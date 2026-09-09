# JARVIS — ton assistant PC

Ce dossier contient **ton** assistant, gardé volontairement **à part** du reste
du dépôt. On le construit étape par étape, et tu valides chaque étape avant la
suivante.

> On est actuellement à l'**Étape 1** : pas encore d'IA, pas encore de voix, pas
> encore de HUD. On teste juste les « mains » de l'agent (ouvrir/fermer une app,
> capture d'écran) en tapant des commandes au clavier.

## Qui fait quoi ?
- **Le code** : c'est Claude qui l'écrit et le pousse ici. Tu n'as **aucune
  ligne de code à écrire**.
- **Sur ta machine** : toi, tu installes Python (une seule fois), tu récupères
  le code, et tu lances l'agent. (Un logiciel ne peut pas s'installer sur ton PC
  à distance — c'est la seule chose qui te revient.)

## Prérequis (une seule fois)
Python 3 installé — vérifie avec :
```powershell
python --version
```
Si ça ne répond pas, voir l'Étape 0 (installation de Python).

## Lancer l'agent (Étape 1)
Ouvre un terminal PowerShell **dans ce dossier `jarvis`** :
```powershell
cd jarvis
pip install -r requirements.txt
python main.py
```

## Essaie ces commandes
```
ouvre bloc-notes
ferme bloc-notes
capture
aide
quitte
```

### Bon à savoir
- `ouvre` / `ferme` marchent le mieux avec **bloc-notes** (Notepad).
  ⚠️ Fermer les apps modernes du Windows Store (ex : Calculatrice) est
  capricieux — c'est normal, on gérera ça mieux plus tard.
- `capture` enregistre une image dans le dossier `captures/`.
- Chaque action est notée dans `journaux/AAAA-MM-JJ.log` : c'est le carnet de
  bord (une brique de sécurité qu'on garde dès le début).

## La suite
- **Étape 2** : le HUD (fenêtre transparente qui flotte sur le bureau).
- **Étape 3** : relier le backend et le HUD par WebSocket.
- **Étape 4** : micro + voix (+ confirmation vocale des actions sensibles).
- **Étape 5** : shell avec garde-fous (liste noire, journal, isolation).
- **Étape 6** : vision.
