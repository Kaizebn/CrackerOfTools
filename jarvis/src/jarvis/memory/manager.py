"""Gestionnaire de mémoire : orchestre SQLite + ChromaDB et l'extraction de faits.

Expose une API asynchrone ; les accès SQLite synchrones passent par un thread pour ne
pas bloquer la boucle. L'extraction de faits en arrière-plan utilise un petit modèle
(Haiku) et ne bloque jamais la conversation.
"""

from __future__ import annotations

import asyncio
import json
from datetime import datetime

from jarvis.config import Settings
from jarvis.llm.base import LLMError, LLMProvider, Message
from jarvis.logging_config import get_logger
from jarvis.memory.db import Database, Fact, Reminder
from jarvis.memory.vector import VectorMemory, create_vector_memory

_log = get_logger("jarvis.memory")

_EXTRACTION_SYSTEM = (
    "Tu extrais les faits durables à mémoriser sur l'utilisateur à partir d'une "
    "conversation (préférences, identité, allergies, habitudes, projets). "
    "Réponds en JSON : une liste d'objets {\"fact\": \"...\", \"category\": \"...\"}. "
    "Ignore l'éphémère et le trivial. Si rien n'est à retenir, réponds []."
)


class MemoryManager:
    def __init__(
        self,
        settings: Settings,
        provider: LLMProvider | None = None,
    ) -> None:
        self._settings = settings
        self._db = Database(settings.db_path)
        self._vector: VectorMemory | None = create_vector_memory(
            settings.chroma_path, "paraphrase-multilingual-MiniLM-L12-v2"
        )
        self._provider = provider
        self._conversation_id: int | None = None

    async def start_conversation(self) -> None:
        self._conversation_id = await asyncio.to_thread(self._db.create_conversation)

    async def add_message(self, role: str, content: str) -> None:
        if self._conversation_id is None:
            await self.start_conversation()
        assert self._conversation_id is not None
        await asyncio.to_thread(self._db.add_message, self._conversation_id, role, content)

    # --- Faits ---

    async def remember(self, text: str, category: str = "general") -> int:
        fact_id = await asyncio.to_thread(self._db.add_fact, text, category)
        if self._vector is not None:
            await asyncio.to_thread(self._vector.add, fact_id, text, category)
        return fact_id

    async def recall(self, query: str, k: int | None = None) -> list[str]:
        top_k = k or self._settings.memory_top_k
        if self._vector is not None:
            return await asyncio.to_thread(self._vector.query, query, top_k)
        # Repli : recherche par sous-chaîne dans SQLite.
        facts = await asyncio.to_thread(self._db.list_facts)
        needle = query.lower()
        matches = [f.text for f in facts if needle in f.text.lower()]
        return matches[:top_k] if matches else [f.text for f in facts[:top_k]]

    async def forget(self, fact_id: int) -> bool:
        deleted = await asyncio.to_thread(self._db.delete_fact, fact_id)
        if deleted and self._vector is not None:
            await asyncio.to_thread(self._vector.delete, fact_id)
        return deleted

    async def list_facts(self) -> list[Fact]:
        return await asyncio.to_thread(self._db.list_facts)

    # --- Rappels ---

    async def add_reminder(self, due_at: datetime, message: str, label: str = "") -> int:
        return await asyncio.to_thread(self._db.add_reminder, due_at, message, label)

    async def pending_reminders(self) -> list[Reminder]:
        return await asyncio.to_thread(self._db.pending_reminders)

    async def mark_reminder_fired(self, reminder_id: int) -> None:
        await asyncio.to_thread(self._db.mark_fired, reminder_id)

    async def cancel_reminder(self, reminder_id: int) -> bool:
        return await asyncio.to_thread(self._db.cancel_reminder, reminder_id)

    # --- Journal des outils ---

    async def log_tool_call(self, name: str, arguments: dict[str, object], ok: bool, display: str) -> None:
        payload = json.dumps(arguments, ensure_ascii=False, default=str)
        await asyncio.to_thread(self._db.log_tool_call, name, payload, ok, display)

    # --- Extraction de faits en arrière-plan ---

    async def extract_facts(self, transcript: str) -> None:
        """Extrait et mémorise les faits durables d'une conversation (non bloquant)."""
        if not self._settings.memory_extraction or self._provider is None:
            return
        try:
            raw = await self._provider.complete(
                messages=[Message.user_text(transcript)],
                system=_EXTRACTION_SYSTEM,
                model=self._settings.memory_model,
                max_tokens=512,
            )
        except LLMError as exc:
            _log.warning("memory.extract_failed", error=str(exc))
            return
        for item in _parse_facts(raw):
            await self.remember(item["fact"], item.get("category", "general"))


def _parse_facts(raw: str) -> list[dict[str, str]]:
    start, end = raw.find("["), raw.rfind("]")
    if start == -1 or end == -1:
        return []
    try:
        parsed = json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, list):
        return []
    facts: list[dict[str, str]] = []
    for entry in parsed:
        if isinstance(entry, dict) and isinstance(entry.get("fact"), str):
            facts.append({"fact": entry["fact"], "category": str(entry.get("category", "general"))})
    return facts
