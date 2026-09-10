"""
securite.py — Les garde-fous AVANT d'exécuter une commande système.

Trois niveaux :
  1. LISTE_NOIRE  : commandes qui ne s'exécutent JAMAIS (destruction massive,
                    registre, antivirus…). Refusées, point.
  2. DESTRUCTIF   : autorisées mais SEULEMENT après confirmation vocale
                    (tout ce qui supprime / écrase / installe / arrête).
  3. le reste     : exécuté directement.

C'est volontairement PRUDENT : dans le doute, on demande confirmation.
"""

import re

# 1) Jamais, sous aucun prétexte.
LISTE_NOIRE = [
    r"\bformat\b",
    r"format-volume", r"clear-disk", r"remove-partition", r"\bdiskpart\b",
    r"\bmkfs\b", r"\bdd\b\s+if=",
    r"del\b.*/\s*s", r"del\b.*/\s*q", r"\berase\b\s+/",
    r"rmdir\b.*/\s*s", r"\brd\b.*/\s*s",
    r"rm\s+-\w*r\w*f", r"rm\s+-\w*f\w*r", r"remove-item\b.*-recurse\b.*-force",
    r"reg\s+delete", r"reg\s+add", r"remove-itemproperty", r"new-itemproperty.*hklm",
    r"set-mppreference.*disable", r"disabl\w*.*defender", r"uninstall.*defender",
    r"vssadmin\s+delete", r"wbadmin\s+delete", r"\bbcdedit\b", r"cipher\s+/w",
    r"net\s+user\b.*/\s*add", r"net\s+user\b.*/\s*delete",
]

# 2) Autorisé mais avec confirmation vocale (supprimer / écraser / installer / arrêter).
DESTRUCTIF = [
    r"\bdel\b", r"\berase\b", r"\brm\b", r"\brmdir\b", r"\brd\b",
    r"remove-item", r"supprim", r"\buninstall\b", r"désinstall", r"desinstall",
    r"move-item", r"\bmove\b", r"\bren\b", r"rename-item", r"renomme", r"déplace",
    r">", r"out-file", r"set-content", r"écras", r"ecras",
    r"\binstall\b", r"winget\s+install", r"choco\s+install", r"pip\s+install",
    r"stop-process", r"taskkill", r"stop-service", r"\bshutdown\b", r"restart-computer",
]


def _cherche(motifs, commande):
    c = (commande or "").lower()
    return any(re.search(p, c) for p in motifs)


def est_interdit(commande):
    """True si la commande figure dans la liste noire (à refuser)."""
    return _cherche(LISTE_NOIRE, commande)


def est_destructif(commande):
    """True si la commande nécessite une confirmation vocale."""
    return _cherche(DESTRUCTIF, commande)
