// ---------------------------------------------------------------------------
// Domain types for BRAIN. Everything lives locally in IndexedDB (via Dexie).
// ---------------------------------------------------------------------------

export type ContentFormat = 'short' | 'long';
export type Platform = 'youtube' | 'tiktok' | 'both';

// Pipeline stages a content item flows through.
export type ItemStatus =
  | 'idea'       // Idée
  | 'validated'  // Validée
  | 'script'     // Script écrit
  | 'filmed'     // Tournée
  | 'edited'     // Montée
  | 'published'; // Publiée

export const STATUS_ORDER: ItemStatus[] = [
  'idea', 'validated', 'script', 'filmed', 'edited', 'published',
];

export const STATUS_LABELS: Record<ItemStatus, string> = {
  idea: 'Idée',
  validated: 'Validée',
  script: 'Script',
  filmed: 'Tournée',
  edited: 'Montée',
  published: 'Publiée',
};

export const HOOK_TYPES = ['question', 'chiffre', 'contradiction', 'tension', 'promesse'] as const;
export type HookType = typeof HOOK_TYPES[number];

export interface Pillar {
  id: string;
  name: string;
  color: string;
}

export interface ReferenceChannel {
  id: string;
  name: string;
  subscribers: string;
  note: string;       // "ce que je fais différemment"
}

export interface ChecklistItem {
  id: string;
  label: string;
  done: boolean;
}

// Time spent per production step, in minutes.
export interface TimeSpent {
  scripting: number;
  filming: number;
  editing: number;
  thumbnail: number;
  other: number;
}

// Manually entered performance stats for a published item.
export interface VideoStats {
  views: number;
  watchTimeMinutes: number; // durée de visionnage totale
  retention: number;        // taux de rétention en %
  likes: number;
  comments: number;
  shares: number;
  subsGained: number;
}

// Structured script content. Fields used depend on format.
export interface ScriptData {
  // shared
  hook: string;
  cta: string;
  // short
  development: string;
  punchline: string;   // "chute"
  // long
  promise: string;
  chapters: string;    // corps en chapitres
  retention: string;   // notes de rétention
  // pre-shoot checklist
  hookTested: boolean;
  valueClear: boolean;
  cleanEnding: boolean;
}

export function emptyScript(): ScriptData {
  return {
    hook: '', cta: '', development: '', punchline: '',
    promise: '', chapters: '', retention: '',
    hookTested: false, valueClear: false, cleanEnding: false,
  };
}

// One shot of a filming plan (storyboard) generated from the script.
export interface Shot {
  visual: string;    // ce qu'on montre / filme
  voiceover: string; // ce qu'on dit
  text: string;      // texte incrusté à l'écran (court, peut être vide)
  duration: number;  // durée estimée en secondes
}

// The central content object: one row per video-in-the-making.
export interface Item {
  id: string;
  title: string;
  angle: string;
  format: ContentFormat;
  source: string;            // source d'inspiration
  potential: number;         // 1-5
  status: ItemStatus;
  pillarId: string | null;
  whyItWorks: string;        // obligatoire pour valider
  hookType: HookType | null; // pour la détection de motifs
  script: ScriptData;
  storyboard: Shot[];

  // Production
  filmingChecklist: ChecklistItem[];
  editingChecklist: ChecklistItem[];
  timeSpent: TimeSpent;

  // Publication
  platform: Platform;
  plannedDate: string | null;    // ISO date (yyyy-mm-dd) créneau planifié
  publishedAt: string | null;    // ISO datetime réel
  finalTitle: string;
  thumbnail: string | null;      // data URL
  description: string;
  hashtags: string;

  // Analyse
  stats: VideoStats;
  lessonWorked: string;
  lessonFailed: string;

  createdAt: number;
  updatedAt: number;
}

export interface HookEntry {
  id: string;
  text: string;
  type: HookType;
  createdAt: number;
}

export interface Positioning {
  id: number; // singleton = 1
  niche: string;
  subNiche: string;
  audience: string;
  promise: string;
  dominantFormat: ContentFormat;
  tone: string;
  avatarAge: string;
  avatarProblem: string;
  avatarWatches: string;
  references: ReferenceChannel[];
}

export interface Settings {
  id: number; // singleton = 1
  onboardingDone: boolean;
  mainGoalTitle: string;
  mainGoalTarget: number;
  mainGoalCurrent: number;
  mainGoalUnit: string;
  longsPerWeek: number;   // rythme cible
  shortsPerWeek: number;
  pillars: Pillar[];
  // Assistant IA (optionnel) — clé stockée localement.
  aiProvider: string; // 'anthropic' | 'openrouter'
  aiApiKey: string;
  aiModel: string;
}

export interface Monetization {
  id: number; // singleton = 1
  ytSubs: number;
  ytWatchHours: number;
  tiktokFollowers: number;
}

export interface Revenue {
  id: string;
  source: 'pub' | 'affiliation' | 'sponsor' | 'produit';
  amount: number;
  label: string;
  date: string; // ISO date
}

export type BrandStatus = 'contacted' | 'talking' | 'signed';

export interface BrandContact {
  id: string;
  brand: string;
  contact: string;
  status: BrandStatus;
  note: string;
  updatedAt: number;
}

export interface LearningStep {
  id: string;
  order: number;
  title: string;
  goal: string;
  resource: string;
  exercise: string;
  done: boolean;
}

export interface JournalEntry {
  id: string;
  date: string; // ISO date
  text: string;
  createdAt: number;
}

// Activity log powers the streak counter.
export interface Activity {
  id: string;
  date: string; // yyyy-mm-dd
  kind: string;
  label: string;
  createdAt: number;
}
