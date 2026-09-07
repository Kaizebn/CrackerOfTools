import Dexie, { type Table } from 'dexie';
import type {
  Item, HookEntry, Positioning, Settings, Monetization,
  Revenue, BrandContact, LearningStep, JournalEntry, Activity,
} from './types';

// Single local database. Bump the version number if the schema changes.
export class BrainDB extends Dexie {
  items!: Table<Item, string>;
  hooks!: Table<HookEntry, string>;
  positioning!: Table<Positioning, number>;
  settings!: Table<Settings, number>;
  monetization!: Table<Monetization, number>;
  revenues!: Table<Revenue, string>;
  brands!: Table<BrandContact, string>;
  learning!: Table<LearningStep, string>;
  journal!: Table<JournalEntry, string>;
  activity!: Table<Activity, string>;

  constructor() {
    super('brain');
    // Only fields we query/sort by need to be indexed.
    this.version(1).stores({
      items: 'id, status, format, pillarId, publishedAt, plannedDate, createdAt, updatedAt',
      hooks: 'id, type, createdAt',
      positioning: 'id',
      settings: 'id',
      monetization: 'id',
      revenues: 'id, source, date',
      brands: 'id, status, updatedAt',
      learning: 'id, order',
      journal: 'id, date, createdAt',
      activity: 'id, date, createdAt',
    });
  }
}

export const db = new BrainDB();

// Small helper for stable unique ids without extra dependencies.
export function uid(): string {
  return (
    Date.now().toString(36) +
    '-' +
    Math.random().toString(36).slice(2, 9)
  );
}

export function todayISO(): string {
  return new Date().toISOString().slice(0, 10);
}
