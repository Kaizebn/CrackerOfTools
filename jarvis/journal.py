"""
journal.py — Le carnet de bord de l'agent.

Chaque action de l'agent est écrite dans un fichier daté, dans le dossier
'journaux/'. Objectif sécurité : on peut TOUJOURS relire ce que l'agent a fait,
et à quelle heure. Un fichier par jour, par exemple : journaux/2026-09-09.log
"""

import os
from datetime import datetime

DOSSIER_JOURNAUX = "journaux"


def journaliser(message: str) -> None:
    """Ajoute une ligne horodatée au journal du jour."""
    os.makedirs(DOSSIER_JOURNAUX, exist_ok=True)

    jour = datetime.now().strftime("%Y-%m-%d")
    heure = datetime.now().strftime("%H:%M:%S")
    chemin = os.path.join(DOSSIER_JOURNAUX, f"{jour}.log")

    # Le mode "a" (append) ajoute à la fin du fichier sans effacer l'existant.
    with open(chemin, "a", encoding="utf-8") as f:
        f.write(f"[{heure}] {message}\n")
