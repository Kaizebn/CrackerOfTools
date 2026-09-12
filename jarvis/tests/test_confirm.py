"""Tests de la confirmation : interprétation oui/non et stratégies simples."""

from __future__ import annotations

from jarvis.confirm import AutoConfirmer, parse_yes_no


def test_parse_yes_no() -> None:
    assert parse_yes_no("oui vas-y") is True
    assert parse_yes_no("non laisse tomber") is False
    assert parse_yes_no("euh je ne sais pas") is None


async def test_auto_confirmer() -> None:
    assert await AutoConfirmer(default=True).confirm("?") is True
    assert await AutoConfirmer(default=False).confirm("?") is False
