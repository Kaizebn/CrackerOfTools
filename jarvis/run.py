"""Point d'entrée de JARVIS.

Phase 0 : il n'y a ni micro, ni LLM. Ce script prouve que les fondations tournent —
configuration, logs, bus d'événements et machine à états — en simulant un tour vocal
complet (wake word → écoute → réflexion → réponse) sans matériel.
"""

from __future__ import annotations

import asyncio

from jarvis.config import get_settings
from jarvis.events import AssistantSentence, EventBus, TranscriptReady, WakeDetected
from jarvis.logging_config import configure_logging, get_logger
from jarvis.state import State, StateMachine


async def _run() -> None:
    settings = get_settings()
    configure_logging(settings.log_level, settings.log_dir)
    log = get_logger("jarvis.boot")

    bus = EventBus()
    machine = StateMachine(bus)

    log.info(
        "jarvis.starting",
        model=settings.model,
        language=settings.language,
        dry_run=settings.dry_run,
    )

    # Un traceur s'abonne à tout et journalise chaque événement qui passe sur le bus.
    subscription = bus.subscribe()

    async def trace() -> None:
        async for event in subscription:
            log.info("event", kind=type(event).__name__, payload=repr(event))

    tracer = asyncio.create_task(trace())

    await bus.publish(WakeDetected(score=0.92))
    await machine.transition(State.LISTENING)
    await machine.transition(State.THINKING)
    await bus.publish(TranscriptReady(text="Bonjour Jarvis", language=settings.language))
    await machine.transition(State.SPEAKING)
    await bus.publish(AssistantSentence(text="Bonjour. Les fondations sont opérationnelles."))
    await machine.transition(State.IDLE)

    subscription.close()
    await tracer
    log.info("jarvis.ready", note="Phase 0 — fondations validées")


def main() -> None:
    asyncio.run(_run())


if __name__ == "__main__":
    main()
