"""Point d'entrée de JARVIS.

Exemples :
    python run.py                 # voix + wake word + HUD (tout)
    python run.py --text          # REPL clavier, sans audio ni UI
    python run.py --no-ui         # voix, sans fenêtre
    python run.py --dry-run       # les actions risquées sont simulées
"""

from __future__ import annotations

from jarvis.cli import main

if __name__ == "__main__":
    main()
