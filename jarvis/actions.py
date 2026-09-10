"""
actions.py — Les "mains" de l'agent : les fonctions qui agissent sur le PC.

Niveau 1 : ouvrir/fermer une app, capture d'écran, volume, recherche web.
Chaque fonction fait UNE chose, renvoie un petit message (✅ / ⚠️ / ❌ au début,
ce qui sert aussi à colorer l'état du HUD), et écrit une ligne dans le journal.

⚠️ Prévu pour Windows.
"""

import os
import glob
import ctypes
import subprocess
import webbrowser
from datetime import datetime
from urllib.parse import quote

from journal import journaliser


# --- Catalogue des applications connues -------------------------------------
APPS_CONNUES = {
    "bloc-notes":   {"lancer": "notepad.exe",  "processus": "notepad.exe"},
    "notepad":      {"lancer": "notepad.exe",  "processus": "notepad.exe"},
    "calculatrice": {"lancer": "calc.exe",     "processus": "CalculatorApp.exe"},
    "paint":        {"lancer": "mspaint.exe",  "processus": "mspaint.exe"},
    "explorateur":  {"lancer": "explorer.exe", "processus": "explorer.exe"},
    "chrome":       {"lancer": "chrome.exe",   "processus": "chrome.exe"},
}


def ouvrir_app(nom: str) -> str:
    """Ouvre une application (connue, spéciale comme Roblox, ou quelconque)."""
    nom = (nom or "").strip().lower()
    if not nom:
        return "🤔 Ouvrir quoi ? (ex : ouvre le bloc-notes)"
    journaliser(f"ouvrir_app: {nom}")

    if "roblox" in nom:
        return _ouvrir_roblox()

    if nom in APPS_CONNUES:
        try:
            subprocess.Popen([APPS_CONNUES[nom]["lancer"]])
            return f"✅ J'ouvre {nom}"
        except Exception as e:
            return f"❌ Impossible d'ouvrir {nom} : {e}"

    # Application inconnue : on tente plusieurs méthodes, dans l'ordre.
    tentatives = (
        lambda: subprocess.Popen([nom]),
        lambda: os.startfile(nom),                        # ouverture "Windows"
        lambda: subprocess.Popen(["cmd", "/c", "start", "", nom]),
    )
    for essayer in tentatives:
        try:
            essayer()
            return f"✅ J'ouvre {nom}"
        except Exception:
            continue
    return f"❌ Je n'ai pas trouvé « {nom} »."


def _ouvrir_roblox() -> str:
    """Roblox est installé de façon particulière : on cherche son lanceur."""
    motif = os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions\*\RobloxPlayerBeta.exe")
    for exe in glob.glob(motif):
        try:
            subprocess.Popen([exe])
            return "✅ J'ouvre Roblox"
        except Exception:
            pass
    for uri in ("roblox://", "roblox-player://"):
        try:
            os.startfile(uri)
            return "✅ J'ouvre Roblox"
        except Exception:
            pass
    return "❌ Roblox introuvable (il n'est peut-être pas installé)."


def fermer_app(nom: str) -> str:
    """Ferme une application via son processus Windows (taskkill)."""
    nom = (nom or "").strip().lower()
    if not nom:
        return "🤔 Fermer quoi ?"
    journaliser(f"fermer_app: {nom}")

    if nom in APPS_CONNUES:
        processus = APPS_CONNUES[nom]["processus"]
    elif "roblox" in nom:
        processus = "RobloxPlayerBeta.exe"
    else:
        processus = nom if nom.endswith(".exe") else f"{nom}.exe"

    try:
        r = subprocess.run(["taskkill", "/IM", processus, "/F"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            return f"✅ J'ai fermé {nom}"
        return f"⚠️ Rien à fermer pour {nom} (pas ouverte ?)."
    except FileNotFoundError:
        return "❌ 'taskkill' introuvable — fonction prévue pour Windows."
    except Exception as e:
        return f"❌ Impossible de fermer {nom} : {e}"


def capture_ecran() -> str:
    """Capture tout l'écran dans le dossier 'captures/'."""
    journaliser("capture_ecran")
    try:
        from PIL import ImageGrab
    except ImportError:
        return "❌ Pillow manquant. Lance : pip install -r requirements.txt"
    os.makedirs("captures", exist_ok=True)
    horodatage = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    chemin = os.path.join("captures", f"capture_{horodatage}.png")
    ImageGrab.grab().save(chemin)
    return f"✅ Capture enregistrée : {chemin}"


def regler_volume(sens: str) -> str:
    """Monte / baisse / coupe le son en simulant les touches multimédia."""
    sens = (sens or "").strip().lower()
    journaliser(f"volume: {sens}")
    # Codes des touches multimédia Windows
    MONTER, BAISSER, MUET = 0xAF, 0xAE, 0xAD
    code = MONTER
    if any(m in sens for m in ("muet", "mute", "coupe")):
        code = MUET
    elif any(m in sens for m in ("-", "baisse", "moins", "diminue", "descend")):
        code = BAISSER
    try:
        repetitions = 1 if code == MUET else 5   # 5 crans = variation nette
        for _ in range(repetitions):
            ctypes.windll.user32.keybd_event(code, 0, 0, 0)   # touche pressée
            ctypes.windll.user32.keybd_event(code, 0, 2, 0)   # touche relâchée
        return "✅ Volume ajusté"
    except Exception as e:
        return f"❌ Volume impossible : {e}"


def recherche_web(requete: str) -> str:
    """Ouvre le navigateur sur une recherche."""
    requete = (requete or "").strip()
    journaliser(f"web: {requete}")
    if not requete:
        return "❌ Chercher quoi ?"
    try:
        webbrowser.open("https://www.google.com/search?q=" + quote(requete))
        return f"✅ Je cherche « {requete} » sur le web"
    except Exception as e:
        return f"❌ Recherche impossible : {e}"


def executer_commande(commande: str) -> str:
    """Exécute une commande PowerShell arbitraire (Niveau 2).
    ⚠️ Les garde-fous (liste noire, confirmation) sont vérifiés AVANT
    l'appel de cette fonction, dans voix.py. Ici on journalise et on exécute."""
    commande = (commande or "").strip()
    journaliser(f"COMMANDE: {commande}")
    if not commande:
        return "❌ Commande vide"
    try:
        r = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", commande],
            capture_output=True, text=True, timeout=30,
        )
        sortie = (r.stdout or "").strip() or (r.stderr or "").strip()
        if r.returncode == 0:
            return "✅ " + (sortie[:250] if sortie else "Commande exécutée")
        return "❌ " + (sortie[:250] if sortie else f"code {r.returncode}")
    except FileNotFoundError:
        return "❌ PowerShell introuvable — fonction prévue pour Windows."
    except subprocess.TimeoutExpired:
        return "❌ La commande a mis trop de temps (arrêtée)."
    except Exception as e:
        return f"❌ Erreur : {e}"
