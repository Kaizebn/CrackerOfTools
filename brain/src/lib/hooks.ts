import { useLiveQuery } from 'dexie-react-hooks';
import { db } from '../db/db';
import { defaultPositioning, defaultSettings, defaultMonetization } from '../db/defaults';
import type { Pillar } from '../db/types';

export function useSettings() {
  return useLiveQuery(() => db.settings.get(1), []) ?? defaultSettings();
}
export function usePositioning() {
  return useLiveQuery(() => db.positioning.get(1), []) ?? defaultPositioning();
}
export function useMonetization() {
  return useLiveQuery(() => db.monetization.get(1), []) ?? defaultMonetization();
}
export function useItems() {
  return useLiveQuery(() => db.items.orderBy('createdAt').reverse().toArray(), []) ?? [];
}
export function useItem(id: string | undefined) {
  return useLiveQuery(() => (id ? db.items.get(id) : undefined), [id]);
}
export function useHooks() {
  return useLiveQuery(() => db.hooks.orderBy('createdAt').reverse().toArray(), []) ?? [];
}
export function useLearning() {
  return useLiveQuery(() => db.learning.orderBy('order').toArray(), []) ?? [];
}
export function useJournal() {
  return useLiveQuery(() => db.journal.orderBy('createdAt').reverse().toArray(), []) ?? [];
}
export function useRevenues() {
  return useLiveQuery(() => db.revenues.orderBy('date').reverse().toArray(), []) ?? [];
}
export function useBrands() {
  return useLiveQuery(() => db.brands.orderBy('updatedAt').reverse().toArray(), []) ?? [];
}
export function useActivity() {
  return useLiveQuery(() => db.activity.toArray(), []) ?? [];
}

// Resolve a pillar id to its object / name / color.
export function pillarLookup(pillars: Pillar[]) {
  const map = new Map(pillars.map((p) => [p.id, p]));
  return {
    get: (id: string | null) => (id ? map.get(id) : undefined),
    name: (id: string | null) => (id ? map.get(id)?.name ?? '—' : '—'),
    color: (id: string | null) => (id ? map.get(id)?.color ?? '#3a4159' : '#3a4159'),
  };
}
