"""Abstraction ``LLMProvider`` et représentation neutre des messages.

L'orchestrateur ne manipule que ces types ; brancher OpenAI plus tard se fait en
écrivant un nouveau provider qui convertit ces structures vers son propre format,
sans toucher à l'orchestrateur.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from dataclasses import dataclass, field
from typing import Literal, Protocol


@dataclass(frozen=True)
class TextBlock:
    text: str


@dataclass(frozen=True)
class ToolUseBlock:
    id: str
    name: str
    arguments: dict[str, object]


@dataclass(frozen=True)
class ToolResultBlock:
    tool_use_id: str
    content: str
    is_error: bool = False


ContentBlock = TextBlock | ToolUseBlock | ToolResultBlock


@dataclass(frozen=True)
class Message:
    role: Literal["user", "assistant"]
    content: list[ContentBlock]

    @classmethod
    def user_text(cls, text: str) -> Message:
        return cls(role="user", content=[TextBlock(text=text)])

    @classmethod
    def assistant_text(cls, text: str) -> Message:
        return cls(role="assistant", content=[TextBlock(text=text)])


@dataclass(frozen=True)
class ToolSchema:
    """Schéma d'un outil exposé au LLM (format neutre, converti par le provider)."""

    name: str
    description: str
    input_schema: dict[str, object]


# --- Événements de streaming émis par un provider ---


@dataclass(frozen=True)
class TextDelta:
    text: str


@dataclass(frozen=True)
class ToolUseReady:
    id: str
    name: str
    arguments: dict[str, object]


@dataclass(frozen=True)
class StreamCompleted:
    stop_reason: str
    text: str
    tool_uses: list[ToolUseBlock] = field(default_factory=list)


StreamEvent = TextDelta | ToolUseReady | StreamCompleted


class LLMError(RuntimeError):
    """Erreur remontée par un provider (réseau, API, quota…)."""


class LLMProvider(Protocol):
    """Contrat minimal d'un fournisseur de LLM en streaming avec tool use."""

    def stream(
        self,
        messages: Sequence[Message],
        system: str,
        tools: Sequence[ToolSchema] = (),
        *,
        model: str | None = None,
        max_tokens: int | None = None,
    ) -> AsyncIterator[StreamEvent]:
        """Diffuse la réponse. Émet des TextDelta, des ToolUseReady, puis StreamCompleted."""
        ...

    async def complete(
        self,
        messages: Sequence[Message],
        system: str,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
    ) -> str:
        """Réponse non-streaming (utilisée en arrière-plan pour la mémoire)."""
        ...
