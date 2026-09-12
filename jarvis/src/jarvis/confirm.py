"""Confirmation des actions risquées (niveau CONFIRM).

Un outil risqué n'est exécuté qu'après accord explicite, vocal ET visuel, avec un
timeout. Plusieurs stratégies sont fournies pour couvrir les modes vocal, console et
automatique (dry-run / tests).
"""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import Awaitable, Callable
from typing import Protocol

from jarvis.events import ConfirmationRequested, ConfirmationResolved, EventBus

_YES = {"oui", "ouais", "vas-y", "confirme", "confirmé", "ok", "okay", "yes", "yep", "d'accord", "go"}
_NO = {"non", "annule", "annuler", "stop", "laisse", "no", "nope", "négatif"}


def parse_yes_no(text: str) -> bool | None:
    """Interprète une réponse orale en oui/non. None si ambigu."""
    words = {w.strip(".,!?") for w in text.lower().split()}
    if words & _YES:
        return True
    if words & _NO:
        return False
    return None


class Confirmer(Protocol):
    async def confirm(self, prompt: str) -> bool: ...


class AutoConfirmer:
    """Répond toujours la même chose (utile en dry-run ou en tests)."""

    def __init__(self, default: bool = False) -> None:
        self._default = default

    async def confirm(self, prompt: str) -> bool:
        return self._default


class ConsoleConfirmer:
    """Lit la réponse sur l'entrée standard, avec timeout (mode --text)."""

    def __init__(self, timeout_s: float = 15.0) -> None:
        self._timeout = timeout_s

    async def confirm(self, prompt: str) -> bool:
        print(f"\n[confirmation] {prompt} (oui/non) ", end="", flush=True)
        try:
            answer = await asyncio.wait_for(asyncio.to_thread(input), timeout=self._timeout)
        except asyncio.TimeoutError:
            print("\n[confirmation] délai dépassé → annulé.")
            return False
        return parse_yes_no(answer) is True


class VoiceConfirmer:
    """Pose la question à voix haute, écoute une réponse courte, interprète oui/non.

    ``speak`` lit le texte ; ``listen`` enregistre et transcrit une réponse courte.
    L'orchestrateur fournit ces deux callbacks (il détient le TTS et le STT).
    """

    def __init__(
        self,
        speak: Callable[[str], Awaitable[None]],
        listen: Callable[[], Awaitable[str]],
        bus: EventBus | None = None,
        timeout_s: float = 15.0,
    ) -> None:
        self._speak = speak
        self._listen = listen
        self._bus = bus
        self._timeout = timeout_s

    async def confirm(self, prompt: str) -> bool:
        request_id = uuid.uuid4().hex
        if self._bus is not None:
            await self._bus.publish(ConfirmationRequested(request_id=request_id, prompt=prompt))
        await self._speak(prompt)
        approved = False
        try:
            answer = await asyncio.wait_for(self._listen(), timeout=self._timeout)
            approved = parse_yes_no(answer) is True
        except asyncio.TimeoutError:
            approved = False
        if self._bus is not None:
            await self._bus.publish(ConfirmationResolved(request_id=request_id, approved=approved))
        return approved
