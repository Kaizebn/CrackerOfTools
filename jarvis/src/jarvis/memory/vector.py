"""Mémoire vectorielle : ChromaDB + embeddings locaux (sentence-transformers).

Aucun appel API pour les embeddings. Si ChromaDB ou le modèle d'embeddings ne sont pas
disponibles, ``create_vector_memory`` renvoie None et la mémoire retombe sur une
recherche par sous-chaîne dans SQLite (dégradation propre).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from jarvis.logging_config import get_logger

_log = get_logger("jarvis.memory.vector")


class VectorMemory:
    def __init__(self, path: Path, model_name: str) -> None:
        import chromadb
        from chromadb.utils import embedding_functions

        path.mkdir(parents=True, exist_ok=True)
        embedding = embedding_functions.SentenceTransformerEmbeddingFunction(model_name=model_name)
        self._client: Any = chromadb.PersistentClient(path=str(path))
        self._collection: Any = self._client.get_or_create_collection(
            name="facts", embedding_function=embedding
        )

    def add(self, fact_id: int, text: str, category: str) -> None:
        self._collection.add(ids=[str(fact_id)], documents=[text], metadatas=[{"category": category}])

    def query(self, text: str, k: int) -> list[str]:
        result = self._collection.query(query_texts=[text], n_results=k)
        documents = result.get("documents") or [[]]
        return [str(doc) for doc in documents[0]]

    def delete(self, fact_id: int) -> None:
        self._collection.delete(ids=[str(fact_id)])


def create_vector_memory(path: Path, model_name: str) -> VectorMemory | None:
    try:
        return VectorMemory(path, model_name)
    except Exception as exc:  # noqa: BLE001 - dépend de l'installation, on dégrade
        _log.warning("vector.unavailable", error=str(exc))
        return None
