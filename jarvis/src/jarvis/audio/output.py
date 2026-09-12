"""Playback TTS : file d'attente de phrases lues séquentiellement, interruptible.

Implémente le protocole ``Speaker``. ``stop()`` coupe la lecture en cours et vide la
file (barge-in). La synthèse (TTS) et la lecture (PortAudio) sont bloquantes : elles
tournent dans des threads.
"""

from __future__ import annotations

import asyncio

import numpy as np
from numpy.typing import NDArray

from jarvis.logging_config import get_logger
from jarvis.tts.base import TTSProvider

_log = get_logger("jarvis.audio.output")


class AudioSpeaker:
    def __init__(self, tts: TTSProvider, device: int | None = None) -> None:
        self._tts = tts
        self._device = device
        self._queue: asyncio.Queue[tuple[NDArray[np.int16], int]] = asyncio.Queue()
        self._player: asyncio.Task[None] | None = None
        self._idle = asyncio.Event()
        self._idle.set()
        self._interrupt = False

    async def start(self) -> None:
        self._player = asyncio.create_task(self._run())

    async def speak(self, text: str) -> None:
        try:
            pcm, sample_rate = await self._tts.synthesize(text)
        except Exception as exc:  # noqa: BLE001 - une phrase ratée ne doit pas tout casser
            _log.warning("tts.synthesis_failed", error=str(exc))
            return
        self._interrupt = False
        self._idle.clear()
        await self._queue.put((pcm, sample_rate))

    async def _run(self) -> None:
        while True:
            pcm, sample_rate = await self._queue.get()
            if not self._interrupt:
                await asyncio.to_thread(self._play, pcm, sample_rate)
            self._queue.task_done()
            if self._queue.empty():
                self._idle.set()

    def _play(self, pcm: NDArray[np.int16], sample_rate: int) -> None:
        import sounddevice as sd

        sd.play(pcm, samplerate=sample_rate, device=self._device)
        sd.wait()

    async def wait(self) -> None:
        await self._idle.wait()

    def stop(self) -> None:
        self._interrupt = True
        try:
            import sounddevice as sd

            sd.stop()
        except Exception as exc:  # noqa: BLE001 - stop best-effort
            _log.debug("tts.stop_failed", error=str(exc))
        while not self._queue.empty():
            self._queue.get_nowait()
            self._queue.task_done()
        self._idle.set()

    async def shutdown(self) -> None:
        if self._player is not None:
            self._player.cancel()
