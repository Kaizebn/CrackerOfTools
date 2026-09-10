"""
voix.py — L'oreille et la voix de JARVIS (Étape 4, avec auto-diagnostic).

- ÉCOUTE en continu (Vosk, local). Ordre clair ou « Jarvis … » pour agir.
- COMPREND avec l'IA locale (cerveau.py / Ollama). Repli mode simple (mots-clés).
- PARLE (pyttsx3, avec repli sur la voix Windows si besoin).
- DIT CE QUI NE VA PAS directement sur l'écran rouge (micro absent, aucun son…).

Test seul :  python voix.py
"""

import os
import time
import json
import queue
import zipfile
import tempfile
import subprocess
import urllib.request

try:
    import audioop            # mesure le niveau du micro (présent jusqu'à Python 3.12)
except Exception:
    audioop = None

import cerveau
import securite
from actions import (ouvrir_app, fermer_app, capture_ecran,
                     regler_volume, recherche_web, executer_commande)

ICI = os.path.dirname(os.path.abspath(__file__))
DOSSIER_MODELES = os.path.join(ICI, "modeles")
# Grand modèle français = bien plus précis (~1,4 Go). L'ancien petit modèle
# comprenait "la moitié des mots" ; celui-ci comprend beaucoup mieux.
NOM_MODELE = "vosk-model-fr-0.22"
URL_MODELE = "https://alphacephei.com/vosk/models/vosk-model-fr-0.22.zip"
CHEMIN_MODELE = os.path.join(DOSSIER_MODELES, NOM_MODELE)

# Voix neuronale (naturelle) pour les réponses. Nécessite internet ;
# repli automatique sur la voix Windows hors-ligne si pas de connexion.
VOIX_EDGE = "fr-FR-HenriNeural"

# On accepte plusieurs façons dont Vosk peut entendre « Jarvis ».
MOTS_REVEIL = ("jarvis", "jarvisse", "jarvi", "jervis", "charvis", "djarvis", "arvis", "gervais")
VERBES_ORDRE = ("ouvre", "ouvrir", "lance", "démarre", "demarre", "ferme", "fermer",
                "cherche", "recherche", "capture", "photo", "volume", "monte", "baisse",
                "éteins", "eteins", "crée", "cree", "supprime", "écris", "ecris")

_moteur = None
_ollama_prevenu = False
_cmd_a_confirmer = None


# ----------------------------------------------------------------------------
#  LA VOIX (avec repli sur la voix Windows)
# ----------------------------------------------------------------------------
def parler(texte):
    """Dit une phrase. On essaie, dans l'ordre :
    1. une belle voix neuronale (edge-tts, nécessite internet),
    2. la voix pyttsx3, 3. la voix Windows (System.Speech). Toujours un son."""
    print("🔊 JARVIS :", texte)
    if _parler_edge(texte):
        return
    if _parler_pyttsx3(texte):
        return
    _parler_sapi(texte)


def _jouer_mp3(chemin):
    """Joue un fichier audio et attend la fin (via MCI, intégré à Windows)."""
    import ctypes
    envoyer = ctypes.windll.winmm.mciSendStringW
    envoyer(f'open "{chemin}" type mpegvideo alias jv', None, 0, 0)
    envoyer('play jv wait', None, 0, 0)
    envoyer('close jv', None, 0, 0)


def _parler_edge(texte):
    """Belle voix neuronale française (edge-tts). Nécessite internet."""
    try:
        import asyncio
        import edge_tts
        chemin = os.path.join(tempfile.gettempdir(), "jarvis_voix.mp3")

        async def _synth():
            await edge_tts.Communicate(texte, VOIX_EDGE).save(chemin)

        asyncio.run(_synth())
        _jouer_mp3(chemin)
        return True
    except Exception as e:
        print("[voix] voix neuronale indisponible (hors-ligne ?) :", e)
        return False


def _parler_pyttsx3(texte):
    global _moteur
    try:
        import pyttsx3
        if _moteur is None:
            _moteur = pyttsx3.init()
            for v in _moteur.getProperty("voices"):
                if "fr" in (getattr(v, "id", "") + getattr(v, "name", "")).lower():
                    _moteur.setProperty("voice", v.id)
                    break
        _moteur.say(texte)
        _moteur.runAndWait()
        return True
    except Exception as e:
        print("[voix] pyttsx3 indisponible :", e)
        return False


def _parler_sapi(texte):
    try:
        sur = texte.replace("'", " ").replace('"', " ")
        subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Add-Type -AssemblyName System.Speech; "
             f"(New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('{sur}')"],
            timeout=20,
        )
    except Exception as e:
        print("[voix] aucune synthèse vocale disponible :", e)


