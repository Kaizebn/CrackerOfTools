"""STT avec faster-whisper. Détection automatique du device (CUDA sinon CPU int8)."""

from __future__ import annotations

import asyncio
from typing import Any

import numpy as np
from numpy.typing import NDArray

from jarvis.config import Settings
from jarvis.logging_config import get_logger

_log = get_logger("jarvis.stt")


def _resolve_device(device: str, compute_type: str) -> tuple[str, str]:
    if device == "auto":
        try:
            import torch

            if torch.cuda.is_available():
                device = "cuda"
            else:
                device = "cpu"
        except Exception:  # noqa: BLE001 - torch absent => CPU
            device = "cpu"
    if compute_type == "auto":
        compute_type = "float16" if device == "cuda" else "int8"
    return device, compute_type


class WhisperSTT:
    def __init__(self, settings: Settings) -> None:
        from faster_whisper import WhisperModel

        device, compute_type = _resolve_device(settings.whisper_device, settings.whisper_compute_type)
        _log.info("stt.loading", model=settings.whisper_model, device=device, compute_type=compute_type)
        self._model: Any = WhisperModel(settings.whisper_model, device=device, compute_type=compute_type)
        self._language = settings.language

    async def transcribe(self, audio: NDArray[np.int16]) -> str:
        def _run() -> str:
            samples = audio.astype(np.float32) / 32768.0
            segments, _info = self._model.transcribe(samples, language=self._language, beam_size=1)
            return " ".join(segment.text.strip() for segment in segments).strip()

        return await asyncio.to_thread(_run)
