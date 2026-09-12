"""Configuration globale, chargée une seule fois via pydantic-settings.

Aucun secret n'est en dur : tout passe par l'environnement et le fichier ``.env``.
Les variables portent le préfixe ``JARVIS_`` (sauf ``ANTHROPIC_API_KEY``, nom
conventionnel conservé tel quel).
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        env_prefix="JARVIS_",
        extra="ignore",
    )

    # --- Cerveau (LLM) ---
    anthropic_api_key: str | None = Field(default=None, validation_alias="ANTHROPIC_API_KEY")
    model: str = "claude-sonnet-4-5"
    memory_model: str = "claude-haiku-4-5-20251001"
    max_tokens: int = 1024
    temperature: float = 0.6

    # --- Langue / audio ---
    language: str = "fr"
    sample_rate: int = 16000
    input_device: int | None = None
    output_device: int | None = None

    # --- Wake word ---
    wake_word: str = "hey_jarvis"
    wake_threshold: float = 0.5
    wake_provider: Literal["openwakeword", "porcupine"] = "openwakeword"
    porcupine_access_key: str | None = None

    # --- VAD (fin de phrase) ---
    vad_threshold: float = 0.5
    vad_silence_ms: int = 700
    vad_max_utterance_s: float = 15.0

    # --- STT (faster-whisper) ---
    whisper_model: str = "medium"
    whisper_device: Literal["auto", "cpu", "cuda"] = "auto"
    whisper_compute_type: str = "auto"

    # --- TTS ---
    tts_provider: Literal["piper", "elevenlabs"] = "piper"
    piper_voice: str = "fr_FR-siwis-medium"
    elevenlabs_api_key: str | None = None
    elevenlabs_voice_id: str = "pNInz6obpgDQGcFmaJgB"
    elevenlabs_model: str = "eleven_multilingual_v2"

    # --- Domotique (Home Assistant) ---
    home_assistant_url: str | None = None
    home_assistant_token: str | None = None

    # --- Recherche web ---
    tavily_api_key: str | None = None

    # --- Sécurité / fichiers ---
    # Listes séparées par ';' dans le .env (pratique pour les chemins Windows).
    allowed_paths: str = ""
    command_allowlist: str = "git;python;pip;echo;dir;ipconfig"
    confirm_timeout_s: float = 15.0

    # --- Mémoire ---
    history_max_turns: int = 20
    memory_top_k: int = 5
    memory_extraction: bool = True

    # --- Comportement ---
    user_name: str = "Monsieur"
    address_as_monsieur: bool = False

    # --- Interface ---
    ui_enabled: bool = True
    hotkey: str = "<ctrl>+<alt>+j"
    barge_in: bool = True

    # --- Exécution / données / logs ---
    dry_run: bool = False
    data_dir: Path = Path("data")
    models_dir: Path = Path("models")
    log_level: str = "INFO"
    log_dir: Path = Path("logs")

    @property
    def allowed_roots(self) -> list[Path]:
        """Racines autorisées pour les outils fichiers (sandbox)."""
        return [Path(p.strip()).expanduser() for p in self.allowed_paths.split(";") if p.strip()]

    @property
    def allowed_commands(self) -> list[str]:
        """Binaires autorisés pour run_command."""
        return [c.strip() for c in self.command_allowlist.split(";") if c.strip()]

    @property
    def db_path(self) -> Path:
        return self.data_dir / "jarvis.db"

    @property
    def chroma_path(self) -> Path:
        return self.data_dir / "chroma"

    @property
    def has_anthropic(self) -> bool:
        return bool(self.anthropic_api_key)

    @property
    def has_home_assistant(self) -> bool:
        return bool(self.home_assistant_url and self.home_assistant_token)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
