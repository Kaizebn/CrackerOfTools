"""Provider TTS Piper (local, offline).

Attend les fichiers de voix ``<voice>.onnx`` et ``<voice>.onnx.json`` dans
``<models_dir>/piper/``. Le README explique comment les télécharger.
"""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import numpy as np
from numpy.typing import NDArray

from jarvis.config import Settings


class PiperTTS:
    def __init__(self, model_path: Path) -> None:
        from piper import PiperVoice

        config_path = model_path.with_suffix(model_path.suffix + ".json")
        self._voice: Any = PiperVoice.load(
            str(model_path), config_path=str(config_path) if config_path.exists() else None
        )
        self._sample_rate = int(self._voice.config.sample_rate)

    @classmethod
    def from_settings(cls, settings: Settings) -> PiperTTS:
        model_path = settings.models_dir / "piper" / f"{settings.piper_voice}.onnx"
        if not model_path.exists():
            raise FileNotFoundError(
                f"Voix Piper introuvable : {model_path}. "
                "Télécharge-la (voir README) dans models/piper/."
            )
        return cls(model_path)

    async def synthesize(self, text: str) -> tuple[NDArray[np.int16], int]:
        def _run() -> NDArray[np.int16]:
            raw = b"".join(self._voice.synthesize_stream_raw(text))
            return np.frombuffer(raw, dtype=np.int16)

        pcm = await asyncio.to_thread(_run)
        return pcm, self._sample_rate
