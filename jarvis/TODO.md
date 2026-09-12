# TODO — JARVIS

Suivi de l'avancement, tenu à jour à chaque phase.

## Phase 0 — Fondations ✅
- [x] Structure du repo (src-layout, `src/jarvis/`, `tests/`).
- [x] `config.py` — pydantic-settings, chargé une fois, `.env` + préfixe `JARVIS_`.
- [x] `events.py` — dataclasses d'événements + `EventBus` (pub/sub typé, backpressure).
- [x] `state.py` — machine à états `IDLE/LISTENING/THINKING/SPEAKING/ERROR`.
- [x] `logging_config.py` — structlog → console colorée + fichier JSON rotatif.
- [x] `.env.example`, `.gitignore`, `pyproject.toml`, `requirements.txt` figé.
- [x] `run.py` — démo des fondations lançable.
- [x] `README.md` — installation Windows pas à pas.
- [x] Tests : bus d'événements, machine à états, configuration.
- [x] `mypy --strict src/` passe.

## Phase 1 — Boucle vocale nue
- [ ] `audio/input.py` — stream micro 16 kHz mono (sounddevice).
- [ ] `audio/wake.py` — openWakeWord (backend onnxruntime), fallback Porcupine.
- [ ] `audio/vad.py` — silero-vad (détection de fin de phrase).
- [ ] `stt/whisper.py` — faster-whisper (détection auto cuda/cpu).
- [ ] `tts/base.py` + `tts/piper.py` — lecture d'une réponse en dur.
- [ ] `audio/output.py` — playback + file d'attente TTS.
- [ ] Orchestrateur minimal câblant wake → VAD → STT → console → Piper.
- [ ] Jalon : « Hey Jarvis, bonjour » → réponse vocale, de façon fiable.

## Phase 2 — Cerveau
- [ ] `llm/base.py` — abstraction `LLMProvider` (streaming).
- [ ] `llm/anthropic.py` — Claude en streaming.
- [ ] `llm/prompts.py` — system prompt soigné.
- [ ] Historique en mémoire vive + TTS phrase par phrase pendant la génération.

## Phase 3 — Outils
- [ ] `tools/registry.py` — `@tool`, schéma généré depuis Pydantic, niveaux de risque.
- [ ] Boucle tool_use ↔ tool_result.
- [ ] `tools/system.py`, `tools/web.py`, `tools/timers.py`.
- [ ] Confirmation des actions risquées + journalisation SQLite + `--dry-run`.

## Phase 4 — Mémoire
- [ ] `memory/db.py` (SQLAlchemy), `memory/vector.py` (ChromaDB), `memory/manager.py`.
- [ ] Injection de contexte + extraction de faits en arrière-plan (Haiku) + résumés.
- [ ] `tools/memory_tools.py`.

## Phase 5 — Domotique + fichiers
- [ ] `tools/home.py` — Home Assistant (REST + WebSocket), cache des entités.
- [ ] `tools/files.py` — opérations sandboxées (ALLOWED_PATHS).

## Phase 6 — Interface
- [ ] `ui/tray.py` — icône barre système.
- [ ] `ui/hud.py` — overlay animé (QPainter, 60 fps).
- [ ] Intégration qasync, raccourci global Ctrl+Alt+J, barge-in.

## Phase 7 — Finition
- [ ] Démarrage automatique avec Windows.
- [ ] Packaging PyInstaller (.exe).
- [ ] Robustesse (réseau coupé, micro débranché, API en erreur → retour IDLE).
- [ ] README final avec captures.
