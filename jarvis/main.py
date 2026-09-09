"""
main.py — Le point d'entrée de l'agent en mode "ligne de commande".

Pour l'instant, PAS d'IA et PAS de voix : tu tapes une commande, l'agent agit.
C'est l'Étape 1 : on teste les "mains" de l'agent, isolément, avant tout le reste
(le HUD, la voix, l'IA... viendront après, une étape à la fois).

Lance-le avec :   python main.py
"""

from actions import ouvrir_app, fermer_app, capture_ecran


AIDE = """
Commandes disponibles :
  ouvre <nom>     -> ouvre une application   (ex: ouvre bloc-notes)
  ferme <nom>     -> ferme une application   (ex: ferme bloc-notes)
  capture         -> fait une capture d'écran
  aide            -> affiche cette aide
  quitte          -> ferme l'agent
"""


def traiter(ligne: str) -> str:
    """Lit ce que tu as tapé et appelle la bonne action.
    On sépare le premier mot (la commande) du reste (l'argument)."""
    ligne = ligne.strip()
    if not ligne:
        return ""

    morceaux = ligne.split(maxsplit=1)
    commande = morceaux[0].lower()
    argument = morceaux[1] if len(morceaux) > 1 else ""

    if commande == "ouvre":
        return ouvrir_app(argument)
    elif commande == "ferme":
        return fermer_app(argument)
    elif commande == "capture":
        return capture_ecran()
    elif commande == "aide":
        return AIDE
    else:
        return f"🤔 Commande inconnue : '{commande}'. Tape 'aide' pour la liste."


def main() -> None:
    print("=" * 52)
    print("  JARVIS — backend (Étape 1, mode ligne de commande)")
    print("=" * 52)
    print(AIDE)

    while True:
        try:
            ligne = input("\n> ")
        except (EOFError, KeyboardInterrupt):
            print("\nÀ bientôt !")
            break

        if ligne.strip().lower() in ("quitte", "exit", "quit"):
            print("À bientôt !")
            break

        reponse = traiter(ligne)
        if reponse:
            print(reponse)


if __name__ == "__main__":
    main()
