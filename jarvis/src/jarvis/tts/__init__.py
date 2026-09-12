"""Synthèse vocale (TTS) : abstraction + providers Piper (local) et ElevenLabs."""

from __future__ import annotations

from jarvis.config import Settings
from jarvis.logging_config import get_logger
from jarvis.tts.base import TTSProvider

_log = get_logger("jarvis.tts")


def create_tts(settings: Settings) -> TTSProvider | None:
    """Construit le provider TTS configuré, ou None si indisponible (dégradation)."""
    if settings.tts_provider == "elevenlabs" and settings.elevenlabs_api_key:
        from jarvis.tts.elevenlabs import ElevenLabsTTS

        return ElevenLabsTTS(
            api_key=settings.elevenlabs_api_key,
            voice_id=settings.elevenlabs_voice_id,
            model=settings.elevenlabs_model,
        )
    try:
        from jarvis.tts.piper import PiperTTS

        return PiperTTS.from_settings(settings)
    except Exception as exc:  # noqa: BLE001 - voix indisponible => on le signale, pas de crash
        _log.warning("tts.unavailable", error=str(exc))
        return None
