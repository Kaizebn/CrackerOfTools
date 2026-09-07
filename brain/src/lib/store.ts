import { db, uid, todayISO } from '../db/db';
import {
  defaultPositioning, defaultSettings, defaultMonetization,
  defaultLearningSteps, newItem,
} from '../db/defaults';
import type {
  Item, Settings, Positioning, Monetization, Activity,
} from '../db/types';

// -----------------------------------------------------------------------------
// Bootstrap: make sure singleton rows and the seeded learning path exist.
// Safe to call on every launch — it only fills gaps.
// -----------------------------------------------------------------------------
export async function initDB(): Promise<void> {
  await db.transaction(
    'rw',
    db.settings, db.positioning, db.monetization, db.learning,
    async () => {
      if (!(await db.settings.get(1))) await db.settings.put(defaultSettings());
      if (!(await db.positioning.get(1))) await db.positioning.put(defaultPositioning());
      if (!(await db.monetization.get(1))) await db.monetization.put(defaultMonetization());
      if ((await db.learning.count()) === 0) await db.learning.bulkPut(defaultLearningSteps());
    },
  );
}

// -----------------------------------------------------------------------------
// Activity log — one entry per meaningful action, used by the streak counter.
// We de-duplicate identical kinds within the same day to keep the log light.
// -----------------------------------------------------------------------------
export async function logActivity(kind: string, label: string): Promise<void> {
  const date = todayISO();
  const existing = await db.activity
    .where('date').equals(date)
    .filter((a) => a.kind === kind)
    .first();
  if (existing) return;
  const entry: Activity = { id: uid(), date, kind, label, createdAt: Date.now() };
  await db.activity.add(entry);
}

// -----------------------------------------------------------------------------
// Settings helpers
// -----------------------------------------------------------------------------
export async function getSettings(): Promise<Settings> {
  return (await db.settings.get(1)) ?? defaultSettings();
}
export async function saveSettings(patch: Partial<Settings>): Promise<void> {
  const cur = await getSettings();
  await db.settings.put({ ...cur, ...patch, id: 1 });
}

export async function getPositioning(): Promise<Positioning> {
  return (await db.positioning.get(1)) ?? defaultPositioning();
}
export async function savePositioning(patch: Partial<Positioning>): Promise<void> {
  const cur = await getPositioning();
  await db.positioning.put({ ...cur, ...patch, id: 1 });
}

export async function getMonetization(): Promise<Monetization> {
  return (await db.monetization.get(1)) ?? defaultMonetization();
}
export async function saveMonetization(patch: Partial<Monetization>): Promise<void> {
  const cur = await getMonetization();
  await db.monetization.put({ ...cur, ...patch, id: 1 });
}

// -----------------------------------------------------------------------------
// Items (the content pipeline)
// -----------------------------------------------------------------------------
export async function createItem(partial: Partial<Item> = {}): Promise<Item> {
  const item = newItem(partial);
  await db.items.add(item);
  await logActivity('idea', 'Nouvelle idée ajoutée');
  return item;
}

export async function updateItem(id: string, patch: Partial<Item>): Promise<void> {
  const cur = await db.items.get(id);
  if (!cur) return;
  const next = { ...cur, ...patch, updatedAt: Date.now() };
  await db.items.put(next);

  // Log status transitions so any progress feeds the streak.
  if (patch.status && patch.status !== cur.status) {
    if (patch.status === 'published') await logActivity('publish', 'Vidéo publiée');
    else await logActivity('pipeline', 'Progression pipeline');
  }
}

export async function deleteItem(id: string): Promise<void> {
  await db.items.delete(id);
}

// Convenience: is the positioning complete enough to unlock the rest?
export function positioningComplete(p: Positioning): boolean {
  return Boolean(
    p.niche.trim() && p.audience.trim() && p.promise.trim() && p.tone.trim(),
  );
}
