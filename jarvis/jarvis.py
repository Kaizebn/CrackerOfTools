"""
jarvis.py — JARVIS COMPLET : HUD plein écran + voix + IA + backend.

Démarre tout d'un coup :
  1. le serveur WebSocket (pont HUD <-> backend),
  2. l'écoute vocale (mot « Jarvis » + IA Ollama, avec repli mode simple),
  3. le HUD plein écran rouge, qui réagit à ta voix.

Lancement : python jarvis.py   (ou double-clic sur lancer_jarvis_complet.bat)
Pour quitter : clique la croix ✕ en haut à droite (ou Alt+F4).
"""

import os
import time
import threading

import webview

import serveur
import voix

ICI = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(ICI, "hud", "index.html")


class Pont:
    """Pont JS -> Python (bouton fermer du HUD)."""

    def __init__(self):
        self.fenetre = None

    def fermer(self):
        if self.fenetre is not None:
            self.fenetre.destroy()


def _demarrer_voix():
    # petit délai : laisse le HUD se connecter au serveur avant de parler
    time.sleep(2)
    voix.ecouter(envoyer=serveur.envoyer)


def main():
    serveur.demarrer_serveur()
    threading.Thread(target=_demarrer_voix, daemon=True).start()

    pont = Pont()
    fenetre = webview.create_window(
        "JARVIS",
        PAGE,
        js_api=pont,
        fullscreen=True,          # grande page plein écran
        background_color="#0b0304",
    )
    pont.fenetre = fenetre
    webview.start()               # bloque jusqu'à la fermeture (thread principal)


if __name__ == "__main__":
    main()
