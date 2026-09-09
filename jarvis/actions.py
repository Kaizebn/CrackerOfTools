"""
actions.py — Les "mains" de l'agent : les fonctions qui agissent sur le PC.

Niveau 1 (pour l'instant) : ouvrir une app, fermer une app, capture d'écran.
Chaque fonction fait UNE seule chose, renvoie un petit message texte (ce qu'on
affichera plus tard dans le terminal du HUD), et écrit une ligne dans le journal.

⚠️ Ce fichier est prévu pour Windows. On l'a gardé volontairement simple.
"""

import os
import subprocess
from datetime import datetime

from journal import journaliser


# --- Catalogue des applications connues -------------------------------------
# Clé        = le nom que TU tapes (en minuscules).
# "lancer"   = la commande qui démarre l'application.
# "processus"= le nom du processus à tuer pour la fermer (utilisé par taskkill).
APPS_CONNUES = {
    "bloc-notes":   {"lancer": "notepad.exe",  "processus": "notepad.exe"},
    "notepad":      {"lancer": "notepad.exe",  "processus": "notepad.exe"},
    "calculatrice": {"lancer": "calc.exe",     "processus": "CalculatorApp.exe"},
    "paint":        {"lancer": "mspaint.exe",  "processus": "mspaint.exe"},
    "explorateur":  {"lancer": "explorer.exe", "processus": "explorer.exe"},
}


def ouvrir_app(nom: str) -> str:
    """Ouvre une application. Si le nom est dans le catalogue, on l'utilise ;
    sinon on tente de lancer directement ce que tu as tapé (ex: 'chrome')."""
    nom = nom.strip().lower()
    if not nom:
        return "🤔 Tu veux ouvrir quoi ? Exemple : ouvre bloc-notes"

    journaliser(f"ouvrir_app: {nom}")

    if nom in APPS_CONNUES:
        commande = APPS_CONNUES[nom]["lancer"]
    else:
        commande = nom  # on tente quand même (ex: "chrome", "spotify"...)

    try:
        # Popen lance le programme SANS bloquer l'agent (il continue de tourner).
        # On passe une liste (et pas shell=True) : plus sûr, pas d'injection.
        subprocess.Popen([commande])
        return f"✅ J'ouvre : {nom}"
    except FileNotFoundError:
        connus = ", ".join(APPS_CONNUES)
        return (f"❌ Je ne trouve pas '{nom}'. "
                f"Essaie un nom connu ({connus}) ou le nom exact du .exe.")
    except Exception as e:
        return f"❌ Impossible d'ouvrir '{nom}' : {e}"


def fermer_app(nom: str) -> str:
    """Ferme une application via son processus Windows (commande taskkill)."""
    nom = nom.strip().lower()
    if not nom:
        return "🤔 Tu veux fermer quoi ? Exemple : ferme bloc-notes"

    journaliser(f"fermer_app: {nom}")

    if nom in APPS_CONNUES:
        processus = APPS_CONNUES[nom]["processus"]
    else:
        # On suppose que le nom du processus = ce que tu as tapé + ".exe".
        processus = nom if nom.endswith(".exe") else f"{nom}.exe"

    try:
        # /IM = cibler par nom d'image (le processus), /F = forcer la fermeture.
        resultat = subprocess.run(
            ["taskkill", "/IM", processus, "/F"],
            capture_output=True, text=True,
        )
        if resultat.returncode == 0:
            return f"✅ J'ai fermé : {nom}"
        return f"⚠️ Rien à fermer pour '{nom}' (elle n'était peut-être pas ouverte)."
    except FileNotFoundError:
        return "❌ 'taskkill' introuvable — cette fonction est prévue pour Windows."
    except Exception as e:
        return f"❌ Impossible de fermer '{nom}' : {e}"


def capture_ecran() -> str:
    """Fait une capture de tout l'écran, enregistrée dans le dossier 'captures/'."""
    journaliser("capture_ecran")

    # Import "paresseux" : on n'importe Pillow qu'au moment où on en a besoin,
    # pour donner un message clair si la librairie n'est pas encore installée.
    try:
        from PIL import ImageGrab
    except ImportError:
        return ("❌ Pillow n'est pas installé. Dans le terminal, lance :\n"
                "   pip install -r requirements.txt")

    dossier = "captures"
    os.makedirs(dossier, exist_ok=True)

    # Nom de fichier avec la date/heure, ex: capture_2026-09-09_14-30-05.png
    horodatage = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    chemin = os.path.join(dossier, f"capture_{horodatage}.png")

    image = ImageGrab.grab()  # capture tout l'écran
    image.save(chemin)
    return f"✅ Capture enregistrée : {chemin}"
