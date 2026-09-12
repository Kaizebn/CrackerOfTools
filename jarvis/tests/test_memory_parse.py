"""Test de l'extraction JSON des faits retournés par le modèle."""

from __future__ import annotations

from jarvis.memory.manager import _parse_facts


def test_parse_valid_json() -> None:
    raw = 'Voici : [{"fact": "aime le café", "category": "préférence"}, {"fact": "dev python"}]'
    facts = _parse_facts(raw)
    assert facts[0] == {"fact": "aime le café", "category": "préférence"}
    assert facts[1]["category"] == "general"


def test_parse_empty_or_invalid() -> None:
    assert _parse_facts("rien à retenir") == []
    assert _parse_facts("[]") == []
    assert _parse_facts("[pas du json]") == []
