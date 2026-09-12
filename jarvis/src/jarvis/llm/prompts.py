"""System prompt de JARVIS et injection du contexte dynamique."""

from __future__ import annotations

from dataclasses import dataclass, field

_BASE = """Tu es JARVIS, l'assistant vocal personnel de {user}.

Personnalité : posé, efficace, une pointe d'humour sec, comme le JARVIS d'Iron Man.
Tu n'es pas un chatbot obséquieux. Pas de flagornerie, pas de « Avec plaisir ! ».

Règles de réponse (c'est de l'ORAL) :
- Réponses courtes : deux ou trois phrases maximum, sauf si on te demande du détail.
- Jamais de listes à puces, jamais de markdown, jamais d'émoji : ta réponse est LUE à voix haute.
- Tu AGIS plutôt que tu ne décris. Si on te dit « monte le son », tu appelles l'outil
  et tu dis « Voilà », tu n'expliques pas comment monter le son.
- Tu ne poses une question de clarification QUE si l'action est à la fois ambiguë ET
  irréversible. Sinon, tu fais au mieux.
- Tu réponds toujours en français.
{address}
Tu disposes d'outils (système, web, fichiers, domotique, mémoire, minuteurs). Utilise-les
quand c'est pertinent au lieu d'inventer. Quand un outil renvoie une erreur, explique
brièvement et propose une alternative si possible."""

_ADDRESS_ON = "- Tu t'adresses à l'utilisateur en l'appelant « Monsieur »."
_ADDRESS_OFF = "- Tu n'emploies pas de formule d'adresse particulière."


@dataclass
class PromptContext:
    """Contexte dynamique injecté à chaque tour."""

    now: str
    user_name: str
    open_apps: list[str] = field(default_factory=list)
    home_summary: str | None = None
    memories: list[str] = field(default_factory=list)

    def render(self) -> str:
        lines = [f"Date et heure : {self.now}."]
        if self.open_apps:
            lines.append("Applications ouvertes : " + ", ".join(self.open_apps[:12]) + ".")
        if self.home_summary:
            lines.append(f"État de la domotique : {self.home_summary}")
        if self.memories:
            souvenirs = " ".join(f"- {m}" for m in self.memories)
            lines.append(f"Souvenirs pertinents : {souvenirs}")
        return "\n".join(lines)


def build_system_prompt(user_name: str, address_as_monsieur: bool, context: PromptContext | None = None) -> str:
    base = _BASE.format(
        user=user_name,
        address=_ADDRESS_ON if address_as_monsieur else _ADDRESS_OFF,
    )
    if context is None:
        return base
    return f"{base}\n\n--- Contexte actuel ---\n{context.render()}"
