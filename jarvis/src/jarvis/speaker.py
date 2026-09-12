"""Abstraction ``Speaker`` : ce qui dit les phrases à voix haute (ou les affiche).

L'orchestrateur ne dépend que de ce contrat. En mode vocal, l'implémentation est le
playback audio (TTS). En mode texte/headless, on se contente d'afficher le texte.
"""

from __future__ import annotations

from typing import Protocol


class Speaker(Protocol):
    async def speak(self, text: str) -> None:
        """Énonce (ou affiche) une phrase."""
        ...

    async def wait(self) -> None:
        """Attend la fin de l'énonciation en cours."""
        ...

    def stop(self) -> None:
        """Interrompt immédiatement (barge-in)."""
        ...


class ConsoleSpeaker:
    """Speaker de secours : écrit la réponse sur la console (mode --text)."""

    async def speak(self, text: str) -> None:
        print(f"\n🗣️  {text}")

    async def wait(self) -> None:
        return None

    def stop(self) -> None:
        return None
