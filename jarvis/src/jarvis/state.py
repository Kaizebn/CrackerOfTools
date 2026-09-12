"""Machine à états explicite du pipeline vocal.

L'état pilote l'animation du HUD et interdit les réentrances : on ne se remet pas
à écouter pendant qu'on parle. Chaque transition légale publie un événement
``StateChanged`` sur l'``EventBus`` si un bus est fourni.
"""

from __future__ import annotations

from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from jarvis.events import EventBus


class State(Enum):
    IDLE = "idle"
    LISTENING = "listening"
    THINKING = "thinking"
    SPEAKING = "speaking"
    ERROR = "error"


class InvalidTransition(RuntimeError):
    """Levée quand une transition d'état interdite est demandée."""

    def __init__(self, current: State, target: State) -> None:
        super().__init__(f"Transition illégale : {current.value} → {target.value}")
        self.current = current
        self.target = target


# Transitions autorisées du parcours nominal. ERROR et le retour ERROR → IDLE
# sont gérés à part car on peut tomber en erreur depuis n'importe quel état.
_ALLOWED: dict[State, frozenset[State]] = {
    State.IDLE: frozenset({State.LISTENING}),
    State.LISTENING: frozenset({State.THINKING, State.IDLE}),
    State.THINKING: frozenset({State.SPEAKING, State.IDLE}),
    # SPEAKING → LISTENING : barge-in, branché en phase 6.
    State.SPEAKING: frozenset({State.IDLE, State.LISTENING}),
    State.ERROR: frozenset({State.IDLE}),
}


class StateMachine:
    def __init__(self, bus: EventBus | None = None, initial: State = State.IDLE) -> None:
        self._bus = bus
        self._state = initial

    @property
    def state(self) -> State:
        return self._state

    def can_transition(self, target: State) -> bool:
        if target is State.ERROR:
            return True
        if target is self._state:
            return False
        return target in _ALLOWED[self._state]

    async def transition(self, target: State) -> None:
        if not self.can_transition(target):
            raise InvalidTransition(self._state, target)
        previous = self._state
        self._state = target
        if self._bus is not None:
            # Import local : casse le cycle state <-> events à l'import du module.
            from jarvis.events import StateChanged

            await self._bus.publish(StateChanged(previous=previous, new=target))
