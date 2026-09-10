"""
voix.py — L'oreille et la voix de JARVIS (Étape 4).

- ÉCOUTE : ton micro -> texte, en LOCAL, avec Vosk (rien ne sort de ton PC).
- PARLE  : réponses à voix haute avec pyttsx3 (voix de Windows, hors-ligne).

Au 1er lancement, le petit modèle vocal français (~40 Mo) se télécharge tout
seul dans le dossier 'modeles/'.

Test tout seul :  python voix.py   (ou double-clic sur lancer_voix.bat)
Puis parle :  « ouvre le bloc-notes », « prends une capture »,
              « ferme le bloc-notes », et « au revoir » pour arrêter.
"""

import os
import json
import queue
import zipfile
import urllib.request

from actions import ouvrir_app, fermer_app, capture_ecran

ICI = os.path.dirname(os.path.abspath(__file__))
DOSSIER_MODELES = os.path.join(ICI, "modeles")
NOM_MODELE = "vosk-model-small-fr-0.22"
URL_MODELE = "https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip"
CHEMIN_MODELE = os.path.join(DOSSIER_MODELES, NOM_MODELE)


# ----------------------------------------------------------------------------
#  LA VOIX (synthèse vocale)
# ----------------------------------------------------------------------------
_moteur = None


def parler(texte):
    """Dit une phrase à voix haute (et l'affiche aussi dans la console)."""
    global _moteur
    print("🔊 JARVIS :", texte)
    try:
        import pyttsx3
        if _moteur is None:
            _moteur = pyttsx3.init()
            # On essaie de choisir une voix française si elle existe.
            for v in _moteur.getProperty("voices"):
                etiquette = (getattr(v, "id", "") + " " + getattr(v, "name", "")).lower()
                if "fr" in etiquette or "french" in etiquette:
                    _moteur.setProperty("voice", v.id)
                    break
        _moteur.say(texte)
        _moteur.runAndWait()
    except Exception as e:
        print("[voix] synthèse vocale indisponible :", e)


# ----------------------------------------------------------------------------
#  COMPRENDRE UNE PHRASE (simple, par mots-clés — l'IA Ollama viendra après)
# ----------------------------------------------------------------------------
APPS_MOTS = {
    "bloc": "bloc-notes", "notes": "bloc-notes", "notepad": "bloc-notes",
    "calculatrice": "calculatrice", "calcul": "calculatrice",
    "paint": "paint", "dessin": "paint",
    "explorateur": "explorateur", "fichiers": "explorateur",
}


def _trouver_app(phrase):
    for mot, app in APPS_MOTS.items():
        if mot in phrase:
            return app
    mots = phrase.split()
    return mots[-1] if mots else ""


def executer_phrase(phrase, envoyer=None):
    """Interprète la phrase entendue, agit, et répond à voix haute.
    'envoyer' (optionnel) sert à prévenir le HUD (état + journal)."""
    phrase = phrase.lower().strip()
    if not phrase:
        return None

    def etat(v):
        if envoyer:
            envoyer("etat", valeur=v)

    def log(t, g="sys"):
        if envoyer:
            envoyer("log", texte=t, genre=g)

    log(phrase, "in")
    etat("reflexion")

    # Arrêt
    if any(m in phrase for m in ("au revoir", "stop jarvis", "arrête-toi", "arrete toi")):
        parler("Au revoir !")
        etat("veille")
        return "quitter"

    # Actions
    if any(m in phrase for m in ("capture", "photo", "écran", "ecran")):
        rep = capture_ecran()
        parler("Voilà, j'ai fait une capture d'écran.")
    elif any(m in phrase for m in ("ouvre", "ouvrir", "lance", "démarre", "demarre")):
        app = _trouver_app(phrase)
        rep = ouvrir_app(app)
        parler(f"J'ouvre {app}." if rep.startswith("✅") else f"Je n'ai pas réussi à ouvrir {app}.")
    elif any(m in phrase for m in ("ferme", "fermer", "arrête", "arrete")):
        app = _trouver_app(phrase)
        rep = fermer_app(app)
        parler(f"Je ferme {app}." if rep.startswith("✅") else f"Je n'ai pas trouvé {app} à fermer.")
    else:
        rep = f"non compris : {phrase}"
        parler("Je n'ai pas compris. Tu peux répéter ?")

    if rep.startswith("✅"):
        etat("action"); log(rep, "act")
    elif rep.startswith("❌"):
        etat("erreur"); log(rep, "err")
    else:
        etat("veille"); log(rep, "sys")
    return None


# ----------------------------------------------------------------------------
#  ÉCOUTER (micro -> texte, en continu)
# ----------------------------------------------------------------------------
def _telecharger_modele():
    os.makedirs(DOSSIER_MODELES, exist_ok=True)
    zip_path = CHEMIN_MODELE + ".zip"
    print("⬇️  Téléchargement du modèle vocal français (~40 Mo, une seule fois)…")
    urllib.request.urlretrieve(URL_MODELE, zip_path)
    print("📦 Décompression…")
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(DOSSIER_MODELES)
    os.remove(zip_path)
    print("✅ Modèle vocal prêt.")


def ecouter(envoyer=None):
    """Ouvre le micro et écoute en continu. Pour chaque phrase reconnue,
    appelle executer_phrase(). Dis « au revoir » pour arrêter."""
    try:
        import sounddevice as sd
        import vosk
    except ImportError:
        print("[voix] Librairies manquantes. Lance : pip install -r requirements.txt")
        parler("Il me manque des composants pour t'entendre.")
        return

    if not os.path.isdir(CHEMIN_MODELE):
        try:
            _telecharger_modele()
        except Exception as e:
            print("[voix] Échec du téléchargement du modèle :", e)
            return

    modele = vosk.Model(CHEMIN_MODELE)
    reconnaisseur = vosk.KaldiRecognizer(modele, 16000)
    fifo = queue.Queue()

    def _capter(indata, frames, heure, status):
        fifo.put(bytes(indata))

    if envoyer:
        envoyer("etat", valeur="ecoute")
    parler("Bonjour, je t'écoute.")
    print("🎙️  Parle ! (dis « au revoir » pour arrêter)")

    with sd.RawInputStream(samplerate=16000, blocksize=8000, dtype="int16",
                           channels=1, callback=_capter):
        while True:
            donnees = fifo.get()
            if reconnaisseur.AcceptWaveform(donnees):
                res = json.loads(reconnaisseur.Result())
                texte = res.get("text", "").strip()
                if texte:
                    if executer_phrase(texte, envoyer) == "quitter":
                        break
                    if envoyer:
                        envoyer("etat", valeur="ecoute")


if __name__ == "__main__":
    ecouter()
