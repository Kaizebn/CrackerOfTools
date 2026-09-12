"""Overlay HUD : anneau « arc-réacteur » animé qui réagit à l'état et au micro.

Rendu maison au QPainter (pas de WebView), rafraîchi ~60 fps. Fenêtre sans bordure,
translucide, toujours au-dessus, clic-traversant au repos, centrée en bas de l'écran.
"""

from __future__ import annotations

import math
from typing import Any

from PySide6 import QtCore, QtGui, QtWidgets

from jarvis.state import State

_COLORS: dict[State, QtGui.QColor] = {
    State.IDLE: QtGui.QColor(80, 120, 150),
    State.LISTENING: QtGui.QColor(0, 200, 255),
    State.THINKING: QtGui.QColor(120, 160, 255),
    State.SPEAKING: QtGui.QColor(0, 230, 255),
    State.ERROR: QtGui.QColor(255, 70, 70),
}
_SIZE = 220


class HUDWindow(QtWidgets.QWidget):  # type: ignore[misc]
    def __init__(self) -> None:
        super().__init__(None)
        self.setWindowFlags(
            QtCore.Qt.WindowType.FramelessWindowHint
            | QtCore.Qt.WindowType.WindowStaysOnTopHint
            | QtCore.Qt.WindowType.Tool
        )
        self.setAttribute(QtCore.Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(QtCore.Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        self.resize(_SIZE, _SIZE + 60)

        self._state = State.IDLE
        self._amplitude = 0.0
        self._phase = 0.0
        self._transcript = ""
        self._badges: list[str] = []

        self._timer = QtCore.QTimer(self)
        self._timer.timeout.connect(self._tick)
        self._timer.start(16)  # ~60 fps
        self._place_bottom_center()

    def _place_bottom_center(self) -> None:
        screen = QtWidgets.QApplication.primaryScreen()
        if screen is None:
            return
        geo = screen.availableGeometry()
        self.move(geo.center().x() - self.width() // 2, geo.bottom() - self.height() - 40)

    # --- API pilotée par l'EventBus ---

    def set_state(self, state: State) -> None:
        self._state = state
        if state is State.IDLE:
            self._transcript = ""
            self._badges = []
        self.update()

    def set_amplitude(self, level: float) -> None:
        self._amplitude = max(0.0, min(1.0, level))

    def set_transcript(self, text: str) -> None:
        self._transcript = text
        self.update()

    def add_badge(self, text: str) -> None:
        self._badges.append(text)
        self._badges = self._badges[-4:]
        self.update()

    def _tick(self) -> None:
        self._phase += 0.05
        self._amplitude *= 0.92  # retombée douce entre deux frames micro
        if self._state in (State.LISTENING, State.THINKING, State.SPEAKING):
            self.update()

    # --- Rendu ---

    def paintEvent(self, event: Any) -> None:
        painter = QtGui.QPainter(self)
        painter.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)
        color = _COLORS.get(self._state, _COLORS[State.IDLE])
        center = QtCore.QPointF(self.width() / 2, _SIZE / 2)
        base_radius = _SIZE * 0.32

        self._draw_glow(painter, center, base_radius, color)
        self._draw_ring(painter, center, base_radius, color)
        if self._state is State.THINKING:
            self._draw_particles(painter, center, base_radius, color)
        self._draw_text(painter, color)
        painter.end()

    def _draw_glow(self, painter: Any, center: Any, radius: float, color: Any) -> None:
        amp = radius * (1.0 + 0.25 * self._amplitude + 0.05 * math.sin(self._phase * 2))
        gradient = QtGui.QRadialGradient(center, amp * 1.6)
        glow = QtGui.QColor(color)
        glow.setAlpha(90)
        gradient.setColorAt(0.0, glow)
        transparent = QtGui.QColor(color)
        transparent.setAlpha(0)
        gradient.setColorAt(1.0, transparent)
        painter.setBrush(QtGui.QBrush(gradient))
        painter.setPen(QtCore.Qt.PenStyle.NoPen)
        painter.drawEllipse(center, amp * 1.6, amp * 1.6)

    def _draw_ring(self, painter: Any, center: Any, radius: float, color: Any) -> None:
        amp = radius * (1.0 + 0.22 * self._amplitude)
        pen = QtGui.QPen(color, 5)
        painter.setPen(pen)
        painter.setBrush(QtCore.Qt.BrushStyle.NoBrush)
        painter.drawEllipse(center, amp, amp)
        inner = QtGui.QColor(color)
        inner.setAlpha(150)
        painter.setPen(QtGui.QPen(inner, 2))
        painter.drawEllipse(center, amp * 0.7, amp * 0.7)

    def _draw_particles(self, painter: Any, center: Any, radius: float, color: Any) -> None:
        painter.setBrush(QtGui.QBrush(color))
        painter.setPen(QtCore.Qt.PenStyle.NoPen)
        for i in range(8):
            angle = self._phase + i * math.pi / 4
            x = center.x() + math.cos(angle) * radius * 1.3
            y = center.y() + math.sin(angle) * radius * 1.3
            painter.drawEllipse(QtCore.QPointF(x, y), 3, 3)

    def _draw_text(self, painter: Any, color: Any) -> None:
        painter.setPen(QtGui.QColor(230, 240, 255))
        font = painter.font()
        font.setPointSize(9)
        painter.setFont(font)
        rect = QtCore.QRectF(0, _SIZE - 10, self.width(), 40)
        text = self._transcript[:120]
        if self._badges:
            text = (text + "   " + "  ".join(self._badges)).strip()
        painter.drawText(rect, int(QtCore.Qt.AlignmentFlag.AlignHCenter), text)
