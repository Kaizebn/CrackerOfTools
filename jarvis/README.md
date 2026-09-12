# JARVIS — assistant IA vocal pour Windows

Un assistant personnel de type JARVIS : un daemon qui tourne en permanence sur Windows 11,
se réveille au mot-clé « Hey Jarvis », comprend ce qu'on lui dit, agit sur la machine /
le web / la domotique, et répond à voix haute — avec une personnalité posée et efficace.

Pipeline événementiel, streaming de bout en bout (LLM → TTS phrase par phrase), outils
sous politique de sécurité (SAFE / CONFIRM), mémoire persistante, HUD animé.

---

## En un coup d'œil

```
Micro → WakeWord → VAD → Whisper → Orchestrateur ⇄ Mémoire (SQLite + ChromaDB)
                                        │ tool_use
                                        ▼
                                   ToolRegistry → système / fichiers / web / domotique / mémoire / minuteurs
                                        │
                                        ▼
                                   TTS (Piper/ElevenLabs) → Haut-parleurs → HUD
```

- **Cerveau** : Claude en streaming + tool use, derrière une abstraction `LLMProvider`.
- **Voix** : openWakeWord → silero-VAD → faster-whisper (CUDA auto) → Piper (offline).
- **Outils** : apps, volume, luminosité, captures, média, énergie, commandes (allowlist),
  fichiers sandboxés, recherche web + météo + actus, Home Assistant, mémoire, minuteurs/rappels.
- **Sécurité** : actions risquées confirmées à la voix **et** au HUD, mode `--dry-run`,
  journal des appels d'outils en SQLite.
- **Interface** : icône de barre système + overlay « arc-réacteur » animé (QPainter, 60 fps).

---

## Prérequis

- **Windows 11 x64**, **Python 3.11+** (cocher *« Add python.exe to PATH »* à l'installation).
- **GPU NVIDIA** recommandé (Whisper en CUDA → réponse < 1,5 s). Sans GPU, tout fonctionne
  sur CPU mais plus lentement (≈ 2–2,5 s).
- Une **clé API Anthropic** (`ANTHROPIC_API_KEY`).

---

## Installation (Windows, pas à pas)

Dans **PowerShell**, depuis le dossier `jarvis/` :

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pip install -e .
```

> **GPU** : `faster-whisper` tire automatiquement les bibliothèques CUDA. Pour `torch`
> (embeddings mémoire + VAD) en version GPU, installe-le depuis l'index PyTorch si besoin :
> `pip install torch --index-url https://download.pytorch.org/whl/cu124`.

### Modèles à télécharger

- **Wake word** (openWakeWord) et **Whisper** se téléchargent automatiquement au premier lancement.
- **Voix Piper** : télécharge `fr_FR-siwis-medium.onnx` **et** `fr_FR-siwis-medium.onnx.json`
  depuis [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices/tree/main/fr/fr_FR/siwis/medium)
  et place-les dans `models/piper/`.

### Configuration

```powershell
Copy-Item .env.example .env
notepad .env
```

Renseigne au minimum `ANTHROPIC_API_KEY`. Les autres clés (Home Assistant, Tavily,
ElevenLabs) sont optionnelles — sans elles, les fonctions correspondantes se désactivent
proprement. Pour les outils fichiers, liste les dossiers autorisés dans
`JARVIS_ALLOWED_PATHS` (séparés par `;`).

---

## Lancer JARVIS

### En un double-clic (le plus simple)

Double-clique sur **`start_jarvis.bat`** dans le dossier `jarvis/`.
- **1er lancement** : il installe tout, puis ouvre `.env` pour que tu colles ta clé API.
- **Ensuite** : il ouvre directement l'interface (icône dans la barre système + HUD), sans
  fenêtre noire. Clic droit sur `start_jarvis.bat` → *Envoyer vers → Bureau* pour un
  raccourci ; pour un démarrage avec Windows, place ce raccourci dans le dossier
  `shell:startup` (touches Windows+R → `shell:startup`).

> Sans voix Piper installée, l'interface fonctionne quand même : les réponses s'affichent
> en texte sous l'anneau du HUD (pas de voix tant que Piper n'est pas dans `models/piper/`).

