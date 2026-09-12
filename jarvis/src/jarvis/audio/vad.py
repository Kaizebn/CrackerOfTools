"""Détection de fin de phrase (endpointing) avec silero-vad.

On enregistre tant que l'utilisateur parle et on s'arrête après un silence suffisant —
sans timeout arbitraire. Le niveau sonore est publié en continu pour animer le HUD.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from typing import Any

import numpy as np
from numpy.typing import NDArray

from jarvis.config import Settings
from jarvis.events import EventBus, MicAmplitude
from jarvis.logging_config import get_logger

_log = get_logger("jarvis.audio.vad")
_WINDOW = 512  # silero attend des fenêtres de 512 échantillons à 16 kHz


class VoiceRecorder:
    def __init__(self, settings: Settings, bus: EventBus | None = None) -> None:
        self._sample_rate = settings.sample_rate
        self._silence_s = settings.vad_silence_ms / 1000.0
        self._max_s = settings.vad_max_utterance_s
        self._threshold = settings.vad_threshold
        self._bus = bus
        self._model: Any = None

    def _ensure_model(self) -> None:
        if self._model is None:
            from silero_vad import load_silero_vad

            self._model = load_silero_vad()

    async def record(self, frames: AsyncIterator[NDArray[np.int16]]) -> NDArray[np.int16]:
        import torch

        self._ensure_model()
        collected: list[NDArray[np.int16]] = []
        pending: NDArray[np.float32] = np.empty(0, dtype=np.float32)
        started = False
        silence_acc = 0.0
        loop = asyncio.get_running_loop()
        start_time = loop.time()

        async for frame in frames:
            collected.append(frame)
            if self._bus is not None:
                await self._bus.publish(MicAmplitude(level=_rms(frame)))

            pending = np.concatenate([pending, frame.astype(np.float32) / 32768.0])
            while pending.size >= _WINDOW:
                chunk = pending[:_WINDOW]
                pending = pending[_WINDOW:]
                prob = float(self._model(torch.from_numpy(chunk), self._sample_rate).item())
                if prob >= self._threshold:
                    started = True
                    silence_acc = 0.0
                elif started:
                    silence_acc += _WINDOW / self._sample_rate

            if started and silence_acc >= self._silence_s:
                break
            if loop.time() - start_time > self._max_s:
                _log.debug("vad.max_utterance")
                break

        if not collected:
            return np.empty(0, dtype=np.int16)
        return np.concatenate(collected).astype(np.int16)


def _rms(frame: NDArray[np.int16]) -> float:
    samples = frame.astype(np.float32) / 32768.0
    level = float(np.sqrt(np.mean(np.square(samples)))) if samples.size else 0.0
    return min(1.0, level * 4.0)
