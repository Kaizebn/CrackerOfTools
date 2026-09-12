"""Tests de l'EventBus : diffusion, filtrage par type, backpressure, fermeture."""

from __future__ import annotations

import asyncio

from jarvis.events import Event, EventBus, TranscriptReady, WakeDetected


async def test_publish_is_delivered_to_subscriber() -> None:
    bus = EventBus()
    sub = bus.subscribe()
    await bus.publish(WakeDetected(score=0.9))

    event = await asyncio.wait_for(sub.get(), timeout=1.0)
    assert isinstance(event, WakeDetected)
    assert event.score == 0.9
    sub.close()


async def test_subscription_filters_by_type() -> None:
    bus = EventBus()
    sub = bus.subscribe(TranscriptReady)

    await bus.publish(WakeDetected(score=0.1))  # ignoré : mauvais type
    await bus.publish(TranscriptReady(text="salut", language="fr"))

    event = await asyncio.wait_for(sub.get(), timeout=1.0)
    assert isinstance(event, TranscriptReady)
    assert event.text == "salut"
    assert sub.empty()
    sub.close()


async def test_multiple_subscribers_each_receive() -> None:
    bus = EventBus()
    first = bus.subscribe()
    second = bus.subscribe()

    await bus.publish(WakeDetected(score=0.5))

    e1 = await asyncio.wait_for(first.get(), timeout=1.0)
    e2 = await asyncio.wait_for(second.get(), timeout=1.0)
    assert isinstance(e1, WakeDetected)
    assert isinstance(e2, WakeDetected)
    first.close()
    second.close()


async def test_bounded_queue_drops_oldest() -> None:
    bus = EventBus(maxsize=2)
    sub = bus.subscribe()

    await bus.publish(TranscriptReady(text="1", language="fr"))
    await bus.publish(TranscriptReady(text="2", language="fr"))
    await bus.publish(TranscriptReady(text="3", language="fr"))  # évince "1"

    first = await sub.get()
    second = await sub.get()
    assert isinstance(first, TranscriptReady) and first.text == "2"
    assert isinstance(second, TranscriptReady) and second.text == "3"
    assert sub.empty()
    sub.close()


async def test_close_stops_iteration_after_draining() -> None:
    bus = EventBus()
    sub = bus.subscribe()
    await bus.publish(WakeDetected(score=0.5))

    sub.close()

    received: list[Event] = []
    async for event in sub:
        received.append(event)

    # L'événement déjà en file est livré, puis l'itération s'arrête proprement.
    assert len(received) == 1
    assert isinstance(received[0], WakeDetected)


async def test_unsubscribe_stops_further_delivery() -> None:
    bus = EventBus()
    sub = bus.subscribe()
    sub.close()

    await bus.publish(WakeDetected(score=0.5))

    # Après fermeture, plus rien n'arrive (hors la sentinelle déjà consommée).
    async for _ in sub:
        raise AssertionError("aucun événement ne devrait être livré après close()")
