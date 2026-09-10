"""
hud.py — La fenêtre transparente du HUD (Étape 2).

Ouvre une fenêtre SANS bordure, à fond transparent, toujours au premier plan,
qui affiche l'interface HUD (dossier hud/). Pour l'instant le HUD est "vivant"
(anneaux qui tournent, onde) mais PAS encore relié au backend — ça viendra à
l'Étape 3 (WebSocket).

Lancement :  python hud.py   (ou double-clic sur lancer_hud.bat)
"""

import os
import webview  # pywebview : la librairie qui crée la fenêtre

# Chemin absolu vers le HTML du HUD (fonctionne quel que soit le dossier courant).
ICI = os.path.dirname(os.path.abspath(__file__))
PAGE = os.path.join(ICI, "hud", "index.html")


class Pont:
    """Petit "pont" entre le HUD (JavaScript) et Python.
    Pour l'instant il sert juste à fermer la fenêtre. À l'Étape 3, il portera
    les vraies actions (ouvrir une app, régler le volume, etc.)."""

    def __init__(self):
        self.fenetre = None

    def fermer(self):
        """Appelé depuis le HUD quand on clique sur la croix ✕."""
        if self.fenetre is not None:
            self.fenetre.destroy()


def main():
    pont = Pont()
    fenetre = webview.create_window(
        "JARVIS",
        PAGE,
        js_api=pont,                 # expose "pont" au JS sous window.pywebview.api
        width=460, height=620,
        frameless=True,              # pas de bordure Windows
        easy_drag=True,              # on peut déplacer le HUD à la souris
        on_top=True,                 # toujours au premier plan
        transparent=True,            # fond transparent (flotte sur le bureau)
        background_color="#04080b",  # repli si la transparence n'est pas dispo
        resizable=False,
    )
    pont.fenetre = fenetre
    webview.start()


if __name__ == "__main__":
    main()
