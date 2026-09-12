"""Orchestrateur : le cerveau qui relie STT → LLM (streaming + outils) → TTS.

Points clés :
- Streaming de bout en bout : on lit chaque phrase dès qu'elle est complète pendant que
  le LLM génère la suite (latence minimale).
- Boucle tool_use ↔ tool_result jusqu'à ce que le modèle n'appelle plus d'outil.
- Contexte injecté à chaque tour (date, utilisateur, apps, domotique, souvenirs).
- Gestion d'erreur : toute panne se solde par un message vocal calme et un retour à IDLE,
  jamais un crash.
"""

from __future__ import annotations

import asyncio
from collections.abc import Coroutine
from datetime import datetime

from jarvis.config import Settings
from jarvis.events import (
    AssistantChunk,
    AssistantCompleted,
    AssistantSentence,
    AssistantStarted,
    ErrorOccurred,
    EventBus,
    ReminderDue,
)
from jarvis.llm.base import (
    ContentBlock,
    LLMError,
    LLMProvider,
    Message,
    StreamCompleted,
    TextBlock,
    TextDelta,
    ToolResultBlock,
    ToolUseBlock,
    ToolUseReady,
)
from jarvis.llm.prompts import PromptContext, build_system_prompt
from jarvis.logging_config import get_logger
from jarvis.memory.manager import MemoryManager
from jarvis.notify import toast
from jarvis.speaker import Speaker
from jarvis.state import State, StateMachine
from jarvis.text import SentenceSplitter
from jarvis.tools.home import HomeAssistantClient
from jarvis.tools.registry import ToolContext, ToolRegistry

_log = get_logger("jarvis.orchestrator")

_ERROR_REPLY = "Un souci technique m'empêche de répondre pour l'instant. Je reste à l'écoute."


