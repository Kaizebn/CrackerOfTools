"""Tests de la machine à états : parcours légal, transitions interdites, erreur, events."""

from __future__ import annotations

import asyncio

import pytest

from jarvis.events import EventBus, StateChanged
from jarvis.state import InvalidTransition, State, StateMachine


async def test_nominal_flow() -> None:
    machine = StateMachine()
    assert machine.state is State.IDLE

    await machine.transition(State.LISTENING)
    await machine.transition(State.THINKING)
    await machine.transition(State.SPEAKING)
    await machine.transition(State.IDLE)

    assert machine.state is State.IDLE


async def test_illegal_transition_raises() -> None:
    machine = StateMachine()
    with pytest.raises(InvalidTransition):
        await machine.transition(State.SPEAKING)  # IDLE → SPEAKING interdit
    assert machine.state is State.IDLE  # l'état n'a pas changé


async def test_same_state_transition_is_rejected() -> None:
    machine = StateMachine()
    assert machine.can_transition(State.IDLE) is False
    with pytest.raises(InvalidTransition):
        await machine.transition(State.IDLE)


async def test_error_reachable_from_anywhere() -> None:
    machine = StateMachine()
    await machine.transition(State.LISTENING)
    await machine.transition(State.ERROR)
    assert machine.state is State.ERROR


async def test_error_is_recoverable_to_idle() -> None:
    machine = StateMachine()
    await machine.transition(State.LISTENING)
    await machine.transition(State.ERROR)
    await machine.transition(State.IDLE)
    assert machine.state is State.IDLE


async def test_transition_publishes_state_changed() -> None:
    bus = EventBus()
    sub = bus.subscribe(StateChanged)
    machine = StateMachine(bus)

    await machine.transition(State.LISTENING)

    event = await asyncio.wait_for(sub.get(), timeout=1.0)
    assert isinstance(event, StateChanged)
    assert event.previous is State.IDLE
    assert event.new is State.LISTENING
    sub.close()
