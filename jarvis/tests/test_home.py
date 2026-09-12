"""Tests de la résolution d'entités Home Assistant (sans réseau)."""

from __future__ import annotations

from jarvis.tools.home import HomeAssistantClient


def _client() -> HomeAssistantClient:
    client = HomeAssistantClient("http://ha.local:8123", "token")
    client._states = {  # noqa: SLF001 - on injecte un état factice pour le test
        "light.salon": {"state": "on", "attributes": {"friendly_name": "Lampe du salon"}},
        "light.cuisine": {"state": "off", "attributes": {"friendly_name": "Lampe cuisine"}},
    }
    return client


def test_resolve_by_friendly_name() -> None:
    client = _client()
    assert client.resolve("lampe du salon") == "light.salon"
    assert client.resolve("salon", domain="light") == "light.salon"


def test_resolve_by_entity_id() -> None:
    assert _client().resolve("light.cuisine") == "light.cuisine"


def test_summary_counts_lights_on() -> None:
    summary = _client().summary()
    assert "1 lumière" in summary or "1 lumière(s)" in summary
