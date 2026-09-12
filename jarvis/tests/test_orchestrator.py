"""Test de bout en bout du cerveau : streaming + boucle tool_use → TTS phrase par phrase."""

from __future__ import annotations

from pydantic import BaseModel

from jarvis.config import Settings
from jarvis.confirm import AutoConfirmer
from jarvis.events import EventBus
from jarvis.llm.base import StreamCompleted, StreamEvent, TextDelta, ToolUseBlock, ToolUseReady
from jarvis.orchestrator import Orchestrator
from jarvis.state import State, StateMachine
from jarvis.tools.registry import Risk, ToolContext, ToolRegistry, ToolResult

from tests.fakes import FakeLLMProvider, FakeSpeaker

calls: list[str] = []
registry = ToolRegistry()


class PingArgs(BaseModel):
    pass


@registry.tool(name="ping", risk=Risk.SAFE)
async def ping(args: PingArgs, ctx: ToolContext) -> ToolResult:
    """Répond pong."""
    calls.append("ping")
    return ToolResult.success("pong")


async def test_full_turn_with_tool_use() -> None:
    calls.clear()
    turns: list[list[StreamEvent]] = [
        # 1er tour : le modèle appelle l'outil ping.
        [
            ToolUseReady(id="t1", name="ping", arguments={}),
            StreamCompleted(stop_reason="tool_use", text="", tool_uses=[ToolUseBlock(id="t1", name="ping", arguments={})]),
        ],
        # 2e tour : il répond en texte après avoir vu le résultat.
        [
            TextDelta(text="Tout est prêt. "),
            TextDelta(text="Je reste à l'écoute."),
            StreamCompleted(stop_reason="end_turn", text="Tout est prêt. Je reste à l'écoute.", tool_uses=[]),
        ],
    ]
    llm = FakeLLMProvider(turns)
    bus = EventBus()
    state = StateMachine(bus)
    speaker = FakeSpeaker()
    ctx = ToolContext(settings=Settings(), bus=bus, confirmer=AutoConfirmer(default=True))
    orchestrator = Orchestrator(Settings(), bus, state, llm, registry, ctx, speaker)

    result = await orchestrator.handle_user_text("prépare-toi")

    assert "ping" in calls  # l'outil a bien été exécuté
    assert "prêt" in result
    assert any("prêt" in sentence for sentence in speaker.said)  # lu phrase par phrase
    assert state.state is State.IDLE  # retour au repos en fin de tour


async def test_empty_transcript_returns_to_idle() -> None:
    llm = FakeLLMProvider([])
    bus = EventBus()
    state = StateMachine(bus)
    ctx = ToolContext(settings=Settings(), bus=bus, confirmer=AutoConfirmer())
    orchestrator = Orchestrator(Settings(), bus, state, llm, registry, ctx, FakeSpeaker())

    result = await orchestrator.handle_user_text("   ")
    assert result == ""
    assert state.state is State.IDLE
