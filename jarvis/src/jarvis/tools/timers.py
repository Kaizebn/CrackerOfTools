"""Minuteurs et rappels.

Les minuteurs sont éphémères (en mémoire). Les rappels sont persistés en SQLite et
rechargés au démarrage, donc ils survivent à un redémarrage. Quand l'un se déclenche,
un événement ``ReminderDue`` est publié : l'orchestrateur le lit pour notifier (voix +
toast Windows).
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timezone

from pydantic import BaseModel, Field

from jarvis.events import EventBus, ReminderDue
from jarvis.logging_config import get_logger
from jarvis.memory.manager import MemoryManager
from jarvis.tools.registry import EmptyArgs, Risk, ToolContext, ToolResult, tool

_log = get_logger("jarvis.timers")


@dataclass
class _ActiveTimer:
    label: str
    task: asyncio.Task[None]
    fire_at: float


class TimerManager:
    def __init__(self, bus: EventBus, memory: MemoryManager) -> None:
        self._bus = bus
        self._memory = memory
        self._timers: dict[int, _ActiveTimer] = {}
        self._reminder_tasks: dict[int, asyncio.Task[None]] = {}
        self._seq = 0

    async def start(self) -> None:
        """Recharge les rappels persistés et les reprogramme."""
        for reminder in await self._memory.pending_reminders():
            self._schedule_reminder(reminder.id, reminder.due_at, reminder.message)

    async def shutdown(self) -> None:
        for timer in self._timers.values():
            timer.task.cancel()
        for task in self._reminder_tasks.values():
            task.cancel()

    # --- Minuteurs éphémères ---

    def set_timer(self, duration_seconds: int, label: str) -> int:
        self._seq += 1
        timer_id = self._seq
        fire_at = _monotonic() + duration_seconds
        task = asyncio.create_task(self._fire_timer(timer_id, duration_seconds, label))
        self._timers[timer_id] = _ActiveTimer(label=label, task=task, fire_at=fire_at)
        return timer_id

    async def _fire_timer(self, timer_id: int, delay: float, label: str) -> None:
        try:
            await asyncio.sleep(delay)
        except asyncio.CancelledError:
            return
        self._timers.pop(timer_id, None)
        message = f"Minuteur terminé : {label}." if label else "Minuteur terminé."
        await self._bus.publish(ReminderDue(reminder_id=-timer_id, message=message))

    # --- Rappels persistés ---

    async def set_reminder(self, due_at: datetime, message: str, label: str) -> int:
        reminder_id = await self._memory.add_reminder(due_at, message, label)
        self._schedule_reminder(reminder_id, due_at, message)
        return reminder_id

    def _schedule_reminder(self, reminder_id: int, due_at: datetime, message: str) -> None:
        delay = max(0.0, (_as_utc(due_at) - datetime.now(timezone.utc)).total_seconds())
        self._reminder_tasks[reminder_id] = asyncio.create_task(
            self._fire_reminder(reminder_id, delay, message)
        )

    async def _fire_reminder(self, reminder_id: int, delay: float, message: str) -> None:
        try:
            await asyncio.sleep(delay)
        except asyncio.CancelledError:
            return
        self._reminder_tasks.pop(reminder_id, None)
        await self._memory.mark_reminder_fired(reminder_id)
        await self._bus.publish(ReminderDue(reminder_id=reminder_id, message=message))

    async def cancel_reminder(self, reminder_id: int) -> bool:
        task = self._reminder_tasks.pop(reminder_id, None)
        if task is not None:
            task.cancel()
        return await self._memory.cancel_reminder(reminder_id)

    def cancel_timer(self, timer_id: int) -> bool:
        timer = self._timers.pop(timer_id, None)
        if timer is None:
            return False
        timer.task.cancel()
        return True

    def active_timers(self) -> list[tuple[int, str]]:
        return [(tid, t.label) for tid, t in self._timers.items()]


def _monotonic() -> float:
    return asyncio.get_event_loop().time()


def _as_utc(moment: datetime) -> datetime:
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


# --- Outils exposés au LLM ---


class SetTimerArgs(BaseModel):
    duration_seconds: int = Field(gt=0, description="Durée du minuteur en secondes.")
    label: str = Field(default="", description="Étiquette facultative du minuteur.")


class SetReminderArgs(BaseModel):
    datetime_iso: str = Field(description="Date/heure du rappel au format ISO 8601.")
    message: str = Field(description="Message du rappel.")
    label: str = Field(default="", description="Étiquette facultative.")


class CancelReminderArgs(BaseModel):
    reminder_id: int = Field(description="Identifiant du rappel à annuler.")


@tool(name="set_timer", risk=Risk.SAFE)
async def set_timer(args: SetTimerArgs, ctx: ToolContext) -> ToolResult:
    """Lance un minuteur. Se déclenche après la durée indiquée avec une notification."""
    if ctx.timers is None:
        return ToolResult.fail("Les minuteurs ne sont pas disponibles.")
    timer_id = ctx.timers.set_timer(args.duration_seconds, args.label)
    minutes = args.duration_seconds / 60
    return ToolResult.success(f"Minuteur lancé ({minutes:.0f} min).", timer_id=timer_id)


@tool(name="set_reminder", risk=Risk.SAFE)
async def set_reminder(args: SetReminderArgs, ctx: ToolContext) -> ToolResult:
    """Programme un rappel à une date/heure. Il survit au redémarrage."""
    if ctx.timers is None:
        return ToolResult.fail("Les rappels ne sont pas disponibles.")
    try:
        due = datetime.fromisoformat(args.datetime_iso)
    except ValueError:
        return ToolResult.fail("Date invalide : utilise le format ISO 8601.")
    reminder_id = await ctx.timers.set_reminder(due, args.message, args.label)
    return ToolResult.success(f"Rappel programmé pour {due:%d/%m %H:%M}.", reminder_id=reminder_id)


@tool(name="list_reminders", risk=Risk.SAFE)
async def list_reminders(args: EmptyArgs, ctx: ToolContext) -> ToolResult:
    """Liste les rappels en attente et les minuteurs actifs."""
    if ctx.timers is None or ctx.memory is None:
        return ToolResult.fail("La mémoire n'est pas disponible.")
    reminders = await ctx.memory.pending_reminders()
    timers = ctx.timers.active_timers()
    data = {
        "reminders": [{"id": r.id, "due": r.due_at.isoformat(), "message": r.message} for r in reminders],
        "timers": [{"id": tid, "label": label} for tid, label in timers],
    }
    if not reminders and not timers:
        return ToolResult.success("Aucun rappel ni minuteur.")
    return ToolResult.success(f"{len(reminders)} rappel(s), {len(timers)} minuteur(s).", **data)


@tool(name="cancel_reminder", risk=Risk.SAFE)
async def cancel_reminder(args: CancelReminderArgs, ctx: ToolContext) -> ToolResult:
    """Annule un rappel par son identifiant."""
    if ctx.timers is None:
        return ToolResult.fail("Les rappels ne sont pas disponibles.")
    ok = await ctx.timers.cancel_reminder(args.reminder_id)
    return ToolResult.success("Rappel annulé.") if ok else ToolResult.fail("Rappel introuvable.")