# ----------------------------------------------------------------------------
#  AGIR selon une décision {action: ...}
# ----------------------------------------------------------------------------
def agir(decision, envoyer=None):
    def etat(v):
        if envoyer: envoyer("etat", valeur=v)

    def log(t, g="sys"):
        if envoyer: envoyer("log", texte=t, genre=g)

    action = (decision or {}).get("action", "repondre")
    cible = decision.get("cible", "")

    if action == "ouvrir":
        rep = ouvrir_app(cible); parler(f"J'ouvre {cible}." if rep.startswith("✅") else f"Je n'ai pas réussi à ouvrir {cible}.")
    elif action == "fermer":
        rep = fermer_app(cible); parler(f"Je ferme {cible}." if rep.startswith("✅") else f"Je n'ai pas trouvé {cible}.")
    elif action == "capture":
        rep = capture_ecran(); parler("Voilà, capture faite.")
    elif action == "web":
        rep = recherche_web(cible); parler(f"Je cherche {cible}.")
    elif action == "volume":
        rep = regler_volume(cible); parler("C'est réglé.")
    elif action == "commande":
        global _cmd_a_confirmer
        cmd = cible or decision.get("commande", "")
        if securite.est_interdit(cmd):
            rep = "❌ Commande interdite (sécurité)"; parler("Non. Cette commande est interdite pour ta sécurité.")
        elif securite.est_destructif(cmd):
            _cmd_a_confirmer = cmd
            etat("reflexion"); log("confirmation requise : " + cmd, "sys")
            parler("Attention, c'est une action sensible. Dis oui pour confirmer, ou non pour annuler.")
            return
        else:
            rep = executer_commande(cmd); parler("C'est fait." if rep.startswith("✅") else "Ça n'a pas marché.")
    else:
        texte = decision.get("texte", "D'accord.")
        rep = "💬 " + texte; parler(texte)

    if rep.startswith("✅"):
        etat("action"); log(rep, "act")
    elif rep.startswith("❌"):
        etat("erreur"); log(rep, "err")
    else:
        etat("veille"); log(rep, "sys")


def _comprendre_simple(commande):
    c = commande.lower()
    if any(m in c for m in ("capture", "photo", "écran", "ecran")):
        return {"action": "capture"}
    if any(m in c for m in ("cherche", "recherche", "google")):
        return {"action": "web", "cible": commande}
    if "volume" in c or "son" in c:
        cible = "muet" if ("muet" in c or "coupe" in c) else ("-" if any(m in c for m in ("baisse", "moins")) else "+")
        return {"action": "volume", "cible": cible}
    if any(m in c for m in ("ouvre", "ouvrir", "lance", "démarre", "demarre")):
        return {"action": "ouvrir", "cible": _dernier_mot(c, ("ouvre", "ouvrir", "lance", "démarre", "demarre", "le", "la", "les", "moi", "un", "une"))}
    if any(m in c for m in ("ferme", "fermer", "quitte")):
        return {"action": "fermer", "cible": _dernier_mot(c, ("ferme", "fermer", "quitte", "le", "la", "les", "moi"))}
    return {"action": "repondre", "texte": "Je n'ai pas compris, tu peux répéter ?"}


def _dernier_mot(phrase, a_retirer):
    mots = [m for m in phrase.split() if m not in a_retirer]
    return mots[-1] if mots else ""


def traiter(commande, envoyer=None):
    global _ollama_prevenu
    commande = commande.strip()
    if not commande:
        return
    if envoyer:
        envoyer("log", texte=commande, genre="in")
        envoyer("etat", valeur="reflexion")
    try:
        decision = cerveau.decider(commande)
    except Exception:
        if not _ollama_prevenu:
            parler("L'intelligence artificielle n'est pas démarrée. Je passe en mode simple.")
            _ollama_prevenu = True
        decision = _comprendre_simple(commande)
    agir(decision, envoyer)


# ----------------------------------------------------------------------------
#  ÉCOUTER (avec auto-diagnostic affiché sur le HUD rouge)
# ----------------------------------------------------------------------------
def _telecharger_modele():
    os.makedirs(DOSSIER_MODELES, exist_ok=True)
    zip_path = CHEMIN_MODELE + ".zip"
    print("⬇️  Téléchargement du modèle vocal (~40 Mo)…")
    urllib.request.urlretrieve(URL_MODELE, zip_path)
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(DOSSIER_MODELES)
    os.remove(zip_path)


def _reveille(texte):
    """Renvoie la commande si on est 'réveillé', '' si juste le mot Jarvis, sinon None."""
    for mot in MOTS_REVEIL:
        if mot in texte:
            return texte.replace(mot, "").strip(" ,.")
    if any(v in texte for v in VERBES_ORDRE):   # ordre clair sans le mot d'activation
        return texte
    return None


