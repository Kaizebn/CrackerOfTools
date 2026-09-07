import type {
  Item, Positioning, Settings, Monetization, LearningStep,
  ChecklistItem, ContentFormat,
} from './types';
import { emptyScript } from './types';
import { uid } from './db';

export function defaultPositioning(): Positioning {
  return {
    id: 1,
    niche: '', subNiche: '', audience: '', promise: '',
    dominantFormat: 'short', tone: '',
    avatarAge: '', avatarProblem: '', avatarWatches: '',
    references: [],
  };
}

export function defaultSettings(): Settings {
  return {
    id: 1,
    onboardingDone: false,
    mainGoalTitle: 'Atteindre 1000 abonnés',
    mainGoalTarget: 1000,
    mainGoalCurrent: 0,
    mainGoalUnit: 'abonnés',
    longsPerWeek: 1,
    shortsPerWeek: 5,
    pillars: [],
    aiProvider: 'anthropic',
    aiApiKey: '',
    aiModel: 'claude-opus-5',
  };
}

export function defaultMonetization(): Monetization {
  return { id: 1, ytSubs: 0, ytWatchHours: 0, tiktokFollowers: 0 };
}

// Default filming/editing checklists copied onto each new item.
export function defaultFilmingChecklist(): ChecklistItem[] {
  return [
    'Lumière en place',
    'Son testé (micro)',
    'Cadrage vérifié',
    'Tenue / décor OK',
    'Hook filmé en premier',
  ].map((label) => ({ id: uid(), label, done: false }));
}

export function defaultEditingChecklist(): ChecklistItem[] {
  return [
    'Rushs importés',
    'Montage rythmé (couper les temps morts)',
    'Sous-titres ajoutés',
    'Musique / sons',
    'Miniature créée',
    'Relecture finale',
  ].map((label) => ({ id: uid(), label, done: false }));
}

export function newItem(partial: Partial<Item> = {}): Item {
  const now = Date.now();
  const format: ContentFormat = partial.format ?? 'short';
  return {
    id: uid(),
    title: '',
    angle: '',
    format,
    source: '',
    potential: 3,
    status: 'idea',
    pillarId: null,
    whyItWorks: '',
    hookType: null,
    script: emptyScript(),
    filmingChecklist: defaultFilmingChecklist(),
    editingChecklist: defaultEditingChecklist(),
    timeSpent: { scripting: 0, filming: 0, editing: 0, thumbnail: 0, other: 0 },
    platform: 'both',
    plannedDate: null,
    publishedAt: null,
    finalTitle: '',
    thumbnail: null,
    description: '',
    hashtags: '',
    stats: {
      views: 0, watchTimeMinutes: 0, retention: 0,
      likes: 0, comments: 0, shares: 0, subsGained: 0,
    },
    lessonWorked: '',
    lessonFailed: '',
    createdAt: now,
    updatedAt: now,
    ...partial,
  };
}

// A default learning path (Branche Progression) seeded on first launch.
export function defaultLearningSteps(): LearningStep[] {
  const steps = [
    {
      title: 'Les bases du cadrage',
      goal: 'Filmer une image nette, bien composée, à hauteur des yeux.',
      resource: 'Cherche "règle des tiers" + "cadrage smartphone" sur YouTube.',
      exercise: 'Filme 3 plans du même sujet avec des cadrages différents et compare.',
    },
    {
      title: 'Le son',
      goal: 'Obtenir un son clair, sans écho ni bruit de fond.',
      resource: 'Cherche "améliorer son vidéo sans micro" et compare avec/sans micro cravate.',
      exercise: 'Enregistre 30s dans 3 pièces différentes, garde la meilleure.',
    },
    {
      title: 'Le montage rythmé',
      goal: 'Couper tous les temps morts pour garder l\'attention.',
      resource: 'Regarde 3 shorts qui te scotchent et compte les coupes.',
      exercise: 'Monte un short en supprimant chaque silence de plus de 0,5s.',
    },
    {
      title: 'L\'écriture de hooks',
      goal: 'Accrocher dans les 3 premières secondes.',
      resource: 'Note 10 hooks de vidéos que tu as regardées jusqu\'au bout.',
      exercise: 'Écris 5 hooks pour une même idée et choisis le plus fort.',
    },
    {
      title: 'Les miniatures',
      goal: 'Donner envie de cliquer sans mentir.',
      resource: 'Compare 5 miniatures performantes de ta niche.',
      exercise: 'Crée 2 miniatures pour une vidéo et demande un avis extérieur.',
    },
    {
      title: 'Les titres',
      goal: 'Écrire un titre qui promet une valeur claire.',
      resource: 'Analyse les titres du top 10 de ta niche.',
      exercise: 'Écris 5 variantes de titre pour ta prochaine vidéo.',
    },
    {
      title: 'L\'analyse de rétention',
      goal: 'Lire une courbe de rétention et savoir quoi corriger.',
      resource: 'Cherche "courbe de rétention YouTube expliquée".',
      exercise: 'Repère le moment où les gens partent sur ta dernière vidéo.',
    },
  ];
  return steps.map((s, i) => ({
    id: uid(),
    order: i,
    title: s.title,
    goal: s.goal,
    resource: s.resource,
    exercise: s.exercise,
    done: false,
  }));
}
