"""Provider Claude (Anthropic) en streaming avec tool use.

On convertit nos messages neutres vers le format Anthropic et on re-émet des
événements neutres, pour que l'orchestrateur ignore tout du SDK.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Sequence
from typing import Any

from jarvis.llm.base import (
    LLMError,
    Message,
    StreamCompleted,
    StreamEvent,
    TextBlock,
    TextDelta,
    ToolResultBlock,
    ToolSchema,
    ToolUseBlock,
    ToolUseReady,
)


def _block_to_anthropic(block: object) -> dict[str, Any]:
    if isinstance(block, TextBlock):
        return {"type": "text", "text": block.text}
    if isinstance(block, ToolUseBlock):
        return {"type": "tool_use", "id": block.id, "name": block.name, "input": block.arguments}
    if isinstance(block, ToolResultBlock):
        return {
            "type": "tool_result",
            "tool_use_id": block.tool_use_id,
            "content": block.content,
            "is_error": block.is_error,
        }
    raise TypeError(f"Bloc inconnu : {block!r}")


def _to_anthropic_messages(messages: Sequence[Message]) -> list[dict[str, Any]]:
    return [
        {"role": m.role, "content": [_block_to_anthropic(b) for b in m.content]}
        for m in messages
    ]


def _to_anthropic_tool(tool: ToolSchema) -> dict[str, Any]:
    return {
        "name": tool.name,
        "description": tool.description,
        "input_schema": tool.input_schema,
    }


class AnthropicProvider:
    def __init__(self, api_key: str, default_model: str, default_max_tokens: int, temperature: float) -> None:
        try:
            import anthropic
        except ImportError as exc:  # pragma: no cover - dépend de l'environnement
            raise LLMError("Le paquet 'anthropic' n'est pas installé.") from exc
        self._anthropic = anthropic
        self._client: Any = anthropic.AsyncAnthropic(api_key=api_key)
        self._model = default_model
        self._max_tokens = default_max_tokens
        self._temperature = temperature

    async def stream(
        self,
        messages: Sequence[Message],
        system: str,
        tools: Sequence[ToolSchema] = (),
        *,
        model: str | None = None,
        max_tokens: int | None = None,
    ) -> AsyncIterator[StreamEvent]:
        kwargs: dict[str, Any] = {
            "model": model or self._model,
            "max_tokens": max_tokens or self._max_tokens,
            "temperature": self._temperature,
            "system": system,
            "messages": _to_anthropic_messages(messages),
        }
        if tools:
            kwargs["tools"] = [_to_anthropic_tool(t) for t in tools]

        text_parts: list[str] = []
        tool_uses: list[ToolUseBlock] = []
        pending: dict[int, dict[str, str]] = {}
        stop_reason = "end_turn"

        try:
            async with self._client.messages.stream(**kwargs) as stream:
                async for event in stream:
                    kind = getattr(event, "type", "")
                    if kind == "content_block_start":
                        block = event.content_block
                        if getattr(block, "type", "") == "tool_use":
                            pending[event.index] = {"id": block.id, "name": block.name, "json": ""}
                    elif kind == "content_block_delta":
                        delta = event.delta
                        dtype = getattr(delta, "type", "")
                        if dtype == "text_delta":
                            text_parts.append(delta.text)
                            yield TextDelta(text=delta.text)
                        elif dtype == "input_json_delta" and event.index in pending:
                            pending[event.index]["json"] += delta.partial_json
                    elif kind == "content_block_stop" and event.index in pending:
                        info = pending.pop(event.index)
                        arguments = json.loads(info["json"] or "{}")
                        use = ToolUseBlock(id=info["id"], name=info["name"], arguments=arguments)
                        tool_uses.append(use)
                        yield ToolUseReady(id=use.id, name=use.name, arguments=use.arguments)
                final = await stream.get_final_message()
                stop_reason = getattr(final, "stop_reason", None) or "end_turn"
        except self._anthropic.APIError as exc:
            raise LLMError(f"Erreur API Anthropic : {exc}") from exc
        except (ConnectionError, OSError) as exc:
            raise LLMError(f"Réseau indisponible : {exc}") from exc

        yield StreamCompleted(stop_reason=stop_reason, text="".join(text_parts), tool_uses=tool_uses)

    async def complete(
        self,
        messages: Sequence[Message],
        system: str,
        *,
        model: str | None = None,
        max_tokens: int | None = None,
    ) -> str:
        try:
            response = await self._client.messages.create(
                model=model or self._model,
                max_tokens=max_tokens or self._max_tokens,
                system=system,
                messages=_to_anthropic_messages(messages),
            )
        except self._anthropic.APIError as exc:
            raise LLMError(f"Erreur API Anthropic : {exc}") from exc
        parts = [block.text for block in response.content if getattr(block, "type", "") == "text"]
        return "".join(parts)