class Orchestrator:
    def __init__(
        self,
        settings: Settings,
        bus: EventBus,
        state: StateMachine,
        llm: LLMProvider,
        registry: ToolRegistry,
        ctx: ToolContext,
        speaker: Speaker,
        memory: MemoryManager | None = None,
        home: HomeAssistantClient | None = None,
    ) -> None:
        self._settings = settings
        self._bus = bus
        self._state = state
        self._llm = llm
        self._registry = registry
        self._ctx = ctx
        self._speaker = speaker
        self._memory = memory
        self._home = home
        self._history: list[Message] = []
        self._tasks: set[asyncio.Task[None]] = set()

    async def start(self) -> None:
        if self._memory is not None:
            await self._memory.start_conversation()
        self._spawn(self._watch_reminders())

    async def stop(self) -> None:
        for task in self._tasks:
            task.cancel()

    async def handle_user_text(self, text: str) -> str:
        """Traite un tour complet et renvoie la réponse finale (texte)."""
        text = text.strip()
        if not text:
            await self._to_idle()
            return ""
        await self._enter_thinking()
        await self._bus.publish(AssistantStarted())
        if self._memory is not None:
            await self._memory.add_message("user", text)
        try:
            system = await self._build_system(text)
            final_text = await self._run_llm(system, self._history + [Message.user_text(text)])
        except LLMError as exc:
            return await self._fail(str(exc))
        except Exception as exc:  # noqa: BLE001 - on ne crashe jamais le pipeline vocal
            _log.exception("orchestrator.unexpected")
            return await self._fail(str(exc))

        await self._speaker.wait()
        await self._to_idle()
        await self._bus.publish(AssistantCompleted(text=final_text))
        self._remember_turn(text, final_text)
        return final_text

    async def _run_llm(self, system: str, working: list[Message]) -> str:
        splitter = SentenceSplitter()
        messages = list(working)
        final_parts: list[str] = []

        while True:
            turn_text = ""
            tool_uses: list[ToolUseBlock] = []
            async for event in self._llm.stream(
                messages,
                system,
                self._registry.schemas(),
                model=self._settings.model,
                max_tokens=self._settings.max_tokens,
            ):
                if isinstance(event, TextDelta):
                    turn_text += event.text
                    await self._bus.publish(AssistantChunk(text=event.text))
                    for sentence in splitter.feed(event.text):
                        await self._speak_sentence(sentence)
                elif isinstance(event, ToolUseReady):
                    _log.info("llm.tool_requested", name=event.name)
                elif isinstance(event, StreamCompleted):
                    tool_uses = event.tool_uses
            final_parts.append(turn_text)

            if not tool_uses:
                break

            messages.append(_assistant_message(turn_text, tool_uses))
            results: list[ContentBlock] = [await self._run_tool(use) for use in tool_uses]
            messages.append(Message(role="user", content=results))

        remaining = splitter.flush()
        if remaining:
            await self._speak_sentence(remaining)
        return "".join(final_parts)

    async def _run_tool(self, use: ToolUseBlock) -> ToolResultBlock:
        result = await self._registry.execute(use.name, use.arguments, self._ctx)
        return ToolResultBlock(tool_use_id=use.id, content=result.to_llm(), is_error=not result.ok)

    async def _speak_sentence(self, sentence: str) -> None:
        if self._state.state is State.THINKING:
            await self._state.transition(State.SPEAKING)
        await self._bus.publish(AssistantSentence(text=sentence))
        await self._speaker.speak(sentence)

    async def _build_system(self, query: str) -> str:
        apps: list[str] = []
        try:
            from jarvis.tools.system import current_open_apps

            apps = await asyncio.to_thread(current_open_apps)
        except Exception:  # noqa: BLE001 - contexte best-effort, jamais bloquant
            apps = []
        memories = await self._memory.recall(query) if self._memory is not None else []
        home_summary = self._home.summary() if self._home is not None else None
        context = PromptContext(
            now=datetime.now().strftime("%A %d %B %Y, %H:%M"),
            user_name=self._settings.user_name,
            open_apps=apps,
            home_summary=home_summary,
            memories=memories,
        )
        return build_system_prompt(self._settings.user_name, self._settings.address_as_monsieur, context)

    def _remember_turn(self, user_text: str, assistant_text: str) -> None:
        self._history.append(Message.user_text(user_text))
        self._history.append(Message.assistant_text(assistant_text))
        limit = self._settings.history_max_turns * 2
        if len(self._history) > limit:
            self._history = self._history[-limit:]
        if self._memory is not None:
            self._spawn(self._memory.add_message("assistant", assistant_text))
            transcript = f"Utilisateur : {user_text}\nJarvis : {assistant_text}"
            self._spawn(self._memory.extract_facts(transcript))

    async def _watch_reminders(self) -> None:
        subscription = self._bus.subscribe(ReminderDue)
        async for event in subscription:
            if isinstance(event, ReminderDue):
                toast("JARVIS — Rappel", event.message)
                await self._speaker.speak(event.message)

    # --- Transitions d'état ---

    async def _enter_thinking(self) -> None:
        if self._state.state is State.IDLE:
            await self._state.transition(State.LISTENING)
        if self._state.state is State.LISTENING:
            await self._state.transition(State.THINKING)

    async def _to_idle(self) -> None:
        if self._state.state is not State.IDLE:
            await self._state.transition(State.IDLE)

    async def _fail(self, reason: str) -> str:
        _log.warning("orchestrator.failed", reason=reason)
        await self._bus.publish(ErrorOccurred(message=reason))
        await self._state.transition(State.ERROR)
        await self._speaker.speak(_ERROR_REPLY)
        await self._speaker.wait()
        await self._state.transition(State.IDLE)
        return _ERROR_REPLY

    def _spawn(self, coro: Coroutine[object, object, None]) -> None:
        task = asyncio.ensure_future(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)


def _assistant_message(text: str, tool_uses: list[ToolUseBlock]) -> Message:
    content: list[ContentBlock] = []
    if text.strip():
        content.append(TextBlock(text=text))
    content.extend(tool_uses)
    return Message(role="assistant", content=content)
