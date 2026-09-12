"""Domotique Home Assistant : client REST + WebSocket et outils associés.

Les entités sont mises en cache au démarrage (REST) puis tenues à jour en temps réel
via WebSocket, ce qui permet de résoudre « la lampe du salon » vers ``light.salon``.
"""

from __future__ import annotations

import asyncio
import difflib
from typing import Any

import aiohttp
from pydantic import BaseModel, Field

from jarvis.logging_config import get_logger
from jarvis.tools.registry import Risk, ToolContext, ToolResult, tool

_log = get_logger("jarvis.home")
_TIMEOUT = aiohttp.ClientTimeout(total=15)


class HomeAssistantClient:
    def __init__(self, base_url: str, token: str) -> None:
        self._base = base_url.rstrip("/")
        self._token = token
        self._headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
        self._states: dict[str, dict[str, Any]] = {}
        self._ws_task: asyncio.Task[None] | None = None

    @property
    def _rest(self) -> str:
        return f"{self._base}/api"

    async def connect(self) -> None:
        """Charge l'état initial et lance l'écoute temps réel (best-effort)."""
        await self.refresh_states()
        self._ws_task = asyncio.create_task(self._listen())

    async def shutdown(self) -> None:
        if self._ws_task is not None:
            self._ws_task.cancel()

    async def refresh_states(self) -> None:
        async with aiohttp.ClientSession(timeout=_TIMEOUT, headers=self._headers) as session:
            async with session.get(f"{self._rest}/states") as response:
                response.raise_for_status()
                payload = await response.json()
        self._states = {item["entity_id"]: item for item in payload}
        _log.info("home.states_loaded", count=len(self._states))

    async def call_service(
        self, domain: str, service: str, entity_id: str | None, data: dict[str, Any] | None
    ) -> None:
        body: dict[str, Any] = dict(data or {})
        if entity_id is not None:
            body["entity_id"] = entity_id
        async with aiohttp.ClientSession(timeout=_TIMEOUT, headers=self._headers) as session:
            async with session.post(f"{self._rest}/services/{domain}/{service}", json=body) as response:
                response.raise_for_status()

    def get_state(self, entity_id: str) -> dict[str, Any] | None:
        return self._states.get(entity_id)

    def entities(self, domain: str | None = None) -> list[dict[str, str]]:
        result = []
        for entity_id, state in self._states.items():
            if domain is not None and not entity_id.startswith(f"{domain}."):
                continue
            friendly = state.get("attributes", {}).get("friendly_name", entity_id)
            result.append({"entity_id": entity_id, "name": friendly, "state": state.get("state", "")})
        return result

    def resolve(self, text: str, domain: str | None = None) -> str | None:
        """Résout un nom courant (ou un entity_id) vers un entity_id."""
        if text in self._states:
            return text
        candidates: dict[str, str] = {}
        for entity_id, state in self._states.items():
            if domain is not None and not entity_id.startswith(f"{domain}."):
                continue
            friendly = str(state.get("attributes", {}).get("friendly_name", "")).lower()
            if friendly:
                candidates[friendly] = entity_id
            candidates[entity_id.lower()] = entity_id
        target = text.lower()
        if target in candidates:
            return candidates[target]
        partial = [name for name in candidates if target in name]
        if partial:
            return candidates[partial[0]]
        matches = difflib.get_close_matches(target, list(candidates), n=1, cutoff=0.5)
        return candidates[matches[0]] if matches else None

    def summary(self) -> str:
        lights_on = [
            s["attributes"].get("friendly_name", eid)
            for eid, s in self._states.items()
            if eid.startswith("light.") and s.get("state") == "on"
        ]
        if not self._states:
            return "non connectée"
        if not lights_on:
            return "toutes les lumières sont éteintes"
        return f"{len(lights_on)} lumière(s) allumée(s) : " + ", ".join(lights_on[:5])

    async def _listen(self) -> None:
        ws_url = self._base.replace("http", "ws", 1) + "/api/websocket"
        try:
            async with aiohttp.ClientSession() as session:
                async with session.ws_connect(ws_url) as ws:
                    await self._ws_auth(ws)
                    await ws.send_json({"id": 1, "type": "subscribe_events", "event_type": "state_changed"})
                    async for message in ws:
                        if message.type is aiohttp.WSMsgType.TEXT:
                            self._apply_event(message.json())
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 - le temps réel est optionnel, REST reste OK
            _log.warning("home.ws_stopped", error=str(exc))

    async def _ws_auth(self, ws: aiohttp.ClientWebSocketResponse) -> None:
        await ws.receive_json()  # auth_required
        await ws.send_json({"type": "auth", "access_token": self._token})
        await ws.receive_json()  # auth_ok / auth_invalid

    def _apply_event(self, message: dict[str, Any]) -> None:
        if message.get("type") != "event":
            return
        data = message.get("event", {}).get("data", {})
        new_state = data.get("new_state")
        entity_id = data.get("entity_id")
        if entity_id and isinstance(new_state, dict):
            self._states[entity_id] = new_state


# --- Outils ---


class ListEntitiesArgs(BaseModel):
    domain: str | None = Field(default=None, description="Filtrer par domaine (light, switch, climate…).")


