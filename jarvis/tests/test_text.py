"""Tests du découpage en phrases et du nettoyage markdown."""

from __future__ import annotations

from jarvis.text import SentenceSplitter, strip_markdown


def test_strip_markdown() -> None:
    assert strip_markdown("**gras** et *italique*") == "gras et italique"
    assert strip_markdown("# Titre\n- point") == "Titre point"
    assert "http" not in strip_markdown("[lien](http://x.y)")


def test_splitter_releases_complete_sentences() -> None:
    splitter = SentenceSplitter()
    assert splitter.feed("Bonjour Monsieur. ") == ["Bonjour Monsieur."]
    assert splitter.feed("Comment ") == []
    assert splitter.feed("allez-vous ?") == ["Comment allez-vous ?"]


def test_splitter_flush_returns_remainder() -> None:
    splitter = SentenceSplitter()
    assert splitter.feed("Sans ponctuation finale") == []
    assert splitter.flush() == "Sans ponctuation finale"
    assert splitter.flush() is None


def test_splitter_ignores_abbreviation_boundary() -> None:
    splitter = SentenceSplitter()
    # "etc." ne doit pas couper la phrase prématurément.
    out = splitter.feed("Des pommes, etc. et des poires. ")
    assert out == ["Des pommes, etc. et des poires."]
