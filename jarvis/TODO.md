# TODO — JARVIS

Légende : ✅ fait & testé (Linux headless) · 🪟 implémenté, à valider sur Windows réel.

## Phase 0 — Fondations ✅
- [x] Structure src-layout, `config.py`, `events.py` (EventBus), `state.py`, logs structlog.
- [x] `.env.example`, `.gitignore`, `pyproject.toml`, `requirements.txt`, tests, `mypy --strict`.

## Phase 1 — Boucle vocale nue 🪟
- [x] `audio/input.py` (micro 16 kHz), `audio/wake.py` (openWakeWord + fallback Porcupine).
- [x] `audio/vad.py` (silero endpointing), `stt/whisper.py` (faster-whisper, device auto).
- [x] `tts/{base,piper,elevenlabs}.py`, `audio/output.py` (playback + file, interruptible).
- [x] `pipeline.py` : wake → VAD → STT → console + orchestrateur.
- [ ] À valider sur Windows : micro réel, modèles téléchargés, latence.

## Phase 2 — Cerveau ✅
- [x] `llm/base.py` (abstraction + messages neutres), `llm/anthropic.py` (streaming + tool use).
- [x] `llm/prompts.py` (personnalité + contexte injecté).
- [x] Historique multi-tours, TTS phrase par phrase (`text.SentenceSplitter`). Testé via mock LLM.

## Phase 3 — Outils ✅
- [x] `tools/registry.py` : `@tool`, schéma Pydantic, risques, dry-run, journalisation.
- [x] Boucle tool_use ↔ tool_result (orchestrateur). Testée de bout en bout.
- [x] `tools/system.py`, `tools/web.py`, `tools/timers.py`.
- [x] Confirmation des actions risquées (vocale + console + auto), testée.

## Phase 4 — Mémoire ✅
- [x] `memory/db.py` (SQLAlchemy), `memory/vector.py` (ChromaDB), `memory/manager.py`.
- [x] Injection de contexte, extraction de faits en arrière-plan (Haiku), repli sans ChromaDB.
- [x] `tools/memory_tools.py` (remember / recall / forget). DB testée.

## Phase 5 — Domotique + fichiers 🪟
- [x] `tools/home.py` : REST + WebSocket temps réel, cache + résolution d'entités (résolution testée).
- [x] `tools/files.py` : opérations sandboxées (ALLOWED_PATHS), testées.
- [ ] À valider sur Windows : instance Home Assistant réelle.

## Phase 6 — Interface 🪟
- [x] `ui/tray.py` (barre système), `ui/hud.py` (overlay animé QPainter), `ui/bridge.py`.
- [x] Intégration `qasync`, raccourci global `Ctrl+Alt+J`, interruption `Échap`.
- [ ] Barge-in vocal « par-dessus » : nécessite AEC (limite documentée).
- [ ] À valider sur Windows : rendu HUD, tray, raccourcis.

## Phase 7 — Finition
- [x] Robustesse : erreurs LLM/outils/réseau → message vocal calme + retour IDLE (pas de crash).
- [x] Modes `--text`, `--no-ui`, `--dry-run`.
- [ ] Démarrage automatique avec Windows (tâche planifiée / raccourci Démarrage).
- [ ] Packaging PyInstaller (.exe).
- [ ] Captures d'écran du HUD dans le README.
