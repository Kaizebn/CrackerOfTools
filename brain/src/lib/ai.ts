import Anthropic from '@anthropic-ai/sdk';
import type { Settings, Positioning, Item, Pillar, ContentFormat } from '../db/types';
import { HOOK_TYPES } from '../db/types';
import { published, detectPatterns } from './analysis';

// ---------------------------------------------------------------------------
// Assistant IA — appelle Claude directement depuis le navigateur avec la clé
// de l'utilisateur (stockée localement). Aucune donnée ne transite par un
// serveur tiers : l'appel va directement à l'API Anthropic.
// ---------------------------------------------------------------------------

export const AI_MODELS = [
  { id: 'claude-haiku-4-5', label: 'Haiku 4.5 — le moins cher (recommandé pour débuter)', price: '≈ 1$/1M tokens' },
  { id: 'claude-sonnet-5', label: 'Sonnet 5 — équilibré', price: '≈ 2$/1M tokens' },
  { id: 'claude-opus-5', label: 'Opus 5 — le plus intelligent', price: '≈ 5$/1M tokens' },
];

export function aiConfigured(settings: Settings): boolean {
  return Boolean(settings.aiApiKey && settings.aiApiKey.trim());
}

export class AIError extends Error {}

function friendly(err: unknown): AIError {
  const status = (err as { status?: number })?.status;
  if (status === 401) return new AIError('Clé API invalide. Vérifie-la dans les Réglages.');
  if (status === 429) return new AIError('Trop de requêtes ou quota atteint. Réessaie dans un instant.');
  if (status === 400) return new AIError('Requête refusée par l\'API. Réessaie ou change de modèle.');
  if (status && status >= 500) return new AIError('Serveur Anthropic indisponible. Réessaie plus tard.');
  const name = (err as Error)?.name || '';
  const msg = (err as Error)?.message || '';
  if (name === 'APIConnectionError' || /connection|connect|network|fetch|failed|timeout|cors/i.test(msg)) {
    return new AIError('Connexion à l\'IA impossible. Vérifie ta connexion internet (et que ta clé est valide).');
  }
  return new AIError(msg || 'Erreur inconnue de l\'assistant IA.');
}

// Low-level call. Returns the concatenated text of the response.
async function complete(
  settings: Settings,
  system: string,
  user: string,
  maxTokens = 4000,
): Promise<string> {
  if (!aiConfigured(settings)) {
    throw new AIError('Assistant IA non configuré. Ajoute ta clé API dans les Réglages.');
  }
  const client = new Anthropic({
    apiKey: settings.aiApiKey.trim(),
    dangerouslyAllowBrowser: true, // app locale mono-utilisateur : la clé reste sur l'appareil
  });
  try {
    const resp = await client.messages.create({
      model: settings.aiModel || 'claude-opus-5',
      max_tokens: maxTokens,
      system,
      messages: [{ role: 'user', content: user }],
    });
    return resp.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('\n')
      .trim();
  } catch (err) {
    throw friendly(err);
  }
}

// Extract the first JSON value (array or object) from a model reply.
function extractJSON<T>(text: string): T {
  let t = text.trim();
  // strip ``` fences
  t = t.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
  try {
    return JSON.parse(t) as T;
  } catch {
    const m = t.match(/\[[\s\S]*\]|\{[\s\S]*\}/);
    if (m) {
      try { return JSON.parse(m[0]) as T; } catch { /* fall through */ }
    }
    throw new AIError('Réponse de l\'IA illisible. Réessaie.');
  }
}

function positioningContext(p: Positioning, pillars: Pillar[]): string {
  const pl = pillars.map((x) => x.name).filter(Boolean).join(', ') || '(aucun)';
  return [
    `Niche : ${p.niche || '?'}`,
    p.subNiche ? `Sous-niche : ${p.subNiche}` : '',
    `Audience cible : ${p.audience || '?'}`,
    `Promesse : ${p.promise || '?'}`,
    `Ton : ${p.tone || '?'}`,
    `Format dominant : ${p.dominantFormat}`,
    p.avatarProblem ? `Problème du spectateur : ${p.avatarProblem}` : '',
    `Piliers de contenu : ${pl}`,
  ].filter(Boolean).join('\n');
}

const SYSTEM_JSON =
  'Tu es un stratège expert du contenu court et long pour YouTube et TikTok, ' +
  'spécialisé dans la croissance de chaînes qui partent de zéro. ' +
  'Tu écris en français, de façon concrète et actionnable. ' +
  'IMPORTANT : tu réponds UNIQUEMENT avec du JSON valide, sans aucun texte autour, ' +
  'sans commentaire et sans balises de code.';

