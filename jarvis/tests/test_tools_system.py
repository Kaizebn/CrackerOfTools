"""Tests de run_command : l'allowlist bloque tout binaire non autorisé."""

from __future__ import annotations

import sys

import pytest

from jarvis.config import Settings
from jarvis.confirm import AutoConfirmer
from jarvis.events import EventBus
from jarvis.tools.registry import ToolContext
from jarvis.tools.system import RunCommandArgs, run_command


def _ctx() -> ToolContext:
    return ToolContext(
        settings=Settings(command_allowlist="echo"),
        bus=EventBus(),
        confirmer=AutoConfirmer(default=True),
    )


async def test_disallowed_binary_refused() -> None:
    result = await run_command(RunCommandArgs(command="rm -rf /"), _ctx())
    assert not result.ok
    assert "non autorisé" in result.display


@pytest.mark.skipif(sys.platform == "win32", reason="echo POSIX")
async def test_allowed_binary_runs() -> None:
    result = await run_command(RunCommandArgs(command="echo bonjour"), _ctx())
    assert result.ok
    assert "bonjour" in result.display
