"""Flux micro : stream 16 kHz mono int16 vers une file asyncio.

Le callback PortAudio tourne dans un thread temps-réel : il ne fait que recopier la
frame et la poster dans la boucle asyncio via ``call_soon_threadsafe`` (thread-safe).
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from typing import Any

import numpy as np
from numpy.typing import NDArray

from jarvis.logging_config import get_logger

_log = get_logger("jarvis.audio.input")


class MicrophoneError(RuntimeError):
    pass


class MicrophoneStream:
    def __init__(self, sample_rate: int = 16000, blocksize: int = 1280, device: int | None = None) -> None:
        self._sample_rate = sample_rate
        self._blocksize = blocksize
        self._device = device
        self._queue: asyncio.Queue[NDArray[np.int16]] = asyncio.Queue()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stream: Any = None

    async def start(self) -> None:
        try:
            import sounddevice as sd
        except OSError as exc:  # PortAudio absent
            raise MicrophoneError(f"Audio indisponible : {exc}") from exc
        self._loop = asyncio.get_running_loop()
        try:
            self._stream = sd.InputStream(
                samplerate=self._sample_rate,
                channels=1,
                dtype="int16",
                blocksize=self._blocksize,
                device=self._device,
                callback=self._callback,
            )
            self._stream.start()
        except Exception as exc:  # noqa: BLE001 - micro absent/occupé
            raise MicrophoneError(f"Impossible d'ouvrir le micro : {exc}") from exc
        _log.info("mic.started", sample_rate=self._sample_rate, blocksize=self._blocksize)

    def _callback(self, indata: Any, frames: int, time_info: Any, status: Any) -> None:
        if status:
            _log.debug("mic.status", status=str(status))
        frame: NDArray[np.int16] = np.array(indata[:, 0], dtype=np.int16)
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._queue.put_nowait, frame)

    async def frames(self) -> AsyncIterator[NDArray[np.int16]]:
        while True:
            yield await self._queue.get()

    async def read(self) -> NDArray[np.int16]:
        return await self._queue.get()

    async def stop(self) -> None:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        _log.info("mic.stopped")