// ---------------------------------------------------------------------------
// 1. Générer des idées
// ---------------------------------------------------------------------------
export interface AIIdea {
  title: string;
  angle: string;
  format: ContentFormat;
  pillar: string;
  whyItWorks: string;
  potential: number;
}

export async function aiGenerateIdeas(
  settings: Settings, positioning: Positioning, pillars: Pillar[],
  existingTitles: string[], count = 8,
): Promise<AIIdea[]> {
  const user = [
    positioningContext(positioning, pillars),
    '',
    existingTitles.length
      ? `Idées déjà en réserve (à NE PAS répéter) :\n- ${existingTitles.slice(0, 40).join('\n- ')}`
      : '',
    '',
    `Génère ${count} nouvelles idées de vidéos originales et cliquables pour cette chaîne.`,
    'Réponds avec un tableau JSON. Chaque élément a exactement ces clés :',
    '"title" (accrocheur, < 70 caractères), "angle" (l\'approche en une phrase), ' +
    '"format" ("short" ou "long"), "pillar" (le nom EXACT d\'un des piliers ci-dessus, ou ""), ' +
    '"whyItWorks" (pourquoi les gens regarderaient jusqu\'au bout, 1 phrase), ' +
    '"potential" (entier 1 à 5).',
  ].filter((x) => x !== undefined).join('\n');

  const raw = await complete(settings, SYSTEM_JSON, user, 4000);
  const arr = extractJSON<AIIdea[]>(raw);
  return (Array.isArray(arr) ? arr : []).map((i) => ({
    title: String(i.title || '').slice(0, 200),
    angle: String(i.angle || ''),
    format: i.format === 'long' ? 'long' : 'short',
    pillar: String(i.pillar || ''),
    whyItWorks: String(i.whyItWorks || ''),
    potential: Math.max(1, Math.min(5, Math.round(Number(i.potential) || 3))),
  }));
}

// ---------------------------------------------------------------------------
// 2. Écrire un brouillon de script
// ---------------------------------------------------------------------------
export interface AIScriptShort { hook: string; development: string; punchline: string; cta: string; }
export interface AIScriptLong { hook: string; promise: string; chapters: string; retention: string; cta: string; }

export async function aiGenerateScript(
  settings: Settings, item: Item, positioning: Positioning, pillars: Pillar[],
): Promise<AIScriptShort | AIScriptLong> {
  const isShort = item.format === 'short';
  const structure = isShort
    ? '"hook" (accroche 0-3s qui empêche de scroller), "development" (le cœur, sans temps mort), ' +
      '"punchline" (la chute qui marque), "cta" (appel à l\'action).'
    : '"hook" (accroche 0-3s), "promise" (ce que le spectateur va apprendre/obtenir), ' +
      '"chapters" (le corps en chapitres, sous forme de liste avec des retours à la ligne), ' +
      '"retention" (relances / boucles ouvertes pour garder l\'attention), "cta" (appel à l\'action).';

  const user = [
    positioningContext(positioning, pillars),
    '',
    `Vidéo : "${item.title}"`,
    item.angle ? `Angle : ${item.angle}` : '',
    `Format : ${isShort ? 'Short (vertical, court)' : 'Long (horizontal)'}`,
    '',
    'Écris un brouillon de script complet et parlé (prêt à être dit face caméra).',
    'Réponds avec un objet JSON ayant exactement ces clés :',
    structure,
  ].filter(Boolean).join('\n');

  const raw = await complete(settings, SYSTEM_JSON, user, 6000);
  return extractJSON<AIScriptShort | AIScriptLong>(raw);
}

// ---------------------------------------------------------------------------
// 3. Titres, hooks, hashtags
// ---------------------------------------------------------------------------
export async function aiGenerateTitles(
  settings: Settings, item: Item, positioning: Positioning, pillars: Pillar[],
): Promise<string[]> {
  const user = [
    positioningContext(positioning, pillars),
    '',
    `Sujet de la vidéo : "${item.title}"${item.angle ? ` (angle : ${item.angle})` : ''}`,
    'Propose 6 titres alternatifs très cliquables mais honnêtes (pas de clickbait mensonger).',
    'Réponds avec un tableau JSON de 6 chaînes de caractères.',
  ].filter(Boolean).join('\n');
  const raw = await complete(settings, SYSTEM_JSON, user, 1500);
  const arr = extractJSON<string[]>(raw);
  return Array.isArray(arr) ? arr.map(String) : [];
}

