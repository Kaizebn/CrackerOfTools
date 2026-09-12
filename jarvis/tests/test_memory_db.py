"""Tests de la mémoire structurée SQLite (faits, rappels, messages, journal)."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from jarvis.memory.db import Database


def _db(tmp_path: Path) -> Database:
    return Database(tmp_path / "jarvis.db")


def test_facts_crud(tmp_path: Path) -> None:
    db = _db(tmp_path)
    fid = db.add_fact("Allergique aux arachides", "santé")
    facts = db.list_facts()
    assert any(f.id == fid and "arachides" in f.text for f in facts)
    assert db.delete_fact(fid) is True
    assert db.delete_fact(fid) is False


def test_reminders_lifecycle(tmp_path: Path) -> None:
    db = _db(tmp_path)
    due = datetime.now(timezone.utc) + timedelta(minutes=5)
    rid = db.add_reminder(due, "Réunion", "travail")
    pending = db.pending_reminders()
    assert [r.id for r in pending] == [rid]
    db.mark_fired(rid)
    assert db.pending_reminders() == []


def test_messages_and_tool_log(tmp_path: Path) -> None:
    db = _db(tmp_path)
    cid = db.create_conversation()
    db.add_message(cid, "user", "bonjour")
    db.add_message(cid, "assistant", "bonjour Monsieur")
    db.log_tool_call("set_volume", '{"percent": 60}', True, "Volume à 60%.")
    # Pas d'exception = structure et commits OK.
    db.set_summary(cid, "Échange de politesses.")
