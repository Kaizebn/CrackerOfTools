"""
serveur.py — Le pont temps réel entre le backend et le HUD (Étape 3).

Le backend démarre un petit serveur WebSocket. Le HUD (dans le navigateur/pywebview)
s'y connecte comme un client. Ensuite, le backend peut ENVOYER des messages au HUD :
  - {"type":"etat", "valeur":"reflexion"}   -> change l'état affiché
  - {"type":"log",  "texte":"...", "genre":"in|act|err|sys"}  -> ajoute une ligne

Tout se passe en local (127.0.0.1) : rien ne sort de ton PC.
"""

import asyncio
import json
import threading

try:
    import websockets
except ImportError:
    websockets = None  # message clair plus bas si la librairie manque

ADRESSE = "127.0.0.1"
PORT = 8765

_clients = set()      # les HUD connectés
_boucle = None        # la boucle asyncio (tourne dans un thread à part)


async def _gerer(ws):
    """Un HUD vient de se connecter : on le garde jusqu'à sa déconnexion."""
    _clients.add(ws)
    try:
        async for _ in ws:   # on ignore les messages entrants pour l'instant
            pass
    except Exception:
        pass
    finally:
        _clients.discard(ws)


async def _principal():
    async with websockets.serve(_gerer, ADRESSE, PORT):
        await asyncio.Future()   # tourne indéfiniment


def demarrer_serveur():
    """Démarre le serveur WebSocket dans un thread de fond (non bloquant)."""
    global _boucle
    if websockets is None:
        print("[serveur] La librairie 'websockets' manque. Lance : pip install -r requirements.txt")
        return
    _boucle = asyncio.new_event_loop()

    def _tourner():
        asyncio.set_event_loop(_boucle)
        _boucle.run_until_complete(_principal())

    threading.Thread(target=_tourner, daemon=True).start()
    print(f"[serveur] WebSocket prêt sur ws://{ADRESSE}:{PORT}")


def envoyer(type_, **donnees):
    """Envoie un message JSON à TOUS les HUD connectés.
    Appelable depuis du code normal (non-async) : c'est thread-safe."""
    if _boucle is None:
        return
    message = json.dumps({"type": type_, **donnees})

    async def _diffuser():
        for ws in list(_clients):
            try:
                await ws.send(message)
            except Exception:
                _clients.discard(ws)

    asyncio.run_coroutine_threadsafe(_diffuser(), _boucle)
