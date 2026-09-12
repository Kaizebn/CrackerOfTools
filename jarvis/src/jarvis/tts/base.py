"""Contrat d'un provider TTS : texte → PCM mono int16 + fréquence d'échantillonnage."""

from __future__ import annotations

from typing import Protocol

import numpy as np
from numpy.typing import NDArray


class TTSProvider(Protocol):
    async def synthesize(self, text: str) -> tuple[NDArray[np.int16], int]:
        """Retourne l'audio (PCM mono int16) et sa fréquence d'échantillonnage."""
        ...
