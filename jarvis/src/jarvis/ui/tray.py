"""Icône de barre système : état courant + menu (pause, historique, quitter).

L'icône est dessinée au runtime (pas de fichier requis). Les actions sont exposées en
callbacks pour que l'application les câble sans que l'UI connaisse la logique métier.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from PySide6 import QtGui, QtWidgets

from jarvis.state import State

_DOT: dict[State, tuple[int, int, int]] = {
    State.IDLE: (80, 120, 150),
    State.LISTENING: (0, 200, 255),
    State.THINKING: (120, 160, 255),
    State.SPEAKING: (0, 230, 255),
    State.ERROR: (255, 70, 70),
}


def _icon(state: State) -> QtGui.QIcon:
    pixmap = QtGui.QPixmap(32, 32)
    pixmap.fill(QtGui.QColor(0, 0, 0, 0))
    painter = QtGui.QPainter(pixmap)
    painter.setRenderHint(QtGui.QPainter.RenderHint.Antialiasing)
    painter.setBrush(QtGui.QColor(*_DOT.get(state, _DOT[State.IDLE])))
    painter.setPen(QtGui.QColor(20, 30, 40))
    painter.drawEllipse(4, 4, 24, 24)
    painter.end()
    return QtGui.QIcon(pixmap)


class TrayIcon:
    def __init__(
        self,
        on_toggle_pause: Callable[[], None],
        on_quit: Callable[[], None],
        on_open_logs: Callable[[], None],
    ) -> None:
        self._tray: Any = QtWidgets.QSystemTrayIcon(_icon(State.IDLE))
        self._tray.setToolTip("JARVIS")
        menu = QtWidgets.QMenu()
        self._pause_action = menu.addAction("Pause")
        self._pause_action.triggered.connect(lambda: on_toggle_pause())
        logs_action = menu.addAction("Ouvrir l'historique")
        logs_action.triggered.connect(lambda: on_open_logs())
        menu.addSeparator()
        quit_action = menu.addAction("Quitter")
        quit_action.triggered.connect(lambda: on_quit())
        self._tray.setContextMenu(menu)
        self._tray.show()

    def set_state(self, state: State) -> None:
        self._tray.setIcon(_icon(state))
        self._tray.setToolTip(f"JARVIS — {state.value}")

    def set_paused(self, paused: bool) -> None:
        self._pause_action.setText("Reprendre" if paused else "Pause")
