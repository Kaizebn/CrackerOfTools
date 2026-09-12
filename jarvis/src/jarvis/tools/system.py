"""Outils système Windows : apps, volume, luminosité, média, capture, énergie, commandes.

Les API propres à Windows sont isolées derrière des gardes ``sys.platform == "win32"``
(et importées paresseusement) : le module reste importable et typé sur tout OS, et les
outils renvoient un message clair plutôt que de planter là où ils ne s'appliquent pas.
"""

from __future__ import annotations

import asyncio
import difflib
import os
import shlex
import subprocess
import sys
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from typing import Any, Literal, TypeVar

from pydantic import BaseModel, Field

from jarvis.tools.registry import EmptyArgs, Risk, ToolContext, ToolResult, tool

_T = TypeVar("_T")
_WINDOWS = sys.platform == "win32"


async def _run_com(func: Callable[[], _T]) -> _T:
    # pycaw passe par COM : il faut initialiser COM dans le thread qui l'utilise.
    def wrapper() -> _T:
        if _WINDOWS:
            import comtypes

            comtypes.CoInitialize()
            try:
                return func()
            finally:
                comtypes.CoUninitialize()
        return func()

    return await asyncio.to_thread(wrapper)


def _start_menu_dirs() -> list[Path]:
    dirs: list[Path] = []
    for var in ("APPDATA", "PROGRAMDATA"):
        base = os.environ.get(var)
        if base:
            dirs.append(Path(base) / "Microsoft" / "Windows" / "Start Menu" / "Programs")
    return [d for d in dirs if d.exists()]


def _resolve_app(name: str) -> Path | None:
    """Résout un nom d'app flou vers un raccourci .lnk du menu Démarrer."""
    shortcuts: dict[str, Path] = {}
    for directory in _start_menu_dirs():
        for lnk in directory.rglob("*.lnk"):
            shortcuts[lnk.stem.lower()] = lnk
    if not shortcuts:
        return None
    target = name.lower()
    if target in shortcuts:
        return shortcuts[target]
    matches = difflib.get_close_matches(target, list(shortcuts), n=1, cutoff=0.5)
    if matches:
        return shortcuts[matches[0]]
    partial = [key for key in shortcuts if target in key]
    return shortcuts[partial[0]] if partial else None


def current_open_apps() -> list[str]:
    """Noms de processus utilisateur en cours (best-effort, pour le contexte du LLM)."""
    try:
        import psutil
    except ImportError:
        return []
    names: set[str] = set()
    for process in psutil.process_iter(["name"]):
        name = process.info.get("name")
        if name:
            names.add(str(name))
    return sorted(names)


# --- Modèles d'arguments ---


class AppArgs(BaseModel):
    name: str = Field(description="Nom de l'application.")


class VolumeArgs(BaseModel):
    percent: int = Field(ge=0, le=100, description="Niveau de volume en pourcentage.")


class BrightnessArgs(BaseModel):
    percent: int = Field(ge=0, le=100, description="Luminosité en pourcentage.")


class MediaArgs(BaseModel):
    action: Literal["play_pause", "next", "prev"] = Field(description="Action média.")


class PowerArgs(BaseModel):
    action: Literal["shutdown", "restart"] = Field(description="Arrêt ou redémarrage.")


class RunCommandArgs(BaseModel):
    command: str = Field(description="Commande à exécuter (binaire autorisé uniquement).")


# --- Outils ---


@tool(name="open_app", risk=Risk.SAFE, side_effect=True)
async def open_app(args: AppArgs, ctx: ToolContext) -> ToolResult:
    """Ouvre une application par son nom (résolution floue via le menu Démarrer)."""
    if not _WINDOWS:
        return ToolResult.fail("Ouverture d'application disponible uniquement sous Windows.")
    shortcut = await asyncio.to_thread(_resolve_app, args.name)
    if shortcut is None:
        return ToolResult.fail(f"Application introuvable : {args.name}.")
    if sys.platform == "win32":
        await asyncio.to_thread(os.startfile, str(shortcut))
    return ToolResult.success(f"{shortcut.stem} ouvert.")


