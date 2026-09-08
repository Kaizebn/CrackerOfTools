# 🧠 BRAIN — Ton cerveau externe de créateur de contenu

Application web **locale**, **mono-utilisateur** et **hors ligne** pour piloter ton
activité de créateur sur YouTube et TikTok. Elle stocke ta stratégie, te dit quoi
faire chaque jour, et mesure si ça marche.

- 100 % local : aucune donnée n'est envoyée sur internet.
- Fonctionne hors ligne, même vide, dès le premier lancement.
- Tes données sont conservées entre les sessions (stockage du navigateur).

## 🚀 Lancer l'application (développement)

Il te faut [Node.js](https://nodejs.org) (version 18 ou plus).

```bash
cd brain
npm install      # à faire une seule fois
npm run dev      # démarre le serveur local
```

Ouvre ensuite l'adresse affichée (par défaut http://localhost:5173).
Au premier lancement, un **assistant de démarrage** (5 min) te guide pour définir
ton positionnement, tes piliers de contenu et ton rythme cible.

## 📦 Construire une version optimisée

```bash
npm run build    # génère le dossier dist/
npm run preview  # prévisualise la version construite
```

Tu peux ouvrir `dist/index.html` via `npm run preview` ou héberger le dossier
`dist/` sur n'importe quel serveur statique (aucun backend requis).

## 🧭 Comment ça marche

L'app est ton cerveau et ses branches :

| Branche | Rôle |
|---|---|
| 🧠 **Aujourd'hui** | Tes 3 actions prioritaires du jour (calculées automatiquement), série, objectif, alertes. |
| 🎯 **Positionnement** | Niche, audience, promesse, ton, avatar spectateur, chaînes de référence. |
| 💡 **Idées** | Banque d'idées + pipeline visuel (Idée → Validée → Script → Tournée → Montée → Publiée). |
| ✍️ **Écriture** | Éditeur de script structuré (Short / Long), bibliothèque de hooks, compteur de mots. |
| 🎬 **Production** | Checklists de tournage/montage, suivi du temps par étape. |
| 📅 **Publication** | Calendrier, rythme cible, fiche de chaque vidéo (miniature, description, hashtags), courbe de cohérence. |
| 📊 **Analyse** | Saisie des stats, graphiques, top/flop, détection de motifs, leçons. |
| 💰 **Monétisation** | Seuils YouTube/TikTok, revenus par source, carnet de contacts marques. |
| 🚀 **Progression** | Parcours d'apprentissage déblocable + journal personnel. |
| ⚙️ **Réglages** | Objectif, piliers, rythme, **export/import JSON**, réinitialisation. |

## 💾 Sauvegarde

Tes données vivent uniquement dans **ce navigateur** (IndexedDB). Pour ne rien
perdre (changement d'appareil, nettoyage du navigateur…), va dans **Réglages** et
utilise **Exporter (JSON)** régulièrement. Tu peux tout restaurer avec **Importer**.

## 🛠️ Stack technique (pour info)

- **React + Vite + TypeScript** — l'interface et l'outillage.
- **Tailwind CSS** — le style (thème sombre, dense, responsive).
- **Dexie (IndexedDB)** — le stockage local. Choisi plutôt que sql.js car plus
  simple et robuste pour un usage 100 % navigateur, sans fichier à gérer.
- **Recharts** — les graphiques.
- **react-router-dom** — la navigation entre les branches.

Aucune clé API, aucun serveur, aucune connexion nécessaire pour le fonctionnement.

## 🌐 Site en ligne + installation (PWA)

BRAIN est une **PWA** : un vrai site web qui s'**installe** comme une app (sur
téléphone et ordinateur) et **fonctionne hors ligne** une fois chargé.

### L'installer comme app
- **Android / Chrome** : menu ⋮ → « Installer l'application » (ou « Ajouter à
  l'écran d'accueil »).
- **iPhone / Safari** : bouton Partager → « Sur l'écran d'accueil ».
- **Ordinateur / Chrome-Edge** : icône d'installation ⊕ dans la barre d'adresse.

### Le mettre en ligne (gratuit, via GitHub Pages)
Le dépôt contient un workflow (`.github/workflows/deploy-brain.yml`) qui
construit et publie l'app automatiquement.

1. Sur GitHub : **Settings → Pages → Source = « GitHub Actions »**.
2. Pousse ta branche (le workflow se déclenche sur les changements de `brain/`),
   ou lance-le à la main dans l'onglet **Actions → Deploy BRAIN to GitHub Pages
   → Run workflow**.
3. L'URL du site s'affiche à la fin du job (ex :
   `https://<ton-pseudo>.github.io/crackeroftools/`).

Le build utilise des chemins **relatifs**, donc l'app marche quel que soit le
sous-dossier — y compris ouverte localement depuis `dist/`.

## 🔤 Sous-titres automatiques (branche Production)

BRAIN peut transcrire ta vidéo/audio **directement dans le navigateur** (avec
Whisper) et te sortir un fichier **.srt / .vtt / texte** à glisser dans ton
montage.

- 100 % local : ton fichier **ne quitte jamais ton appareil**, aucune clé.
- La 1re fois, le modèle se télécharge (~40–150 Mo selon le choix) puis reste en
  cache. Il faut donc une connexion internet **au premier usage**.
- Option « style court » pour des sous-titres façon TikTok (petits groupes de mots).

> Astuce : pour des sous-titres calés au mot près sur ta voix, un outil de
> montage comme CapCut (sous-titres auto, gratuit) reste imbattable. BRAIN te
> dépanne quand tu veux un .srt sans quitter l'app.
