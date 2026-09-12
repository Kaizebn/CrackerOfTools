"""Pont EventBus → UI : traduit les événements en mises à jour du HUD et du tray.

L'UI ne connaît que le bus. Avec qasync, la boucle asyncio est la boucle Qt : on peut
donc toucher les widgets directement depuis ces coroutines (même thread).
"""

from __future__ import annotations

from jarvis.events import (
    AssistantSentence,
    EventBus,
    MicAmplitude,
    StateChanged,
    ToolCalled,
)
from jarvis.ui.hud import HUDWindow
from jarvis.ui.tray import TrayIcon

_BADGES: dict[str, str] = {
    "search_web": "🔍 web",
    "get_weather": "🌤️ météo",
    "get_news": "📰 actus",
    "fetch_page": "🔍 page",
    "set_volume": "🔊 volume",
    "set_mute": "🔇 son",
    "set_brightness": "💡 écran",
    "open_app": "🚀 app",
    "take_screenshot": "📸 capture",
    "turn_on": "💡 on",
    "turn_off": "💡 off",
    "set_light_brightness": "💡 lumière",
    "set_temperature": "🌡️ temp",
    "remember": "🧠 mémoire",
    "recall": "🧠 souvenir",
    "set_timer": "⏲️ minuteur",
    "set_reminder": "⏰ rappel",
}


async def run_ui_bridge(bus: EventBus, hud: HUDWindow, tray: TrayIcon) -> None:
    subscription = bus.subscribe(StateChanged, MicAmplitude, AssistantSentence, ToolCalled)
    async for event in subscription:
        if isinstance(event, StateChanged):
            hud.set_state(event.new)
            tray.set_state(event.new)
        elif isinstance(event, MicAmplitude):
            hud.set_amplitude(event.level)
        elif isinstance(event, AssistantSentence):
            hud.set_transcript(event.text)
        elif isinstance(event, ToolCalled):
            hud.add_badge(_BADGES.get(event.name, f"⚙️ {event.name}"))