@tool(name="close_app", risk=Risk.SAFE, side_effect=True)
async def close_app(args: AppArgs, ctx: ToolContext) -> ToolResult:
    """Ferme les processus dont le nom correspond à l'application indiquée."""
    try:
        import psutil
    except ImportError:
        return ToolResult.fail("psutil n'est pas disponible.")

    def _kill() -> int:
        killed = 0
        target = args.name.lower()
        for process in psutil.process_iter(["name"]):
            name = (process.info.get("name") or "").lower()
            if target in name:
                process.terminate()
                killed += 1
        return killed

    count = await asyncio.to_thread(_kill)
    return ToolResult.success(f"{count} processus fermé(s).") if count else ToolResult.fail("Aucun processus correspondant.")


@tool(name="list_running_apps", risk=Risk.SAFE)
async def list_running_apps(args: EmptyArgs, ctx: ToolContext) -> ToolResult:
    """Liste les applications/processus en cours d'exécution."""
    apps = await asyncio.to_thread(current_open_apps)
    if not apps:
        return ToolResult.fail("Liste des processus indisponible.")
    return ToolResult.success(f"{len(apps)} processus.", apps=apps[:50])


@tool(name="set_volume", risk=Risk.SAFE, side_effect=True)
async def set_volume(args: VolumeArgs, ctx: ToolContext) -> ToolResult:
    """Règle le volume principal du système en pourcentage."""
    if not _WINDOWS:
        return ToolResult.fail("Contrôle du volume disponible uniquement sous Windows.")

    def _set() -> None:
        from ctypes import POINTER, cast

        from comtypes import CLSCTX_ALL
        from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume

        speakers = AudioUtilities.GetSpeakers()
        interface = speakers.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        volume: Any = cast(interface, POINTER(IAudioEndpointVolume))
        volume.SetMasterVolumeLevelScalar(args.percent / 100, None)

    await _run_com(_set)
    return ToolResult.success(f"Volume à {args.percent}%.")


class MuteArgs(BaseModel):
    muted: bool = Field(description="True pour couper le son, False pour le rétablir.")


@tool(name="set_mute", risk=Risk.SAFE, side_effect=True)
async def set_mute(args: MuteArgs, ctx: ToolContext) -> ToolResult:
    """Coupe ou rétablit le son du système."""
    if not _WINDOWS:
        return ToolResult.fail("Contrôle du son disponible uniquement sous Windows.")

    def _apply() -> None:
        from ctypes import POINTER, cast

        from comtypes import CLSCTX_ALL
        from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume

        speakers = AudioUtilities.GetSpeakers()
        interface = speakers.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        volume: Any = cast(interface, POINTER(IAudioEndpointVolume))
        volume.SetMute(1 if args.muted else 0, None)

    await _run_com(_apply)
    return ToolResult.success("Son coupé." if args.muted else "Son rétabli.")


@tool(name="set_brightness", risk=Risk.SAFE, side_effect=True)
async def set_brightness(args: BrightnessArgs, ctx: ToolContext) -> ToolResult:
    """Règle la luminosité de l'écran en pourcentage."""
    try:
        import screen_brightness_control as sbc
    except ImportError:
        return ToolResult.fail("screen-brightness-control n'est pas disponible.")
    try:
        await asyncio.to_thread(sbc.set_brightness, args.percent)
    except Exception as exc:  # noqa: BLE001 - matériel variable (DDC indisponible)
        return ToolResult.fail(f"Luminosité non réglable ici : {exc}")
    return ToolResult.success(f"Luminosité à {args.percent}%.")


@tool(name="take_screenshot", risk=Risk.SAFE, side_effect=True)
async def take_screenshot(args: EmptyArgs, ctx: ToolContext) -> ToolResult:
    """Capture l'écran et renvoie le chemin du fichier image."""
    try:
        import pyautogui
    except ImportError:
        return ToolResult.fail("pyautogui n'est pas disponible.")
    folder = ctx.settings.data_dir / "screenshots"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"screenshot_{datetime.now():%Y%m%d_%H%M%S}.png"

    def _capture() -> None:
        image = pyautogui.screenshot()
        image.save(str(path))

    await asyncio.to_thread(_capture)
    return ToolResult.success(f"Capture enregistrée : {path}", path=str(path))


