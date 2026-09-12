"""Utilitaires texte : découpage en phrases à la volée et nettoyage pour le TTS.

Le découpage en phrases est au cœur de la latence : on lit une phrase dès qu'elle est
complète pendant que le LLM génère encore la suite, au lieu d'attendre la réponse
entière.
"""

from __future__ import annotations

import re

_SENTENCE_END = re.compile(r"[.!?…](?=\s|$)|[:;]\s|\n")
# Abréviations françaises courantes à ne PAS confondre avec une fin de phrase.
_ABBREVIATIONS = {"m.", "mme.", "dr.", "etc.", "ex.", "cf.", "p.", "fig.", "n°"}

_MARKDOWN_PATTERNS = [
    (re.compile(r"```.*?```", re.DOTALL), " "),  # blocs de code
    (re.compile(r"`([^`]*)`"), r"\1"),            # code inline
    (re.compile(r"\*\*([^*]+)\*\*"), r"\1"),      # gras
    (re.compile(r"\*([^*]+)\*"), r"\1"),          # italique
    (re.compile(r"_([^_]+)_"), r"\1"),            # italique _
    (re.compile(r"^#{1,6}\s*", re.MULTILINE), ""),  # titres
    (re.compile(r"^\s*[-*+]\s+", re.MULTILINE), ""),  # puces
    (re.compile(r"\[([^\]]+)\]\([^)]+\)"), r"\1"),  # liens
]


def strip_markdown(text: str) -> str:
    """Retire le markdown pour que le TTS ne lise pas les astérisques et les dièses."""
    result = text
    for pattern, repl in _MARKDOWN_PATTERNS:
        result = pattern.sub(repl, result)
    # On aplatit tous les blancs (y compris les sauts de ligne) : le TTS ne lit pas de retours.
    return re.sub(r"\s+", " ", result).strip()


class SentenceSplitter:
    """Accumule des fragments de texte et libère les phrases complètes."""

    def __init__(self, min_length: int = 2) -> None:
        self._buffer = ""
        self._min_length = min_length

    def feed(self, chunk: str) -> list[str]:
        """Ajoute un fragment et retourne les phrases désormais complètes."""
        self._buffer += chunk
        sentences: list[str] = []
        search_start = 0
        while True:
            match = _SENTENCE_END.search(self._buffer, search_start)
            if match is None:
                break
            end = match.end()
            candidate = self._buffer[:end].strip()
            if self._is_false_boundary(candidate):
                # Abréviation : on ne coupe pas, on poursuit la recherche APRÈS ce point.
                search_start = end
                continue
            cleaned = strip_markdown(candidate)
            self._buffer = self._buffer[end:]
            search_start = 0
            if len(cleaned) >= self._min_length:
                sentences.append(cleaned)
        return sentences

    def flush(self) -> str | None:
        """Retourne ce qui reste dans le tampon (fin de génération)."""
        remaining = strip_markdown(self._buffer)
        self._buffer = ""
        if len(remaining) >= self._min_length:
            return remaining
        return None

    def _is_false_boundary(self, candidate: str) -> bool:
        last_word = candidate.split()[-1].lower() if candidate.split() else ""
        return last_word in _ABBREVIATIONS
