"""Registre d'outils : décorateur ``@tool``, niveaux de risque, schémas générés.

Chaque outil déclare son modèle d'arguments Pydantic ; le JSON Schema envoyé au LLM en
est dérivé (jamais réécrit à la main). Le registre valide les arguments, gère la
confirmation des actions risquées, le mode dry-run et la journalisation.
"""

from __future__ import annotations

import inspect
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass, field
from enum import Enum
from typing import TYPE_CHECKING, Any, cast, get_type_hints

from pydantic import BaseModel, ValidationError

from jarvis.config import Settings
from jarvis.events import EventBus, ToolCalled, ToolFailed, ToolSucceeded
from jarvis.llm.base import ToolSchema
from jarvis.logging_config import get_logger

if TYPE_CHECKING:
    from jarvis.confirm import Confirmer
    from jarvis.memory.manager import MemoryManager
    from jarvis.tools.home import HomeAssistantClient
    from jarvis.tools.timers import TimerManager

_log = get_logger("jarvis.tools")


class EmptyArgs(BaseModel):
    """Outil sans argument."""


class Risk(Enum):
    SAFE = "safe"
    CONFIRM = "confirm"
    FORBIDDEN = "forbidden"


@dataclass
class ToolResult:
    ok: bool
    display: str = ""
    data: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def success(cls, display: str = "", **data: Any) -> ToolResult:
        return cls(ok=True, display=display, data=data)

    @classmethod
    def fail(cls, display: str, **data: Any) -> ToolResult:
        return cls(ok=False, display=display, data=data)

    def to_llm(self) -> str:
        """Sérialise le résultat en texte court pour le tool_result renvoyé au LLM."""
        if self.data:
            import json

            payload = json.dumps(self.data, ensure_ascii=False, default=str)
            return f"{self.display} {payload}".strip() if self.display else payload
        return self.display or ("ok" if self.ok else "échec")


@dataclass
class ToolContext:
    """Dépendances passées à chaque outil à l'exécution."""

    settings: Settings
    bus: EventBus
    confirmer: Confirmer
    dry_run: bool = False
    memory: MemoryManager | None = None
    home: HomeAssistantClient | None = None
    timers: TimerManager | None = None


ToolFunc = Callable[[Any, ToolContext], Awaitable[ToolResult]]


@dataclass
class Tool:
    name: str
    description: str
    risk: Risk
    args_model: type[BaseModel]
    func: ToolFunc
    side_effect: bool
    confirm_prompt: Callable[[Any], str] | None = None

    def to_schema(self) -> ToolSchema:
        return ToolSchema(
            name=self.name,
            description=self.description,
            input_schema=self.args_model.model_json_schema(),
        )


def _extract_args_model(func: ToolFunc) -> type[BaseModel]:
    signature = inspect.signature(func)
    params = list(signature.parameters)
    if not params:
        raise TypeError(f"{func.__name__} doit accepter (args, ctx).")
    hints = get_type_hints(func)
    first = params[0]
    model = hints.get(first)
    if model is None or not isinstance(model, type) or not issubclass(model, BaseModel):
        raise TypeError(f"{func.__name__} : le 1er paramètre doit être annoté par un modèle Pydantic.")
    return cast("type[BaseModel]", model)


class ToolRegistry:
    def __init__(self) -> None:
        self._tools: dict[str, Tool] = {}

    def tool(
        self,
        *,
        name: str,
        risk: Risk = Risk.SAFE,
        side_effect: bool = False,
        description: str | None = None,
        confirm_prompt: Callable[[Any], str] | None = None,
    ) -> Callable[[ToolFunc], ToolFunc]:
        def decorator(func: ToolFunc) -> ToolFunc:
            model = _extract_args_model(func)
            desc = (description or inspect.getdoc(func) or "").strip()
            if not desc:
                raise ValueError(f"L'outil {name} doit avoir une description (docstring).")
            self._tools[name] = Tool(
                name=name,
                description=desc,
                risk=risk,
                args_model=model,
                func=func,
                side_effect=side_effect,
                confirm_prompt=confirm_prompt,
            )
            return func

        return decorator

    def get(self, name: str) -> Tool | None:
        return self._tools.get(name)

    def all(self) -> Sequence[Tool]:
        return list(self._tools.values())

    def schemas(self) -> list[ToolSchema]:
        """Schémas exposés au LLM (les outils FORBIDDEN sont masqués)."""
        return [t.to_schema() for t in self._tools.values() if t.risk is not Risk.FORBIDDEN]

    async def execute(self, name: str, raw_args: dict[str, Any], ctx: ToolContext) -> ToolResult:
        tool = self._tools.get(name)
        if tool is None:
            return ToolResult.fail(f"Outil inconnu : {name}.")
        if tool.risk is Risk.FORBIDDEN:
            return ToolResult.fail(f"L'outil {name} est interdit.")

        try:
            args = tool.args_model.model_validate(raw_args)
        except ValidationError as exc:
            return ToolResult.fail(f"Arguments invalides pour {name} : {exc.errors()}")

        if tool.risk is Risk.CONFIRM:
            prompt = tool.confirm_prompt(args) if tool.confirm_prompt else f"Tu confirmes l'action {name} ?"
            if not await ctx.confirmer.confirm(prompt):
                return ToolResult(ok=False, display="Action annulée.", data={"cancelled": True})

        await ctx.bus.publish(ToolCalled(name=name, arguments=raw_args))

        if ctx.dry_run and (tool.risk is Risk.CONFIRM or tool.side_effect):
            result = ToolResult.success(f"[dry-run] {name} simulé.", dry_run=True)
        else:
            result = await self._invoke(tool, args, ctx)

        await self._log_call(ctx, name, raw_args, result)
        if result.ok:
            await ctx.bus.publish(ToolSucceeded(name=name, display=result.display))
        else:
            await ctx.bus.publish(ToolFailed(name=name, error=result.display))
        return result

    async def _invoke(self, tool: Tool, args: BaseModel, ctx: ToolContext) -> ToolResult:
        # On encapsule l'exécution : un outil qui lève ne doit pas tuer l'orchestrateur,
        # l'erreur est renvoyée au LLM comme un résultat exploitable.
        try:
            return await tool.func(args, ctx)
        except Exception as exc:  # noqa: BLE001 - remonté au LLM, pas avalé
            _log.warning("tool.error", tool=tool.name, error=str(exc))
            return ToolResult.fail(f"Erreur pendant {tool.name} : {exc}")

    async def _log_call(
        self, ctx: ToolContext, name: str, raw_args: dict[str, Any], result: ToolResult
    ) -> None:
        _log.info("tool.call", tool=name, args=raw_args, ok=result.ok, display=result.display)
        if ctx.memory is not None:
            await ctx.memory.log_tool_call(name, raw_args, result.ok, result.display)


# Registre global : les modules d'outils s'y enregistrent à l'import via @tool.
registry = ToolRegistry()
tool = registry.tool
