"""Tests des outils fichiers : le bac à sable (ALLOWED_PATHS) est bien respecté."""

from __future__ import annotations

from pathlib import Path

from jarvis.config import Settings
from jarvis.confirm import AutoConfirmer
from jarvis.events import EventBus
from jarvis.tools.files import (
    PathArgs,
    SearchFilesArgs,
    WriteFileArgs,
    read_file,
    search_files,
    write_file,
)
from jarvis.tools.registry import ToolContext


def _ctx(root: Path) -> ToolContext:
    settings = Settings(allowed_paths=str(root))
    return ToolContext(settings=settings, bus=EventBus(), confirmer=AutoConfirmer(default=True))


async def test_write_then_read_inside_sandbox(tmp_path: Path) -> None:
    ctx = _ctx(tmp_path)
    target = tmp_path / "note.txt"
    write_result = await write_file(WriteFileArgs(path=str(target), content="bonjour"), ctx)
    assert write_result.ok
    read_result = await read_file(PathArgs(path=str(target)), ctx)
    assert read_result.display == "bonjour"


async def test_access_outside_sandbox_is_refused(tmp_path: Path) -> None:
    ctx = _ctx(tmp_path)
    outside = tmp_path.parent / "secret.txt"
    result = await read_file(PathArgs(path=str(outside)), ctx)
    assert not result.ok
    assert "refusé" in result.display.lower()


async def test_search_finds_file(tmp_path: Path) -> None:
    (tmp_path / "rapport_final.md").write_text("x", encoding="utf-8")
    ctx = _ctx(tmp_path)
    result = await search_files(SearchFilesArgs(query="rapport"), ctx)
    assert result.ok
    assert any("rapport_final" in f for f in result.data["files"])


async def test_no_roots_configured_refuses(tmp_path: Path) -> None:
    ctx = ToolContext(settings=Settings(), bus=EventBus(), confirmer=AutoConfirmer(default=True))
    result = await read_file(PathArgs(path=str(tmp_path / "x")), ctx)
    assert not result.ok
