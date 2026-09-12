"""Assemblage et lancement de JARVIS.

Trois modes :
- ``--text``            : REPL clavier, sans audio ni UI (idéal pour tester le cerveau).
- voix sans UI          : micro + wake word + voix, sans fenêtre.
- voix + UI (défaut)    : idem, plus le tray et le HUD, via une boucle qasync (Qt+asyncio).

Les briques lourdes (Qt, qasync, pynput, audio, Whisper) sont importées paresseusement
pour que l'import du module et le mode texte restent légers.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import TYPE_CHECKING

from jarvis.config import Settings
from jarvis.confirm import AutoConfirmer, ConsoleConfirmer, VoiceConfirmer
from jarvis.events import EventBus
from jarvis.llm.anthropic import AnthropicProvider
from jarvis.llm.base import LLMProvider
from jarvis.logging_config import get_logger
from jarvis.memory.manager import MemoryManager
from jarvis.orchestrator import Orchestrator
from jarvis.speaker import ConsoleSpeaker, Speaker
from jarvis.state import StateMachine
from jarvis.tools.home import HomeAssistantClient
from jarvis.tools.loader import load_registry
from jarvis.tools.registry import ToolContext
from jarvis.tools.timers import TimerManager

if TYPE_CHECKING:
    from jarvis.pipeline import VoicePipeline

_log = get_logger("jarvis.app")


@dataclass
class AppOptions:
    text: bool = False
    ui: bool = True
    dry_run: bool = False


@dataclass
class Core:
    provider: LLMProvider
    orchestrator: Orchestrator
    ctx: ToolContext
    memory: MemoryManager
    home: HomeAssistantClient | None
    timers: TimerManager


class ConfigError(RuntimeError):
    pass


async def _build_core(settings: Settings, options: AppOptions, bus: EventBus, state: StateMachine, speaker: Speaker) -> Core:
    if not settings.has_anthropic:
        raise ConfigError("ANTHROPIC_API_KEY manquante : renseigne-la dans .env (obligatoire dès la Phase 2).")
    provider = AnthropicProvider(
        api_key=settings.anthropic_api_key or "",
        default_model=settings.model,
        default_max_tokens=settings.max_tokens,
        temperature=settings.temperature,
    )
    registry = load_registry()
    memory = MemoryManager(settings, provider)

    home: HomeAssistantClient | None = None
    if settings.has_home_assistant and settings.home_assistant_url and settings.home_assistant_token:
        home = HomeAssistantClient(settings.home_assistant_url, settings.home_assistant_token)
        try:
            await home.connect()
        except Exception as exc:  # noqa: BLE001 - domotique optionnelle
            _log.warning("home.connect_failed", error=str(exc))

    timers = TimerManager(bus, memory)
    ctx = ToolContext(
        settings=settings,
        bus=bus,
        confirmer=AutoConfirmer(default=False),
        dry_run=options.dry_run or settings.dry_run,
        memory=memory,
        home=home,
        timers=timers,
    )
    orchestrator = Orchestrator(settings, bus, state, provider, registry, ctx, speaker, memory, home)
    return Core(provider, orchestrator, ctx, memory, home, timers)


async def run_text(settings: Settings, options: AppOptions) -> None:
    bus = EventBus()
    state = StateMachine(bus)
    speaker = ConsoleSpeaker()
    core = await _build_core(settings, options, bus, state, speaker)
    core.ctx.confirmer = ConsoleConfirmer(settings.confirm_timeout_s)
    await core.orchestrator.start()
    await core.timers.start()

    print("JARVIS (mode texte) — tape ta requête, 'quit' pour sortir.\n")
    try:
        while True:
            try:
                line = await asyncio.to_thread(input, "› ")
            except (EOFError, KeyboardInterrupt):
                break
            if line.strip().lower() in {"quit", "exit", ":q"}:
                break
            await core.orchestrator.handle_user_text(line)
    finally:
        await _shutdown(core)


async def _assemble_voice(
    settings: Settings, options: AppOptions, bus: EventBus, state: StateMachine
) -> tuple["VoicePipeline", Core, Speaker]:
    from jarvis.audio.input import MicrophoneStream
    from jarvis.audio.output import AudioSpeaker
    from jarvis.audio.vad import VoiceRecorder
    from jarvis.audio.wake import create_wake_detector
    from jarvis.pipeline import VoicePipeline
    from jarvis.stt.whisper import WhisperSTT
    from jarvis.tts import create_tts

    tts = create_tts(settings)
    speaker: Speaker
    if tts is not None:
        audio_speaker = AudioSpeaker(tts, settings.output_device)
        await audio_speaker.start()
        speaker = audio_speaker
    else:
        _log.warning("tts.missing", note="Pas de voix — bascule en sortie console.")
        speaker = ConsoleSpeaker()

    core = await _build_core(settings, options, bus, state, speaker)

    mic = MicrophoneStream(settings.sample_rate, blocksize=1280, device=settings.input_device)
    wake = create_wake_detector(settings)
    recorder = VoiceRecorder(settings, bus)
    stt = WhisperSTT(settings)
    pipeline = VoicePipeline(settings, bus, state, mic, wake, recorder, stt, core.orchestrator, speaker)

    core.ctx.confirmer = VoiceConfirmer(
        speak=pipeline.speak_and_wait,
        listen=pipeline.listen_once,
        bus=bus,
        timeout_s=settings.confirm_timeout_s,
    )
    await core.orchestrator.start()
    await core.timers.start()
    return pipeline, core, speaker


async def run_voice_headless(settings: Settings, options: AppOptions) -> None:
    bus = EventBus()
    state = StateMachine(bus)
    pipeline, core, _speaker = await _assemble_voice(settings, options, bus, state)
    try:
        await pipeline.run()
    finally:
        await _shutdown(core)


def run_with_qt(settings: Settings, options: AppOptions) -> None:
    import qasync
    from PySide6 import QtWidgets

    from jarvis.ui.bridge import run_ui_bridge
    from jarvis.ui.hud import HUDWindow
    from jarvis.ui.tray import TrayIcon

    app = QtWidgets.QApplication.instance() or QtWidgets.QApplication([])
    app.setQuitOnLastWindowClosed(False)
    loop = qasync.QEventLoop(app)
    asyncio.set_event_loop(loop)

    bus = EventBus()
    state = StateMachine(bus)

    async def _bootstrap() -> None:
        pipeline, core, _speaker = await _assemble_voice(settings, options, bus, state)
        hud = HUDWindow()
        hud.show()
        paused = {"value": False}

        def _toggle_pause() -> None:
            paused["value"] = not paused["value"]
            tray.set_paused(paused["value"])
            if paused["value"]:
                pipeline.request_stop()

        def _quit() -> None:
            pipeline.request_stop()
            app.quit()

        def _open_logs() -> None:
            _log.info("ui.open_logs", path=str(settings.log_dir))

        tray = TrayIcon(on_toggle_pause=_toggle_pause, on_quit=_quit, on_open_logs=_open_logs)
        bridge = asyncio.ensure_future(run_ui_bridge(bus, hud, tray))
        _install_hotkeys(settings, loop, pipeline)
        try:
            await pipeline.run()
        finally:
            bridge.cancel()
            await _shutdown(core)

    with loop:
        loop.run_until_complete(_bootstrap())


def _install_hotkeys(settings: Settings, loop: asyncio.AbstractEventLoop, pipeline: "VoicePipeline") -> None:
    try:
        from pynput import keyboard
    except Exception as exc:  # noqa: BLE001 - raccourcis optionnels
        _log.warning("hotkeys.unavailable", error=str(exc))
        return

    def _on_trigger() -> None:
        loop.call_soon_threadsafe(pipeline.trigger_listen)

    hotkeys = keyboard.GlobalHotKeys({settings.hotkey: _on_trigger})
    hotkeys.start()

    def _on_press(key: object) -> None:
        if key == keyboard.Key.esc:
            loop.call_soon_threadsafe(pipeline.interrupt)

    listener = keyboard.Listener(on_press=_on_press)
    listener.start()
    _log.info("hotkeys.installed", trigger=settings.hotkey)


async def _shutdown(core: Core) -> None:
    await core.orchestrator.stop()
    await core.timers.shutdown()
    if core.home is not None:
        await core.home.shutdown()
