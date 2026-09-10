"""
app.py — JARVIS "relié" : le HUD + le backend ensemble (Étape 3).

Ce que fait ce fichier :
  1. démarre le serveur WebSocket (serveur.py),
  2. ouvre le HUD (fenêtre transparente),
  3. lit tes commandes tapées dans la console et, pour chacune :
     - prévient le HUD (état + journal),
     - exécute l'action,
     - renvoie le résultat au HUD.

Résultat : quand tu tapes une commande, le HUD RÉAGIT en direct.

Lancement :  python app.py   (ou double-clic sur lancer_tout.bat)

Note : le micro/voix arrivera à l'Étape 4. Ici, tu "parles" encore au clavier.
"""

import os
import threading

import webview

import serveur
from actions import ouvrir_app, fermer_app, capture_ecran

ICI = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(ICI, "hud", "index.html")

MENU = """
Commandes : ouvre <app> | ferme <app> | capture | aide
(Ferme la fenêtre du HUD avec la croix ✕ pour tout arrêter.)
"""


def executer(ligne):
    """Traite une commande tapée et tient le HUD au courant à chaque étape."""
    ligne = ligne.strip()
    if not ligne:
        return

    # ce que JARVIS "entend" (ici : ce que tu tapes)
    serveur.envoyer("log", texte=ligne, genre="in")
    serveur.envoyer("etat", valeur="reflexion")

    morceaux = ligne.split(maxsplit=1)
    cmd = morceaux[0].lower()
    arg = morceaux[1] if len(morceaux) > 1 else ""

    if cmd == "ouvre":
        rep = ouvrir_app(arg)
    elif cmd == "ferme":
        rep = fermer_app(arg)
    elif cmd == "capture":
        rep = capture_ecran()
    elif cmd == "aide":
        rep = MENU
    else:
        rep = f"❌ Commande inconnue : {cmd}"

    # on choisit l'état/couleur selon le résultat
    if rep.startswith("✅"):
        genre, etat = "act", "action"
    elif rep.startswith("❌"):
        genre, etat = "err", "erreur"
    else:
        genre, etat = "sys", "veille"

    serveur.envoyer("etat", valeur=etat)
    serveur.envoyer("log", texte=rep, genre=genre)
    print(rep)

    # retour à l'état veille après 2 secondes
    threading.Timer(2.0, lambda: serveur.envoyer("etat", valeur="veille")).start()


def boucle_console():
    """Lit les commandes au clavier, en boucle (dans un thread de fond)."""
    print("=" * 50)
    print("  JARVIS relié — tape une commande, regarde le HUD réagir")
    print("=" * 50)
    print(MENU)
    while True:
        try:
            ligne = input("> ")
        except (EOFError, OSError):
            break
        executer(ligne)


class Pont:
    """Pont JS -> Python (bouton fermer du HUD)."""

    def __init__(self):
        self.fenetre = None

    def fermer(self):
        if self.fenetre is not None:
            self.fenetre.destroy()


def main():
    serveur.demarrer_serveur()
    threading.Thread(target=boucle_console, daemon=True).start()

    pont = Pont()
    fenetre = webview.create_window(
        "JARVIS",
        PAGE,
        js_api=pont,
        width=460, height=620,
        frameless=True, easy_drag=True, on_top=True,
        transparent=True, background_color="#04080b",
        resizable=False,
    )
    pont.fenetre = fenetre
    webview.start()   # bloque jusqu'à la fermeture du HUD (thread principal)


if __name__ == "__main__":
    main()
