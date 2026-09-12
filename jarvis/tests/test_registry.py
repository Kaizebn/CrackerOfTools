"""Tests du registre d'outils : schéma, validation, risque, confirmation, dry-run."""

from __future__ import annotations

from pydantic import BaseModel, Field

from jarvis.config import Settings
from jarvis.confirm import AutoConfirmer
from jarvis.events import EventBus
from jarvis.tools.registry import Risk, ToolContext, ToolRegistry, ToolResult

registry = ToolRegistry()


class AddArgs(BaseModel):
    a: int = Field(description="Premier nombre.")
    b: int = Field(description="Second nombre.")


executed: list[str] = []


@registry.tool(name="add", risk=Risk.SAFE)
async def add(args: AddArgs, ctx: ToolContext) -> ToolResult:
    """Additionne deux nombres."""
    executed.append("add")
    return ToolResult.success(str(args.a + args.b), total=args.a + args.b)


@registry.tool(name="danger", risk=Risk.CONFIRM, side_effect=True)
async def danger(args: AddArgs, ctx: ToolContext) -> ToolResult:
    """Action risquée fictive."""
    executed.append("danger")
    return ToolResult.success("fait")


def _ctx(confirm: bool = False, dry_run: bool = False) -> ToolContext:
    return ToolContext(
        settings=Settings(),
        bus=EventBus(),
        confirmer=AutoConfirmer(default=confirm),
        dry_run=dry_run,
    )


def test_schema_generated_from_pydantic() -> None:
    schema = next(s for s in registry.schemas() if s.name == "add")
    assert schema.description == "Additionne deux nombres."
    properties = schema.input_schema["properties"]
    assert isinstance(properties, dict)
    assert set(properties) == {"a", "b"}


async def test_execute_success() -> None:
    result = await registry.execute("add", {"a": 2, "b": 3}, _ctx())
    assert result.ok
    assert result.data["total"] == 5


async def test_validation_error_is_reported() -> None:
    result = await registry.execute("add", {"a": "oops", "b": 3}, _ctx())
    assert not result.ok


async def test_unknown_tool() -> None:
    result = await registry.execute("nope", {}, _ctx())
    assert not result.ok


async def test_confirm_denied_cancels() -> None:
    executed.clear()
    result = await registry.execute("danger", {"a": 1, "b": 1}, _ctx(confirm=False))
    assert not result.ok
    assert result.data.get("cancelled") is True
    assert "danger" not in executed


async def test_confirm_approved_runs() -> None:
    executed.clear()
    result = await registry.execute("danger", {"a": 1, "b": 1}, _ctx(confirm=True))
    assert result.ok
    assert "danger" in executed


async def test_dry_run_skips_side_effect() -> None:
    executed.clear()
    result = await registry.execute("danger", {"a": 1, "b": 1}, _ctx(confirm=True, dry_run=True))
    assert result.ok
    assert result.data.get("dry_run") is True
    assert "danger" not in executed
