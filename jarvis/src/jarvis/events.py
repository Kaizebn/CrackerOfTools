"""Bus d'événements asyncio et dataclasses d'événements typées.

Tous les composants du pipeline communiquent via l'``EventBus`` : ils publient des
événements et s'abonnent à ceux qui les intéressent. L'UI ne connaît que le bus,
jamais la logique métier.

Un abonnement (``Subscription``) est une file asyncio ; on peut itérer dessus avec
``async for`` ou appeler ``get()``. La fermeture d'un abonnement débloque proprement
un itérateur en attente.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from time import time
from types import TracebackType
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from jarvis.state import State


@dataclass(frozen=True)
class Event:
    """Événement de base ; l'horodatage est posé à la création."""

    timestamp: float = field(default_factory=time, kw_only=True)


@dataclass(frozen=True)
class WakeDetected(Event):
    score: float


@dataclass(frozen=True)
class SpeechStarted(Event):
    pass


@dataclass(frozen=True)
class SpeechEnded(Event):
    duration_s: float


@dataclass(frozen=True)
class TranscriptReady(Event):
    text: str
    language: str


@dataclass(frozen=True)
class AssistantChunk(Event):
    """Fragment de texte brut émis par le LLM en streaming."""

    text: str


@dataclass(frozen=True)
class AssistantSentence(Event):
    """Phrase complète prête à être lue par le TTS."""

    text: str


@dataclass(frozen=True)
class ToolCalled(Event):
    name: str
    arguments: dict[str, object]


@dataclass(frozen=True)
class ToolSucceeded(Event):
    name: str
    display: str


@dataclass(frozen=True)
class ToolFailed(Event):
    name: str
    error: str


@dataclass(frozen=True)
class StateChanged(Event):
    previous: State
    new: State


@dataclass(frozen=True)
class ErrorOccurred(Event):
    message: str
    recoverable: bool = True


# Sentinelle poussée dans la file d'un abonnement fermé pour débloquer un itérateur.
_SHUTDOWN = Event()


class Subscription:
    """Flux d'événements filtré, adossé à une file asyncio."""

    def __init__(
        self,
        bus: EventBus,
        event_types: tuple[type[Event], ...],
        maxsize: int,
    ) -> None:
        self._bus = bus
        self._event_types = event_types
        self._queue: asyncio.Queue[Event] = asyncio.Queue(maxsize)
        self._open = True

    def _matches(self, event: Event) -> bool:
        # Sans type déclaré, l'abonnement reçoit tout.
        return not self._event_types or isinstance(event, self._event_types)

    def _offer(self, event: Event) -> None:
        if not self._open or not self._matches(event):
            return
        if self._queue.maxsize and self._queue.full():
            # Backpressure : on évince le plus ancien pour préserver le flux récent
            # (utile quand les chunks audio arrivent plus vite qu'on ne les consomme).
            self._queue.get_nowait()
        self._queue.put_nowait(event)

    async def get(self) -> Event:
        return await self._queue.get()

    def empty(self) -> bool:
        return self._queue.empty()

    def __aiter__(self) -> Subscription:
        return self

    async def __anext__(self) -> Event:
        if not self._open and self._queue.empty():
            raise StopAsyncIteration
        event = await self._queue.get()
        if event is _SHUTDOWN:
            raise StopAsyncIteration
        return event

    def close(self) -> None:
        if self._open:
            self._open = False
            if not (self._queue.maxsize and self._queue.full()):
                self._queue.put_nowait(_SHUTDOWN)
        self._bus._unsubscribe(self)

    def __enter__(self) -> Subscription:
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        self.close()


class EventBus:
    def __init__(self, maxsize: int = 0) -> None:
        self._subscriptions: list[Subscription] = []
        self._maxsize = maxsize

    def subscribe(self, *event_types: type[Event]) -> Subscription:
        """S'abonne aux types donnés (aucun type = tous les événements)."""
        sub = Subscription(self, event_types, self._maxsize)
        self._subscriptions.append(sub)
        return sub

    async def publish(self, event: Event) -> None:
        # Copie défensive : un abonné peut se désinscrire pendant la diffusion.
        for sub in list(self._subscriptions):
            sub._offer(event)

    def _unsubscribe(self, sub: Subscription) -> None:
        if sub in self._subscriptions:
            self._subscriptions.remove(sub)
