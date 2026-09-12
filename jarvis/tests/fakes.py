"""Doublures pour les tests : LLM scripté et speaker qui capture les phrases."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence

from jarvis.llm.base import Message, StreamEvent, ToolSchema


class FakeLLMProvider:
    """Rejoue une liste de tours (chaque tour = liste d'événements de streaming)."""

    def __init__(self, turns: list[list[StreamEvent]]) -> None:
        self._turns = turns
        self._index = 0

    async def stream(
        self,
        messages: Sequence[Message],
        system: str,
        tools: Sequence[ToolSchema] = (),
        *,
        model: str | None = None,
        max_tokens: int | None = None,
    ) -> AsyncIterator[StreamEvent]:
        events = self._turns[self._index]
        self._index += 1
        for event in events:
            yield event

    async def complete(
        self,
        messages: Sequence[Message],
        system: str,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
    ) -> str:
        return ""


class FakeSpeaker:
    def __init__(self) -> None:
        self.said: list[str] = []
        self.stopped = False

    async def speak(self, text: str) -> None:
        self.said.append(text)

    async def wait(self) -> None:
        return None

    def stop(self) -> None:
        self.stopped = True
