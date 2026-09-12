"""Outils fichiers, strictement limités aux racines autorisées (ALLOWED_PATHS).

Toute opération hors des racines déclarées est refusée explicitement. Si aucune racine
n'est configurée, tout est refusé (par sécurité).
"""

from __future__ import annotations

import asyncio
import os
import shutil
import sys
from pathlib import Path

from pydantic import BaseModel, Field

from jarvis.tools.registry import Risk, ToolContext, ToolResult, tool

_MAX_READ = 20000
_MAX_HITS = 50


def _within_roots(path: Path, roots: list[Path]) -> bool:
    try:
        resolved = path.expanduser().resolve()
    except OSError:
        return False
    for root in roots:
        try:
            resolved.relative_to(root.resolve())
            return True
        except ValueError:
            continue
    return False


def _check(path_str: str, roots: list[Path]) -> tuple[Path | None, str]:
    if not roots:
        return None, "Aucune racine autorisée n'est configurée (JARVIS_ALLOWED_PATHS)."
    path = Path(path_str).expanduser()
    if not _within_roots(path, roots):
        return None, f"Accès refusé : {path} est hors des racines autorisées."
    return path, ""


class SearchFilesArgs(BaseModel):
    query: str = Field(description="Fragment de nom de fichier à rechercher.")
    root: str | None = Field(default=None, description="Racine où chercher (sinon toutes les racines autorisées).")


class PathArgs(BaseModel):
    path: str = Field(description="Chemin du fichier ou dossier.")


class WriteFileArgs(BaseModel):
    path: str = Field(description="Chemin du fichier à écrire.")
    content: str = Field(description="Contenu à écrire.")


class MoveArgs(BaseModel):
    source: str = Field(description="Chemin source.")
    destination: str = Field(description="Chemin destination.")


@tool(name="search_files", risk=Risk.SAFE)
async def search_files(args: SearchFilesArgs, ctx: ToolContext) -> ToolResult:
    """Cherche des fichiers par fragment de nom dans les racines autorisées."""
    roots = ctx.settings.allowed_roots
    if not roots:
        return ToolResult.fail("Aucune racine autorisée n'est configurée.")
    search_roots = roots
    if args.root is not None:
        root, error = _check(args.root, roots)
        if root is None:
            return ToolResult.fail(error)
        search_roots = [root]

    def _scan() -> list[str]:
        hits: list[str] = []
        needle = args.query.lower()
        for base in search_roots:
            for dirpath, _dirs, files in os.walk(base):
                for filename in files:
                    if needle in filename.lower():
                        hits.append(str(Path(dirpath) / filename))
                        if len(hits) >= _MAX_HITS:
                            return hits
        return hits

    results = await asyncio.to_thread(_scan)
    if not results:
        return ToolResult.success("Aucun fichier trouvé.")
    return ToolResult.success(f"{len(results)} fichier(s).", files=results)


@tool(name="read_file", risk=Risk.SAFE)
async def read_file(args: PathArgs, ctx: ToolContext) -> ToolResult:
    """Lit le contenu texte d'un fichier autorisé (tronqué si volumineux)."""
    path, error = _check(args.path, ctx.settings.allowed_roots)
    if path is None:
        return ToolResult.fail(error)
    if not path.is_file():
        return ToolResult.fail("Fichier introuvable.")

    def _read() -> str:
        return path.read_text(encoding="utf-8", errors="replace")[:_MAX_READ]

    content = await asyncio.to_thread(_read)
    return ToolResult.success(content)


@tool(
    name="write_file",
    risk=Risk.CONFIRM,
    side_effect=True,
    confirm_prompt=lambda a: f"J'écris dans le fichier {a.path} ?",
)
async def write_file(args: WriteFileArgs, ctx: ToolContext) -> ToolResult:
    """Écrit du contenu dans un fichier autorisé (demande confirmation)."""
    path, error = _check(args.path, ctx.settings.allowed_roots)
    if path is None:
        return ToolResult.fail(error)

    def _write() -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(args.content, encoding="utf-8")

    await asyncio.to_thread(_write)
    return ToolResult.success(f"Écrit dans {path.name}.")


@tool(name="move_file", risk=Risk.SAFE, side_effect=True)
async def move_file(args: MoveArgs, ctx: ToolContext) -> ToolResult:
    """Déplace un fichier autorisé vers une destination autorisée."""
    roots = ctx.settings.allowed_roots
    source, error = _check(args.source, roots)
    if source is None:
        return ToolResult.fail(error)
    destination, error = _check(args.destination, roots)
    if destination is None:
        return ToolResult.fail(error)
    await asyncio.to_thread(shutil.move, str(source), str(destination))
    return ToolResult.success(f"Déplacé vers {destination}.")


@tool(name="copy_file", risk=Risk.SAFE, side_effect=True)
async def copy_file(args: MoveArgs, ctx: ToolContext) -> ToolResult:
    """Copie un fichier autorisé vers une destination autorisée."""
    roots = ctx.settings.allowed_roots
    source, error = _check(args.source, roots)
    if source is None:
        return ToolResult.fail(error)
    destination, error = _check(args.destination, roots)
    if destination is None:
        return ToolResult.fail(error)
    await asyncio.to_thread(shutil.copy2, str(source), str(destination))
    return ToolResult.success(f"Copié vers {destination}.")


@tool(
    name="delete_file",
    risk=Risk.CONFIRM,
    side_effect=True,
    confirm_prompt=lambda a: f"Je supprime définitivement {a.path} ?",
)
async def delete_file(args: PathArgs, ctx: ToolContext) -> ToolResult:
    """Supprime un fichier autorisé (demande confirmation)."""
    path, error = _check(args.path, ctx.settings.allowed_roots)
    if path is None:
        return ToolResult.fail(error)
    if not path.is_file():
        return ToolResult.fail("Fichier introuvable.")
    await asyncio.to_thread(path.unlink)
    return ToolResult.success(f"{path.name} supprimé.")


@tool(name="open_in_explorer", risk=Risk.SAFE, side_effect=True)
async def open_in_explorer(args: PathArgs, ctx: ToolContext) -> ToolResult:
    """Ouvre un fichier ou dossier autorisé dans l'explorateur Windows."""
    path, error = _check(args.path, ctx.settings.allowed_roots)
    if path is None:
        return ToolResult.fail(error)
    if sys.platform != "win32":
        return ToolResult.fail("Explorateur disponible uniquement sous Windows.")
    await asyncio.to_thread(os.startfile, str(path))
    return ToolResult.success(f"{path.name} ouvert dans l'explorateur.")