### En ligne de commande

```powershell
python run.py            # Voix + wake word + HUD (tout)
python run.py --no-ui    # Voix, sans fenêtre
python run.py --text     # REPL clavier : teste le cerveau et les outils sans micro
python run.py --dry-run  # Les actions risquées sont simulées (jamais exécutées)
```

- **Raccourci global `Ctrl+Alt+J`** : déclenche l'écoute sans dire le mot-clé.
- **Échap** : interrompt la parole de Jarvis.

Le mode `--text` est le plus simple pour commencer : tape une requête, JARVIS répond et
utilise ses outils exactement comme à la voix.

---

## Tester

```powershell
pip install -e ".[dev]"
pytest                 # suite de tests (audio et LLM mockés)
mypy --strict src\     # typage strict : Success: no issues found
```

---

## Exemples de commandes

| Tu dis…                                                   | JARVIS…                                            |
|-----------------------------------------------------------|----------------------------------------------------|
| « Hey Jarvis, quelle heure est-il ? »                     | répond l'heure.                                    |
| « …ouvre Spotify et monte le son à 60 %. »                | ouvre l'app et règle le volume, une seule réponse. |
| « …quel temps fera-t-il demain à Paris ? »                | interroge Open-Meteo et résume.                    |
| « …éteins la lumière du salon. »                          | résout `light.salon` et l'éteint (Home Assistant). |
| « …retiens que je suis allergique aux arachides. »        | le mémorise (SQLite + ChromaDB).                   |
| « …supprime le fichier X. »                               | demande confirmation avant d'agir.                 |

---

## Sécurité

- Chaque outil déclare un niveau : **SAFE** (exécuté), **CONFIRM** (confirmation vocale +
  visuelle, timeout 15 s → annulation), **FORBIDDEN** (masqué du LLM).
- `run_command` n'exécute que les binaires d'une **allowlist** (`JARVIS_COMMAND_ALLOWLIST`),
  jamais via un shell construit depuis la sortie du LLM.
- Les outils fichiers sont **confinés** à `JARVIS_ALLOWED_PATHS` ; tout accès hors de ces
  racines est refusé.
- `--dry-run` journalise les actions à effet de bord sans les exécuter.
- Chaque appel d'outil est **journalisé** en SQLite (horodatage, arguments, résultat).

---

## Notes Windows

- **UTF-8 console** : reconfiguré automatiquement (`logging_config._ensure_utf8_console`).
- **pycaw / COM** : l'initialisation COM est faite dans le thread qui contrôle le volume.
- **Luminosité** : dépend du matériel (DDC) ; en cas d'échec, l'outil le signale sans planter.
- **Concurrence** : une seule boucle asyncio intégrée à Qt via `qasync`. Les libs bloquantes
  (Whisper, Piper, pyautogui, pycaw) passent par un thread ; le callback micro temps-réel
  ne fait que poster les frames.

---

## Limites connues

- **Barge-in vocal « par-dessus » la voix** : couper Jarvis en parlant pendant qu'il parle
  exige de l'annulation d'écho (AEC) pour ne pas se déclencher sur sa propre sortie. La
  version actuelle fournit l'interruption fiable par **Échap** (et le raccourci global).
  L'AEC est prévue comme évolution.
- Les briques **audio / GPU / Qt** ont été développées et typées, mais doivent être validées
  sur une vraie machine Windows (micro, GPU, écran). Le **cerveau, les outils, la mémoire et
  la boucle tool-use** sont couverts par les tests automatisés.

---

## Dépannage

- `pip install` échoue sur une version audio/ML/UI → retire l'épingle et laisse pip résoudre
  (`pip install faster-whisper sounddevice piper-tts …`), puis relance.
- Pas de voix → vérifie que les fichiers Piper sont dans `models/piper/` (voir plus haut).
- « ANTHROPIC_API_KEY manquante » → renseigne la clé dans `.env`.
- Micro introuvable → liste les périphériques avec `python -m sounddevice` et règle
  `JARVIS_INPUT_DEVICE`.

Voir [`TODO.md`](TODO.md) pour l'état détaillé par phase.