export interface AIHook { type: string; text: string; }
export async function aiGenerateHooks(
  settings: Settings, item: Item, positioning: Positioning, pillars: Pillar[],
): Promise<AIHook[]> {
  const user = [
    positioningContext(positioning, pillars),
    '',
    `Sujet : "${item.title}"${item.angle ? ` (angle : ${item.angle})` : ''}`,
    `Propose 5 hooks (accroches des 3 premières secondes), un de chaque type parmi : ${HOOK_TYPES.join(', ')}.`,
    'Réponds avec un tableau JSON. Chaque élément a les clés "type" (un des types ci-dessus) et "text".',
  ].filter(Boolean).join('\n');
  const raw = await complete(settings, SYSTEM_JSON, user, 1500);
  const arr = extractJSON<AIHook[]>(raw);
  return Array.isArray(arr) ? arr.map((h) => ({ type: String(h.type || ''), text: String(h.text || '') })) : [];
}

export interface AIPublishMeta { description: string; hashtags: string; }
export async function aiGeneratePublishMeta(
  settings: Settings, item: Item, positioning: Positioning, pillars: Pillar[],
): Promise<AIPublishMeta> {
  const user = [
    positioningContext(positioning, pillars),
    '',
    `Vidéo : "${item.finalTitle || item.title}"${item.angle ? ` (angle : ${item.angle})` : ''}`,
    `Plateforme : ${item.platform}`,
    'Rédige une description engageante (2-4 phrases) et une liste de hashtags pertinents.',
    'Réponds avec un objet JSON : "description" (string) et "hashtags" (string, ex: "#x #y #z").',
  ].filter(Boolean).join('\n');
  const raw = await complete(settings, SYSTEM_JSON, user, 1500);
  const o = extractJSON<AIPublishMeta>(raw);
  return { description: String(o.description || ''), hashtags: String(o.hashtags || '') };
}

// ---------------------------------------------------------------------------
// 4. Analyser les résultats (texte / markdown léger)
// ---------------------------------------------------------------------------
export async function aiAnalyze(
  settings: Settings, items: Item[], positioning: Positioning, pillars: Pillar[],
): Promise<string> {
  const pub = published(items).filter((i) => i.stats.views > 0);
  if (pub.length === 0) {
    throw new AIError('Renseigne d\'abord les statistiques d\'au moins une vidéo publiée.');
  }
  const pl = (id: string | null) => pillars.find((p) => p.id === id)?.name ?? '—';
  const patterns = detectPatterns(items, pl);

  const lines = pub.map((i) =>
    `- "${i.finalTitle || i.title}" [${i.format}, pilier: ${pl(i.pillarId)}, hook: ${i.hookType || '?'}] ` +
    `→ ${i.stats.views} vues, rétention ${i.stats.retention}%, ${i.stats.likes} likes, ` +
    `${i.stats.comments} comm., +${i.stats.subsGained} abonnés` +
    (i.lessonWorked ? ` | a marché: ${i.lessonWorked}` : '') +
    (i.lessonFailed ? ` | à revoir: ${i.lessonFailed}` : ''),
  ).join('\n');

  const best = (rows: { key: string; avgViews: number }[]) =>
    rows.slice(0, 1).map((r) => `${r.key} (${Math.round(r.avgViews)} vues moy.)`).join('') || '—';

  const user = [
    positioningContext(positioning, pillars),
    '',
    `Voici ${pub.length} vidéos publiées avec leurs stats :`,
    lines,
    '',
    'Tendances détectées :',
    `- Meilleur pilier : ${best(patterns.byPillar)}`,
    `- Meilleur format : ${best(patterns.byFormat)}`,
    `- Meilleur type de hook : ${best(patterns.byHook)}`,
    `- Meilleur jour : ${best(patterns.byWeekday)}`,
    '',
    'Analyse ces résultats comme un coach. Donne :',
    '1) 3 constats clairs (ce qui marche / ne marche pas),',
    '2) 3 actions concrètes pour la prochaine vidéo,',
    '3) 1 chose à arrêter de faire.',
    'Réponds en texte simple et court (pas de JSON), avec des tirets. Sois direct et encourageant.',
  ].join('\n');

  const system =
    'Tu es un coach de créateurs de contenu bienveillant et direct. Tu réponds en français, ' +
    'en conseils concrets et actionnables, sans jargon.';
  return complete(settings, system, user, 3000);
}

// Quick connectivity test used by the settings screen.
export async function aiTest(settings: Settings): Promise<string> {
  const raw = await complete(settings, 'Réponds en un mot.', 'Dis "OK".', 20);
  return raw;
}
