"""Notifications toast Windows (best-effort, dégradation silencieuse ailleurs)."""

from __future__ import annotations

import sys

from jarvis.logging_config import get_logger

_log = get_logger("jarvis.notify")


def toast(title: str, message: str) -> None:
    if sys.platform != "win32":
        return
    try:
        from windows_toasts import Toast, WindowsToaster

        toaster = WindowsToaster("JARVIS")
        notification = Toast()
        notification.text_fields = [title, message]
        toaster.show_toast(notification)
    except Exception as exc:  # noqa: BLE001 - la notif est un bonus, jamais bloquante
        _log.debug("notify.failed", error=str(exc))
