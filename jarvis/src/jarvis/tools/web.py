"""Outils web : recherche, extraction de page, météo (Open-Meteo), actualités."""

from __future__ import annotations

import asyncio
from typing import Any

import aiohttp
from pydantic import BaseModel, Field

from jarvis.tools.registry import Risk, ToolContext, ToolResult, tool

_TIMEOUT = aiohttp.ClientTimeout(total=15)
_WEATHER_CODES = {
    0: "ciel dégagé", 1: "plutôt dégagé", 2: "partiellement nuageux", 3: "couvert",
    45: "brouillard", 48: "brouillard givrant", 51: "bruine légère", 53: "bruine",
    55: "bruine dense", 61: "pluie faible", 63: "pluie", 65: "forte pluie",
    71: "neige faible", 73: "neige", 75: "forte neige", 80: "averses",
    81: "averses", 82: "fortes averses", 95: "orage", 96: "orage avec grêle",
}


async def _get_json(url: str, params: dict[str, Any]) -> Any:
    async with aiohttp.ClientSession(timeout=_TIMEOUT) as session:
        async with session.get(url, params=params) as response:
            response.raise_for_status()
            return await response.json()


async def _get_text(url: str) -> str:
    async with aiohttp.ClientSession(timeout=_TIMEOUT) as session:
        async with session.get(url, headers={"User-Agent": "JarvisBot/1.0"}) as response:
            response.raise_for_status()
            return await response.text()


class SearchWebArgs(BaseModel):
    query: str = Field(description="La requête de recherche.")
    max_results: int = Field(default=5, ge=1, le=10)


class FetchPageArgs(BaseModel):
    url: str = Field(description="URL de la page à lire.")


class WeatherArgs(BaseModel):
    city: str = Field(description="Ville pour laquelle obtenir la météo.")


class NewsArgs(BaseModel):
    topic: str = Field(description="Sujet des actualités recherchées.")


async def _search_tavily(api_key: str, query: str, max_results: int) -> list[dict[str, str]]:
    from tavily import TavilyClient

    def _run() -> list[dict[str, str]]:
        client = TavilyClient(api_key=api_key)
        response = client.search(query=query, max_results=max_results)
        results = response.get("results", [])
        return [
            {"title": r.get("title", ""), "url": r.get("url", ""), "snippet": r.get("content", "")}
            for r in results
        ]

    return await asyncio.to_thread(_run)


async def _search_ddg(query: str, max_results: int) -> list[dict[str, str]]:
    from ddgs import DDGS

    def _run() -> list[dict[str, str]]:
        with DDGS() as ddgs:
            hits = list(ddgs.text(query, max_results=max_results))
        return [
            {"title": h.get("title", ""), "url": h.get("href", ""), "snippet": h.get("body", "")}
            for h in hits
        ]

    return await asyncio.to_thread(_run)


@tool(name="search_web", risk=Risk.SAFE)
async def search_web(args: SearchWebArgs, ctx: ToolContext) -> ToolResult:
    """Recherche sur le web et renvoie des titres, liens et extraits."""
    if ctx.settings.tavily_api_key:
        results = await _search_tavily(ctx.settings.tavily_api_key, args.query, args.max_results)
    else:
        results = await _search_ddg(args.query, args.max_results)
    if not results:
        return ToolResult.success("Aucun résultat.")
    return ToolResult.success(f"{len(results)} résultat(s).", results=results)


@tool(name="fetch_page", risk=Risk.SAFE)
async def fetch_page(args: FetchPageArgs, ctx: ToolContext) -> ToolResult:
    """Récupère une page web et renvoie son texte principal, tronqué intelligemment."""
    import trafilatura

    html = await _get_text(args.url)
    extracted = await asyncio.to_thread(trafilatura.extract, html)
    text = (extracted or "").strip()
    if not text:
        return ToolResult.fail("Impossible d'extraire le contenu de cette page.")
    truncated = text[:4000]
    suffix = "…" if len(text) > 4000 else ""
    return ToolResult.success(truncated + suffix)


@tool(name="get_weather", risk=Risk.SAFE)
async def get_weather(args: WeatherArgs, ctx: ToolContext) -> ToolResult:
    """Donne la météo actuelle et la tendance de demain pour une ville (Open-Meteo)."""
    geo = await _get_json(
        "https://geocoding-api.open-meteo.com/v1/search",
        {"name": args.city, "count": 1, "language": "fr"},
    )
    places = geo.get("results") or []
    if not places:
        return ToolResult.fail(f"Ville introuvable : {args.city}.")
    place = places[0]
    forecast = await _get_json(
        "https://api.open-meteo.com/v1/forecast",
        {
            "latitude": place["latitude"],
            "longitude": place["longitude"],
            "current": "temperature_2m,weather_code",
            "daily": "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max",
            "timezone": "auto",
            "forecast_days": 2,
        },
    )
    current = forecast.get("current", {})
    daily = forecast.get("daily", {})
    now_desc = _WEATHER_CODES.get(int(current.get("weather_code", -1)), "conditions inconnues")
    data = {
        "city": place.get("name", args.city),
        "now": f"{current.get('temperature_2m')}°C, {now_desc}",
        "tomorrow": {
            "min": daily.get("temperature_2m_min", [None, None])[1],
            "max": daily.get("temperature_2m_max", [None, None])[1],
            "desc": _WEATHER_CODES.get(int(daily.get("weather_code", [0, -1])[1]), "?"),
            "rain_prob": daily.get("precipitation_probability_max", [None, None])[1],
        },
    }
    summary = (
        f"{data['city']} : actuellement {data['now']}. "
        f"Demain {data['tomorrow']['desc']}, de {data['tomorrow']['min']} à "
        f"{data['tomorrow']['max']}°C, pluie {data['tomorrow']['rain_prob']}%."
    )
    return ToolResult.success(summary, **data)


@tool(name="get_news", risk=Risk.SAFE)
async def get_news(args: NewsArgs, ctx: ToolContext) -> ToolResult:
    """Donne les actualités récentes sur un sujet (via la recherche web)."""
    query = f"actualités {args.topic}"
    if ctx.settings.tavily_api_key:
        results = await _search_tavily(ctx.settings.tavily_api_key, query, 5)
    else:
        results = await _search_ddg(query, 5)
    if not results:
        return ToolResult.success("Aucune actualité trouvée.")
    return ToolResult.success(f"{len(results)} actualité(s).", results=results)