def ecouter(envoyer=None):
    global _cmd_a_confirmer

    def diag(texte, genre="sys"):
        """Affiche un message dans la console ET sur le HUD rouge."""
        print("•", texte)
        if envoyer:
            envoyer("log", texte=texte, genre=genre)

    diag("démarrage de l'écoute…")

    try:
        import sounddevice as sd
        import vosk
    except ImportError:
        diag("❌ composants voix manquants — relance INSTALLER", "err")
        parler("Il me manque des composants. Relance l'installateur.")
        return

    # Y a-t-il un micro ?
    try:
        sd.query_devices(kind="input")
    except Exception:
        diag("❌ aucun micro détecté par Windows", "err")
        parler("Je ne détecte aucun micro sur ton ordinateur.")
        return

    if not os.path.isdir(CHEMIN_MODELE):
        diag("téléchargement du modèle vocal…")
        try:
            _telecharger_modele()
        except Exception as e:
            diag(f"❌ modèle vocal indisponible : {e}", "err")
            parler("Je n'ai pas pu télécharger mon modèle vocal.")
            return

    modele = vosk.Model(CHEMIN_MODELE)
    reconnaisseur = vosk.KaldiRecognizer(modele, 16000)
    fifo = queue.Queue()

    def _capter(indata, frames, heure, status):
        fifo.put(bytes(indata))

    if cerveau.ollama_dispo():
        parler("Bonjour. Dis Jarvis, ou donne-moi un ordre.")
    else:
        parler("Bonjour. L'IA n'est pas démarrée, je suis en mode simple.")
    diag("🎤 micro ouvert — parle !", "act")
    if envoyer: envoyer("etat", valeur="veille")

    attend_commande = False
    dernier_son = time.time()
    silence_signale = False

    try:
        flux = sd.RawInputStream(samplerate=16000, blocksize=4000, dtype="int16",
                                 channels=1, callback=_capter)
    except Exception as e:
        diag(f"❌ impossible d'ouvrir le micro : {e}", "err")
        parler("Je n'arrive pas à ouvrir le micro. Vérifie les autorisations Windows.")
        return

    with flux:
        while True:
            donnees = fifo.get()

            # Niveau du micro -> le cercle bouge, ET détection du silence total
            if audioop is not None:
                niveau = audioop.rms(donnees, 2) / 8000.0
                if envoyer:
                    envoyer("niveau", valeur=round(min(1.0, niveau), 3))
                if niveau > 0.02:
                    dernier_son = time.time()
                    silence_signale = False
                elif not silence_signale and time.time() - dernier_son > 10:
                    diag("⚠️ je n'entends aucun son (micro coupé ou mauvaise entrée ?)", "err")
                    parler("Je n'entends aucun son. Vérifie que ton micro est activé.")
                    silence_signale = True

            if not reconnaisseur.AcceptWaveform(donnees):
                continue
            texte = json.loads(reconnaisseur.Result()).get("text", "").strip().lower()
            if not texte:
                continue
            print("👂", texte)
            if envoyer:
                envoyer("log", texte="j'entends : " + texte, genre="in")

            # Confirmation d'une commande sensible ?
            if _cmd_a_confirmer is not None:
                if any(m in texte for m in ("oui", "confirme", "vas-y", "vas y", "d'accord", "ok")):
                    rep = executer_commande(_cmd_a_confirmer)
                    parler("C'est fait." if rep.startswith("✅") else "Ça n'a pas marché.")
                    if envoyer:
                        envoyer("log", texte=rep, genre="act" if rep.startswith("✅") else "err")
                        envoyer("etat", valeur="action" if rep.startswith("✅") else "erreur")
                else:
                    parler("D'accord, j'annule.")
                    if envoyer:
                        envoyer("log", texte="commande annulée", genre="sys")
                        envoyer("etat", valeur="veille")
                _cmd_a_confirmer = None
                continue

            if any(m in texte for m in ("au revoir", "stop jarvis", "arrête-toi", "arrete toi")):
                parler("Au revoir !")
                if envoyer: envoyer("etat", valeur="veille")
                break

            commande = _reveille(texte)
            if commande is None and not attend_commande:
                continue                      # entendu mais pas un ordre / pas « Jarvis »

            if envoyer: envoyer("etat", valeur="ecoute")
            if attend_commande:
                traiter(texte, envoyer); attend_commande = False
            elif commande == "":
                parler("Oui ?"); attend_commande = True
            else:
                traiter(commande, envoyer)
            if envoyer: envoyer("etat", valeur="veille")


if __name__ == "__main__":
    ecouter()