class EntityArgs(BaseModel):
    entity: str = Field(description="Entité (nom courant ou entity_id).")


class CallServiceArgs(BaseModel):
    domain: str = Field(description="Domaine du service (light, switch, climate…).")
    service: str = Field(description="Service à appeler (turn_on, turn_off…).")
    entity: str | None = Field(default=None, description="Entité cible.")
    data: dict[str, Any] | None = Field(default=None, description="Données supplémentaires.")


class BrightnessEntityArgs(BaseModel):
    entity: str = Field(description="Entité lumière.")
    percent: int = Field(ge=0, le=100, description="Luminosité en pourcentage.")


class TemperatureArgs(BaseModel):
    entity: str = Field(description="Entité climat/thermostat.")
    temperature: float = Field(description="Température cible en °C.")


def _require_home(ctx: ToolContext) -> HomeAssistantClient | None:
    return ctx.home


@tool(name="list_entities", risk=Risk.SAFE)
async def list_entities(args: ListEntitiesArgs, ctx: ToolContext) -> ToolResult:
    """Liste les entités Home Assistant, éventuellement filtrées par domaine."""
    home = _require_home(ctx)
    if home is None:
        return ToolResult.fail("Home Assistant n'est pas configuré.")
    entities = home.entities(args.domain)
    return ToolResult.success(f"{len(entities)} entité(s).", entities=entities[:60])


@tool(name="get_entity_state", risk=Risk.SAFE)
async def get_entity_state(args: EntityArgs, ctx: ToolContext) -> ToolResult:
    """Donne l'état d'une entité Home Assistant."""
    home = _require_home(ctx)
    if home is None:
        return ToolResult.fail("Home Assistant n'est pas configuré.")
    entity_id = home.resolve(args.entity)
    if entity_id is None:
        return ToolResult.fail(f"Entité introuvable : {args.entity}.")
    state = home.get_state(entity_id)
    if state is None:
        return ToolResult.fail("État indisponible.")
    return ToolResult.success(f"{entity_id} : {state.get('state')}.", entity_id=entity_id, state=state.get("state"))


@tool(name="call_service", risk=Risk.SAFE, side_effect=True)
async def call_service(args: CallServiceArgs, ctx: ToolContext) -> ToolResult:
    """Appelle un service Home Assistant sur une entité."""
    home = _require_home(ctx)
    if home is None:
        return ToolResult.fail("Home Assistant n'est pas configuré.")
    entity_id = home.resolve(args.entity, args.domain) if args.entity else None
    await home.call_service(args.domain, args.service, entity_id, args.data)
    return ToolResult.success(f"{args.domain}.{args.service} exécuté.")


@tool(name="turn_on", risk=Risk.SAFE, side_effect=True)
async def turn_on(args: EntityArgs, ctx: ToolContext) -> ToolResult:
    """Allume une entité (lumière, prise…)."""
    return await _switch(ctx, args.entity, True)


@tool(name="turn_off", risk=Risk.SAFE, side_effect=True)
async def turn_off(args: EntityArgs, ctx: ToolContext) -> ToolResult:
    """Éteint une entité (lumière, prise…)."""
    return await _switch(ctx, args.entity, False)


async def _switch(ctx: ToolContext, entity: str, on: bool) -> ToolResult:
    home = _require_home(ctx)
    if home is None:
        return ToolResult.fail("Home Assistant n'est pas configuré.")
    entity_id = home.resolve(entity)
    if entity_id is None:
        return ToolResult.fail(f"Entité introuvable : {entity}.")
    domain = entity_id.split(".", 1)[0]
    await home.call_service(domain, "turn_on" if on else "turn_off", entity_id, None)
    return ToolResult.success("Voilà.")


@tool(name="set_light_brightness", risk=Risk.SAFE, side_effect=True)
async def set_light_brightness(args: BrightnessEntityArgs, ctx: ToolContext) -> ToolResult:
    """Règle la luminosité d'une lumière Home Assistant en pourcentage."""
    home = _require_home(ctx)
    if home is None:
        return ToolResult.fail("Home Assistant n'est pas configuré.")
    entity_id = home.resolve(args.entity, "light")
    if entity_id is None:
        return ToolResult.fail(f"Lumière introuvable : {args.entity}.")
    await home.call_service("light", "turn_on", entity_id, {"brightness_pct": args.percent})
    return ToolResult.success(f"Luminosité à {args.percent}%.")


@tool(name="set_temperature", risk=Risk.SAFE, side_effect=True)
async def set_temperature(args: TemperatureArgs, ctx: ToolContext) -> ToolResult:
    """Règle la température cible d'un thermostat Home Assistant."""
    home = _require_home(ctx)
    if home is None:
        return ToolResult.fail("Home Assistant n'est pas configuré.")
    entity_id = home.resolve(args.entity, "climate")
    if entity_id is None:
        return ToolResult.fail(f"Thermostat introuvable : {args.entity}.")
    await home.call_service("climate", "set_temperature", entity_id, {"temperature": args.temperature})
    return ToolResult.success(f"Température réglée à {args.temperature}°C.")
