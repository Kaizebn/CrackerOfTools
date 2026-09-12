"""Provider TTS ElevenLabs (optionnel, voix plus « JARVIS »).

Demande du PCM 16 kHz directement pour éviter tout décodage mp3 côté client.
"""

from __future__ import annotations

import aiohttp
import numpy as np
from numpy.typing import NDArray

_SAMPLE_RATE = 16000
_TIMEOUT = aiohttp.ClientTimeout(total=30)


class ElevenLabsTTS:
    def __init__(self, api_key: str, voice_id: str, model: str) -> None:
        self._api_key = api_key
        self._voice_id = voice_id
        self._model = model

    async def synthesize(self, text: str) -> tuple[NDArray[np.int16], int]:
        url = (
            f"https://api.elevenlabs.io/v1/text-to-speech/{self._voice_id}"
            f"?output_format=pcm_{_SAMPLE_RATE}"
        )
        headers = {"xi-api-key": self._api_key, "Content-Type": "application/json"}
        payload = {"text": text, "model_id": self._model}
        async with aiohttp.ClientSession(timeout=_TIMEOUT, headers=headers) as session:
            async with session.post(url, json=payload) as response:
                response.raise_for_status()
                data = await response.read()
        pcm = np.frombuffer(data, dtype=np.int16)
        return pcm, _SAMPLE_RATE
