import type { Item, Settings, Positioning, LearningStep } from '../db/types';
import { positioningComplete } from './store';
import { published } from './analysis';
import { daysBetween } from './format';

export interface Action {
  id: string;
  title: string;
  detail: string;
  to: string;         // route to jump to
  priority: number;   // lower = more urgent
  tone: 'urgent' | 'normal' | 'good';
}

export interface Alert {
  id: string;
  text: string;
  to: string;
  level: 'warn' | 'info';
}

interface Ctx {
  settings: Settings;
  positioning: Positioning;
  items: Item[];
  learning: LearningStep[];
}

// Idea reserve = ideas not yet published (the pool of things to make).
const reserve = (items: Item[]) => items.filter((i) => i.status !== 'published');
const inReserveEarly = (items: Item[]) =>
  items.filter((i) => i.status === 'idea' || i.status === 'validated');

export function daysSinceLastPublish(items: Item[]): number | null {
  const pub = published(items)
    .map((i) => i.publishedAt)
    .filter(Boolean)
    .sort()
    .reverse();
  if (pub.length === 0) return null;
  return daysBetween(new Date(pub[0]!), new Date());
}

export function generateActions(ctx: Ctx): Action[] {
  const { settings, positioning, items, learning } = ctx;
  const actions: Action[] = [];
  const add = (a: Omit<Action, 'id'>) => actions.push({ ...a, id: `a${actions.length}` });

  // 1. Positioning is the gate — nothing else matters until it's set.
  if (!positioningComplete(positioning)) {
    add({
      title: 'Définis ton positionnement',
      detail: 'Niche, audience, promesse, ton. C\'est la base de tout le reste.',
      to: '/positionnement', priority: 0, tone: 'urgent',
    });
    return actions.sort((a, b) => a.priority - b.priority).slice(0, 3);
  }

  // 2. Content pillars.
  if (settings.pillars.length < 3) {
    add({
      title: 'Définis tes piliers de contenu',
      detail: 'Choisis 3 à 5 thèmes récurrents pour structurer tes idées.',
      to: '/reglages', priority: 1, tone: 'urgent',
    });
  }

  // 3. Idea reserve.
  const reserveCount = reserve(items).length;
  if (reserveCount < 10) {
    add({
      title: 'Remplis ta banque d\'idées',
      detail: `Il te reste ${reserveCount} idée(s) en réserve. Vise au moins 10.`,
      to: '/idees', priority: 2, tone: reserveCount < 5 ? 'urgent' : 'normal',
    });
  }

  // 4. Publishing cadence.
  const since = daysSinceLastPublish(items);
  if (since === null) {
    add({
      title: 'Publie ta première vidéo',
      detail: 'Le plus dur est de commencer. Fais avancer une idée jusqu\'à la publication.',
      to: '/publication', priority: 3, tone: 'urgent',
    });
  } else if (since >= 3) {
    add({
      title: 'Publie une nouvelle vidéo',
      detail: `${since} jours sans publier. Garde le rythme.`,
      to: '/publication', priority: 3, tone: since >= 7 ? 'urgent' : 'normal',
    });
  }

  // 5. Move the pipeline forward: find the item closest to publication.
  const validated = items.filter((i) => i.status === 'validated');
  const scripted = items.filter((i) => i.status === 'script');
  const filmed = items.filter((i) => i.status === 'filmed');
  const edited = items.filter((i) => i.status === 'edited');

  if (edited.length) {
    add({
      title: 'Publie une vidéo montée',
      detail: `"${edited[0].title || 'Sans titre'}" est prête. Programme-la ou publie-la.`,
      to: '/publication', priority: 4, tone: 'good',
    });
  } else if (filmed.length) {
    add({
      title: 'Monte une vidéo tournée',
      detail: `"${filmed[0].title || 'Sans titre'}" attend le montage.`,
      to: '/production', priority: 5, tone: 'normal',
    });
  } else if (scripted.length) {
    add({
      title: 'Tourne une vidéo',
      detail: `Le script de "${scripted[0].title || 'Sans titre'}" est prêt à filmer.`,
      to: '/production', priority: 5, tone: 'normal',
    });
  } else if (validated.length) {
    add({
      title: 'Écris un script',
      detail: `"${validated[0].title || 'Sans titre'}" est validée. Passe à l\'écriture.`,
      to: '/ecriture', priority: 5, tone: 'normal',
    });
  }

  // 6. Published items missing stats.
  const missingStats = published(items).filter((i) => i.stats.views === 0);
  if (missingStats.length) {
    add({
      title: 'Renseigne tes statistiques',
      detail: `${missingStats.length} vidéo(s) publiée(s) sans stats. Mesure pour progresser.`,
      to: '/analyse', priority: 6, tone: 'normal',
    });
  }

  // 7. Published items missing lessons.
  const missingLessons = published(items).filter(
    (i) => i.stats.views > 0 && !i.lessonWorked && !i.lessonFailed,
  );
  if (missingLessons.length) {
    add({
      title: 'Note tes leçons',
      detail: `Qu\'est-ce qui a marché sur "${missingLessons[0].finalTitle || missingLessons[0].title || 'ta dernière vidéo'}" ?`,
      to: '/analyse', priority: 7, tone: 'normal',
    });
  }

  // 8. Learning path next step.
  const nextStep = [...learning].sort((a, b) => a.order - b.order).find((s) => !s.done);
  if (nextStep) {
    add({
      title: `Apprends : ${nextStep.title}`,
      detail: nextStep.goal,
      to: '/progression', priority: 8, tone: 'good',
    });
  }

  // Fallback so the screen is never empty.
  if (actions.length === 0) {
    add({
      title: 'Ajoute une nouvelle idée',
      detail: 'Tout est à jour. Continue à nourrir ta banque d\'idées.',
      to: '/idees', priority: 9, tone: 'good',
    });
  }

  return actions.sort((a, b) => a.priority - b.priority).slice(0, 3);
}

export function generateAlerts(ctx: Ctx): Alert[] {
  const { items } = ctx;
  const alerts: Alert[] = [];
  const add = (a: Omit<Alert, 'id'>) => alerts.push({ ...a, id: `al${alerts.length}` });

  const since = daysSinceLastPublish(items);
  if (since !== null && since >= 3) {
    add({ text: `Aucune vidéo publiée depuis ${since} jours`, to: '/publication', level: 'warn' });
  }

  const early = inReserveEarly(items).length;
  if (early < 10) {
    add({
      text: early === 0 ? 'Banque d\'idées vide' : `Banque d\'idées faible (${early})`,
      to: '/idees',
      level: early < 5 ? 'warn' : 'info',
    });
  }

  const missingStats = published(items).filter((i) => i.stats.views === 0).length;
  if (missingStats > 0) {
    add({ text: `${missingStats} vidéo(s) publiée(s) sans statistiques`, to: '/analyse', level: 'info' });
  }

  return alerts;
}