@tool(name="media_control", risk=Risk.SAFE, side_effect=True)
async def media_control(args: MediaArgs, ctx: ToolContext) -> ToolResult:
    """Contrôle la lecture média : lecture/pause, piste suivante ou précédente."""
    try:
        import pyautogui
    except ImportError:
        return ToolResult.fail("pyautogui n'est pas disponible.")
    keys = {"play_pause": "playpause", "next": "nexttrack", "prev": "prevtrack"}
    await asyncio.to_thread(pyautogui.press, keys[args.action])
    return ToolResult.success("Voilà.")


@tool(name="lock_screen", risk=Risk.SAFE, side_effect=True)
async def lock_screen(args: EmptyArgs, ctx: ToolContext) -> ToolResult:
    """Verrouille la session Windows."""
    if sys.platform != "win32":
        return ToolResult.fail("Verrouillage disponible uniquement sous Windows.")
    import ctypes

    ctypes.windll.user32.LockWorkStation()
    return ToolResult.success("Session verrouillée.")


@tool(
    name="power",
    risk=Risk.CONFIRM,
    side_effect=True,
    confirm_prompt=lambda a: f"Tu confirmes le {'redémarrage' if a.action == 'restart' else 'arrêt'} du PC ?",
)
async def power(args: PowerArgs, ctx: ToolContext) -> ToolResult:
    """Arrête ou redémarre l'ordinateur (demande confirmation)."""
    if sys.platform != "win32":
        return ToolResult.fail("Arrêt/redémarrage disponible uniquement sous Windows.")
    flag = "/r" if args.action == "restart" else "/s"
    await asyncio.to_thread(subprocess.run, ["shutdown", flag, "/t", "0"], check=False)
    return ToolResult.success("Redémarrage en cours." if args.action == "restart" else "Arrêt en cours.")


@tool(name="sleep_pc", risk=Risk.CONFIRM, side_effect=True, confirm_prompt=lambda a: "Je mets le PC en veille ?")
async def sleep_pc(args: EmptyArgs, ctx: ToolContext) -> ToolResult:
    """Met l'ordinateur en veille (demande confirmation)."""
    if sys.platform != "win32":
        return ToolResult.fail("Mise en veille disponible uniquement sous Windows.")
    await asyncio.to_thread(
        subprocess.run, ["rundll32.exe", "powrprof.dll,SetSuspendState", "0", "1", "0"], check=False
    )
    return ToolResult.success("Mise en veille.")


@tool(
    name="run_command",
    risk=Risk.CONFIRM,
    side_effect=True,
    confirm_prompt=lambda a: f"J'exécute la commande « {a.command} » ?",
)
async def run_command(args: RunCommandArgs, ctx: ToolContext) -> ToolResult:
    """Exécute une commande dont le binaire figure dans l'allowlist de configuration."""
    try:
        parts = shlex.split(args.command, posix=not _WINDOWS)
    except ValueError as exc:
        return ToolResult.fail(f"Commande mal formée : {exc}")
    if not parts:
        return ToolResult.fail("Commande vide.")
    binary = Path(parts[0]).stem.lower()
    allowed = {c.lower() for c in ctx.settings.allowed_commands}
    if binary not in allowed:
        return ToolResult.fail(f"Binaire « {binary} » non autorisé. Autorisés : {sorted(allowed)}.")

    def _run() -> subprocess.CompletedProcess[str]:
        # Jamais shell=True : on passe une liste d'arguments, pas une chaîne.
        return subprocess.run(parts, capture_output=True, text=True, timeout=30, check=False)

    completed = await asyncio.to_thread(_run)
    output = (completed.stdout or completed.stderr or "").strip()[:2000]
    return ToolResult.success(output or "Commande exécutée.", return_code=completed.returncode)
