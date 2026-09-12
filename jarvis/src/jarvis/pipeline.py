"""Pipeline vocal : IDLE → wake word → écoute (VAD) → STT → orchestrateur.

Un seul consommateur lit le micro à la fois (verrou), ce qui évite que la détection du
wake word, l'enregistrement et l'écoute de confirmation se disputent les frames.
L'interruption de la parole (barge-in) se fait par la touche Échap / le raccourci global
(``interrupt``) : le vrai barge-in vocal « par-dessus » la voix demande de l'annulation
d'écho, documentée comme limite connue.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator

import numpy as np
from numpy.typing import NDArray

from jarvis.audio.input import MicrophoneStream
from jarvis.audio.vad import VoiceRecorder
from jarvis.audio.wake import WakeWordDetector
from jarvis.config import Settings
from jarvis.events import EventBus, ListeningStarted, TranscriptReady, WakeDetected
from jarvis.logging_config import get_logger
from jarvis.orchestrator import Orchestrator
from jarvis.speaker import Speaker
from jarvis.state import State, StateMachine
from jarvis.stt.whisper import WhisperSTT

_log = get_logger("jarvis.pipeline")


class VoicePipeline:
    def __init__(
        self,
        settings: Settings,
        bus: EventBus,
        state: StateMachine,
        mic: MicrophoneStream,
        wake: WakeWordDetector,
        recorder: VoiceRecorder,
        stt: WhisperSTT,
        orchestrator: Orchestrator,
        speaker: Speaker,
    ) -> None:
        self._settings = settings
        self._bus = bus
        self._state = state
        self._mic = mic
        self._wake = wake
        self._recorder = recorder
        self._stt = stt
        self._orchestrator = orchestrator
        self._speaker = speaker
        self._lock = asyncio.Lock()
        self._trigger = asyncio.Event()
        self._stop = asyncio.Event()

    def trigger_listen(self) -> None:
        """Force une écoute sans wake word (raccourci global Ctrl+Alt+J)."""
        self._trigger.set()

    def interrupt(self) -> None:
        """Coupe la parole en cours (Échap)."""
        self._speaker.stop()

    def request_stop(self) -> None:
        self._stop.set()

    async def run(self) -> None:
        await self._mic.start()
        _log.info("pipeline.ready")
        try:
            while not self._stop.is_set():
                await self._await_wake()
                if self._stop.is_set():
                    break
                await self._process_turn()
        finally:
            await self._mic.stop()

    async def _await_wake(self) -> None:
        async with self._lock:
            while not self._stop.is_set():
                if self._trigger.is_set():
                    self._trigger.clear()
                    return
                frame = await self._mic.read()
                if self._wake.detect(frame) >= self._settings.wake_threshold:
                    self._wake.reset()
                    await self._bus.publish(WakeDetected(score=1.0))
                    return

    async def _process_turn(self) -> None:
        if self._state.state is State.IDLE:
            await self._state.transition(State.LISTENING)
        await self._bus.publish(ListeningStarted())
        async with self._lock:
            audio = await self._recorder.record(self._frames())
        text = await self._stt.transcribe(audio)
        print(f"🎤 {text}")
        await self._bus.publish(TranscriptReady(text=text, language=self._settings.language))
        await self._orchestrator.handle_user_text(text)

    async def listen_once(self) -> str:
        """Écoute une réponse courte (utilisé par la confirmation vocale)."""
        async with self._lock:
            audio = await self._recorder.record(self._frames())
        return await self._stt.transcribe(audio)

    async def speak_and_wait(self, text: str) -> None:
        await self._speaker.speak(text)
        await self._speaker.wait()

    async def _frames(self) -> AsyncIterator[NDArray[np.int16]]:
        while not self._stop.is_set():
            yield await self._mic.read()
