"""Tests de la configuration : valeurs par défaut et parsing des listes ';'."""

from __future__ import annotations

from pathlib import Path

from jarvis.config import Settings


def test_defaults() -> None:
    settings = Settings()
    assert settings.model == "claude-sonnet-4-5"
    assert settings.language == "fr"
    assert settings.tts_provider == "piper"
    assert settings.dry_run is False
    assert settings.allowed_roots == []
    assert settings.allowed_commands == []


def test_allowed_roots_parsing() -> None:
    settings = Settings(allowed_paths="/tmp/docs ; /tmp/projets")
    assert settings.allowed_roots == [Path("/tmp/docs"), Path("/tmp/projets")]


def test_allowed_commands_parsing() -> None:
    settings = Settings(command_allowlist="git;python; notepad ")
    assert settings.allowed_commands == ["git", "python", "notepad"]
