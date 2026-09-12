"""Outils de mémoire : remember / recall / forget."""

from __future__ import annotations

from pydantic import BaseModel, Field

from jarvis.tools.registry import Risk, ToolContext, ToolResult, tool


class RememberArgs(BaseModel):
    fact: str = Field(description="Le fait durable à mémoriser.")
    category: str = Field(default="general", description="Catégorie (préférence, santé, projet…).")


class RecallArgs(BaseModel):
    query: str = Field(description="Ce qu'on cherche à retrouver.")


class ForgetArgs(BaseModel):
    fact_id: int = Field(description="Identifiant du fait à oublier.")


@tool(name="remember", risk=Risk.SAFE)
async def remember(args: RememberArgs, ctx: ToolContext) -> ToolResult:
    """Mémorise un fait durable sur l'utilisateur pour s'en souvenir plus tard."""
    if ctx.memory is None:
        return ToolResult.fail("La mémoire n'est pas disponible.")
    fact_id = await ctx.memory.remember(args.fact, args.category)
    return ToolResult.success("C'est noté.", fact_id=fact_id)


@tool(name="recall", risk=Risk.SAFE)
async def recall(args: RecallArgs, ctx: ToolContext) -> ToolResult:
    """Retrouve des faits mémorisés par similarité avec la requête."""
    if ctx.memory is None:
        return ToolResult.fail("La mémoire n'est pas disponible.")
    memories = await ctx.memory.recall(args.query)
    if not memories:
        return ToolResult.success("Aucun souvenir correspondant.")
    return ToolResult.success("Souvenirs trouvés.", memories=memories)


@tool(name="forget", risk=Risk.CONFIRM, confirm_prompt=lambda a: f"J'oublie définitivement le fait {a.fact_id} ?")
async def forget(args: ForgetArgs, ctx: ToolContext) -> ToolResult:
    """Oublie un fait mémorisé par son identifiant."""
    if ctx.memory is None:
        return ToolResult.fail("La mémoire n'est pas disponible.")
    ok = await ctx.memory.forget(args.fact_id)
    return ToolResult.success("Oublié.") if ok else ToolResult.fail("Fait introuvable.")
