"""Détection du mot-clé « Hey Jarvis » via openWakeWord (fallback Porcupine)."""

from __future__ import annotations

from typing import Any, Protocol

import numpy as np
from numpy.typing import NDArray

from jarvis.config import Settings
from jarvis.logging_config import get_logger

_log = get_logger("jarvis.audio.wake")


class WakeWordDetector(Protocol):
    def detect(self, frame: NDArray[np.int16]) -> float:
        """Retourne le score de détection (0..1) pour la frame fournie."""
        ...

    def reset(self) -> None: ...


class OpenWakeWordDetector:
    def __init__(self, threshold: float) -> None:
        from openwakeword.model import Model

        try:
            from openwakeword.utils import download_models

            download_models()
        except Exception as exc:  # noqa: BLE001 - modèles déjà présents ou hors-ligne
            _log.debug("wake.download_skipped", error=str(exc))
        self._model: Any = Model()
        self._threshold = threshold

    def detect(self, frame: NDArray[np.int16]) -> float:
        scores = self._model.predict(frame)
        return max((float(v) for v in scores.values()), default=0.0)

    def reset(self) -> None:
        self._model.reset()


class PorcupineDetector:
    def __init__(self, access_key: str, threshold: float) -> None:
        import pvporcupine

        self._porcupine: Any = pvporcupine.create(access_key=access_key, keywords=["jarvis"])
        self._threshold = threshold

    def detect(self, frame: NDArray[np.int16]) -> float:
        index = self._porcupine.process(frame)
        return 1.0 if index >= 0 else 0.0

    def reset(self) -> None:
        return None


def create_wake_detector(settings: Settings) -> WakeWordDetector:
    if settings.wake_provider == "porcupine" and settings.porcupine_access_key:
        return PorcupineDetector(settings.porcupine_access_key, settings.wake_threshold)
    return OpenWakeWordDetector(settings.wake_threshold)
