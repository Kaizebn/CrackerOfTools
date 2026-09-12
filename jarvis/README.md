# JARVIS — assistant IA vocal pour Windows

Un assistant personnel de type JARVIS : un daemon qui tourne en permanence sur un PC
Windows 11, se réveille au mot-clé « Hey Jarvis », comprend ce qu'on lui dit, agit sur
la machine / le web / la domotique, et répond à voix haute.

Le projet est construit **phase par phase** : chaque phase se termine par quelque chose
de lançable et testable. Cette version couvre la **Phase 0 — Fondations**.

---

## État d'avancement

- [x] **Phase 0 — Fondations** : structure, config, bus d'événements, machine à états, logs, tests.
- [ ] Phase 1 — Boucle vocale nue (micro → wake word → VAD → Whisper → Piper).
- [ ] Phase 2 — Cerveau (Claude en streaming).
- [ ] Phase 3 — Outils (système, web, minuteurs) + confirmations.
- [ ] Phase 4 — Mémoire (SQLite + ChromaDB).
- [ ] Phase 5 — Domotique + fichiers.
- [ ] Phase 6 — Interface (tray + HUD) + barge-in.
- [ ] Phase 7 — Finition (démarrage auto, packaging, robustesse).

Voir [`TODO.md`](TODO.md) pour le détail.

---

## Prérequis

- **Windows 11 x64** (le code tourne nativement, pas via WSL).
- **Python 3.11 ou plus récent** — à l'installation, cocher *« Add python.exe to PATH »*.
- **GPU NVIDIA** recommandé pour la latence (faster-whisper en CUDA, à partir de la
  Phase 1). Sans GPU, tout fonctionne sur CPU mais la réponse est plus lente.

> La Phase 0 n'a **aucune** dépendance Windows ni GPU : elle s'installe et se teste sur
> n'importe quel OS. Les briques audio/GPU arrivent en Phase 1.

---

## Installation (Windows, pas à pas)

Ouvrir **PowerShell** dans le dossier `jarvis/`.

### Option A — avec `uv` (recommandé)

```powershell
# Installer uv une fois : https://docs.astral.sh/uv/
uv venv
.\.venv\Scripts\Activate.ps1
uv pip install -r requirements.txt
uv pip install -e .
```

### Option B — avec venv + pip

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pip install -e .
```

### Configuration

```powershell
Copy-Item .env.example .env
notepad .env
```

En Phase 0 aucune clé n'est nécessaire : les valeurs par défaut suffisent. La clé
`ANTHROPIC_API_KEY` devient obligatoire en Phase 2.

---

## Lancer et tester la Phase 0

### 1. Exécuter le daemon (démo des fondations)

```powershell
python run.py
```

Attendu : des logs colorés s'affichent, simulant un tour vocal complet sans micro ni
LLM — `jarvis.starting`, puis les événements `WakeDetected`, `StateChanged`,
`TranscriptReady`, `AssistantSentence`, et enfin `jarvis.ready`. Un fichier
`logs/jarvis.jsonl` est créé (logs structurés en JSON, rotatifs).

### 2. Lancer les tests

```powershell
pip install -e ".[dev]"
pytest
```

Attendu : tous les tests passent (bus d'événements, machine à états, configuration).

### 3. Vérifier le typage strict

```powershell
mypy --strict src/
```

Attendu : `Success: no issues found`.

---

## Notes Windows

- **UTF-8 en console** : `run.py` reconfigure automatiquement `stdout`/`stderr` en UTF-8
  pour que les accents et emoji des logs s'affichent correctement (`logging_config.py`,
  `_ensure_utf8_console`).
- **Couleurs** : `colorama` est inclus pour les couleurs de log dans les terminaux
  Windows plus anciens ; les terminaux récents (Windows Terminal) le gèrent nativement.

D'autres contournements spécifiques à Windows (pycaw/COM, sounddevice, chemins) seront
documentés ici au fil des phases qui les introduisent.

---

## Architecture (rappel)

Pipeline événementiel, chaque étage remplaçable, articulé autour d'un **EventBus**
asyncio et d'une **machine à états** `IDLE → LISTENING → THINKING → SPEAKING → IDLE`
(+ `ERROR`) :

```
Micro → WakeWord → VAD+Recorder → STT → Orchestrator ⇄ Memory
                                              │ tool_use
                                              ▼
                                         ToolRegistry → (system / files / web / home / memory)
                                              │
                                              ▼
                                         TTS → Haut-parleurs → HUD
```

- **Modèle de concurrence** : une seule boucle asyncio intégrée à Qt via `qasync`
  (choisi à partir de la Phase 6). Les libs bloquantes (Whisper, Piper, pyautogui…)
  passent par un thread pool ; le callback micro temps-réel ne fait que pousser les
  frames dans une file.
- **Sécurité** : chaque outil déclare un niveau de risque `SAFE / CONFIRM / FORBIDDEN` ;
  les actions `CONFIRM` exigent une confirmation vocale **et** visuelle. Mode `--dry-run`
  pour tester sans effet de bord.
