"""Charge tous les modules d'outils pour peupler le registre global."""

from __future__ import annotations

from jarvis.tools.registry import ToolRegistry, registry


def load_registry() -> ToolRegistry:
    # L'import déclenche les décorateurs @tool qui enregistrent chaque outil.
    from jarvis.tools import (  # noqa: F401
        files,
        home,
        memory_tools,
        system,
        timers,
        web,
    )

    return registry
