"""
voix.py — L'oreille et la voix de JARVIS (Étape 4, version complète).

- ÉCOUTE en continu (Vosk, local). Il faut dire « Jarvis » pour qu'il agisse.
- COMPREND avec l'IA locale (cerveau.py / Ollama). Repli automatique en
  "mode simple" (mots-clés) si Ollama n'est pas démarré.
- PARLE ses réponses (pyttsx3, hors-ligne).
- Envoie au HUD : l'état, le journal, et le NIVEAU du micro (le cercle bouge).

Test seul :  python voix.py     (sans HUD ; le HUD est branché par jarvis.py)
"""

import os
import json
import queue
import zipfile
import urllib.request

try:
    import audioop            # sert à mesurer le niveau du micro (Python <= 3.12)
except Exception:
    audioop = None

import cerveau
import securite
from actions import (ouvrir_app, fermer_app, capture_ecran,
                     regler_volume, recherche_web, executer_commande)

ICI = os.path.dirname(os.path.abspath(__file__))
DOSSIER_MODELES = os.path.join(ICI, "modeles")
NOM_MODELE = "vosk-model-small-fr-0.22"
URL_MODELE = "https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip"
CHEMIN_MODELE = os.path.join(DOSSIER_MODELES, NOM_MODELE)

MOT_ACTIVATION = "jarvis"

_moteur = None
_ollama_prevenu = False
_cmd_a_confirmer = None      # commande sensible en attente d'un « oui » vocal


# ----------------------------------------------------------------------------
#  LA VOIX
# ----------------------------------------------------------------------------
def parler(texte):
    global _moteur
    print("🔊 JARVIS :", texte)
    try:
        import pyttsx3
        if _moteur is None:
            _moteur = pyttsx3.init()
            for v in _moteur.getProperty("voices"):
                etiquette = (getattr(v, "id", "") + " " + getattr(v, "name", "")).lower()
                if "fr" in etiquette or "french" in etiquette:
                    _moteur.setProperty("voice", v.id)
                    break
        _moteur.say(texte)
        _moteur.runAndWait()
    except Exception as e:
        print("[voix] synthèse indisponible :", e)


# ----------------------------------------------------------------------------
#  AGIR selon une décision {action: ...} (venue de l'IA ou du mode simple)
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
        # Niveau 2 : commande système arbitraire, avec garde-fous.
        global _cmd_a_confirmer
        cmd = cible or decision.get("commande", "")
        if securite.est_interdit(cmd):
            rep = "❌ Commande interdite (sécurité)"
            parler("Non. Cette commande est interdite pour ta sécurité.")
        elif securite.est_destructif(cmd):
            _cmd_a_confirmer = cmd
            etat("reflexion"); log("confirmation requise : " + cmd, "sys")
            parler("Attention, c'est une action sensible. Dis oui pour confirmer, ou non pour annuler.")
            return
        else:
            rep = executer_commande(cmd)
            parler("C'est fait." if rep.startswith("✅") else "Ça n'a pas marché.")
    else:  # repondre
        texte = decision.get("texte", "D'accord.")
        rep = "💬 " + texte; parler(texte)

    if rep.startswith("✅"):
        etat("action"); log(rep, "act")
    elif rep.startswith("❌"):
        etat("erreur"); log(rep, "err")
    else:
        etat("veille"); log(rep, "sys")


def _comprendre_simple(commande):
    """Mode de secours par mots-clés, si l'IA n'est pas disponible."""
    c = commande.lower()
    if any(m in c for m in ("capture", "photo", "écran", "ecran")):
        return {"action": "capture"}
    if any(m in c for m in ("cherche", "recherche", "google")):
        return {"action": "web", "cible": commande}
    if "volume" in c or "son" in c:
        cible = "muet" if "muet" in c or "coupe" in c else ("-" if any(m in c for m in ("baisse", "moins")) else "+")
        return {"action": "volume", "cible": cible}
    if any(m in c for m in ("ouvre", "ouvrir", "lance", "démarre", "demarre")):
        return {"action": "ouvrir", "cible": _dernier_mot(c, ("ouvre", "ouvrir", "lance", "démarre", "demarre", "le", "la", "les", "moi"))}
    if any(m in c for m in ("ferme", "fermer", "quitte")):
        return {"action": "fermer", "cible": _dernier_mot(c, ("ferme", "fermer", "quitte", "le", "la", "les", "moi"))}
    return {"action": "repondre", "texte": "Je n'ai pas compris, tu peux répéter ?"}


def _dernier_mot(phrase, a_retirer):
    mots = [m for m in phrase.split() if m not in a_retirer]
    return mots[-1] if mots else ""


def traiter(commande, envoyer=None):
    """Comprend la commande (IA d'abord, sinon mode simple) puis agit."""
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
#  ÉCOUTER (avec mot d'activation « Jarvis »)
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
    """Boucle d'écoute. Dis « Jarvis … » pour donner un ordre,
    ou « Jarvis » seul (il répond « Oui ? ») puis ta demande.
    Dis « au revoir » pour arrêter."""
    global _cmd_a_confirmer
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
        envoyer("etat", valeur="veille")
    if cerveau.ollama_dispo():
        parler("Bonjour. Dis Jarvis pour me parler.")
    else:
        parler("Bonjour. L'IA n'est pas démarrée, je fonctionne en mode simple. Dis Jarvis pour me parler.")
    print("🎙️  En écoute. Dis « Jarvis … » (au revoir pour arrêter)")

    attend_commande = False
    with sd.RawInputStream(samplerate=16000, blocksize=4000, dtype="int16",
                           channels=1, callback=_capter):
        while True:
            donnees = fifo.get()

            # niveau du micro -> le cercle du HUD bouge
            if envoyer and audioop is not None:
                niveau = min(1.0, audioop.rms(donnees, 2) / 8000.0)
                envoyer("niveau", valeur=round(niveau, 3))

            if not reconnaisseur.AcceptWaveform(donnees):
                continue
            texte = json.loads(reconnaisseur.Result()).get("text", "").strip().lower()
            if not texte:
                continue
            print("👂", texte)

            # Une commande sensible attend un « oui » / « non » ?
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

            if MOT_ACTIVATION in texte:
                if envoyer: envoyer("etat", valeur="ecoute")
                reste = texte.replace(MOT_ACTIVATION, "").strip(" ,.")
                if reste:
                    traiter(reste, envoyer)
                else:
                    parler("Oui ?")
                    attend_commande = True
                if envoyer: envoyer("etat", valeur="veille")
            elif attend_commande:
                traiter(texte, envoyer)
                attend_commande = False
                if envoyer: envoyer("etat", valeur="veille")
            # sinon : entendu mais pas adressé à Jarvis -> on ignore


if __name__ == "__main__":
    ecouter()
