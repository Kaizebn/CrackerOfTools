import type { Item } from '../db/types';
import { STATUS_LABELS } from '../db/types';

export const published = (items: Item[]) => items.filter((i) => i.status === 'published');

// Overall "score" used for ranking (weighted engagement).
export function itemScore(i: Item): number {
  const s = i.stats;
  return s.views + s.likes * 3 + s.comments * 5 + s.shares * 8 + s.subsGained * 20;
}

export function topAndFlop(items: Item[], n = 5) {
  const pub = published(items).filter((i) => i.stats.views > 0);
  const sorted = [...pub].sort((a, b) => itemScore(b) - itemScore(a));
  return {
    top: sorted.slice(0, n),
    flop: sorted.slice(-n).reverse(),
  };
}

interface PatternRow {
  key: string;
  count: number;
  avgViews: number;
  avgRetention: number;
}

function groupBy(items: Item[], keyFn: (i: Item) => string | null): PatternRow[] {
  const map = new Map<string, Item[]>();
  for (const i of items) {
    const k = keyFn(i);
    if (!k) continue;
    if (!map.has(k)) map.set(k, []);
    map.get(k)!.push(i);
  }
  const rows: PatternRow[] = [];
  for (const [key, list] of map) {
    const views = list.reduce((a, b) => a + b.stats.views, 0);
    const ret = list.reduce((a, b) => a + b.stats.retention, 0);
    rows.push({
      key,
      count: list.length,
      avgViews: views / list.length,
      avgRetention: ret / list.length,
    });
  }
  return rows.sort((a, b) => b.avgViews - a.avgViews);
}

const WEEKDAYS = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];

export function detectPatterns(items: Item[], pillarName: (id: string | null) => string) {
  const pub = published(items).filter((i) => i.stats.views > 0);
  return {
    byPillar: groupBy(pub, (i) => (i.pillarId ? pillarName(i.pillarId) : null)),
    byFormat: groupBy(pub, (i) => (i.format === 'short' ? 'Short' : 'Long')),
    byHook: groupBy(pub, (i) => (i.hookType ? i.hookType : null)),
    byWeekday: groupBy(pub, (i) => {
      const d = i.publishedAt ? new Date(i.publishedAt) : null;
      return d && !isNaN(d.getTime()) ? WEEKDAYS[d.getDay()] : null;
    }),
    sampleSize: pub.length,
  };
}

// Time series of views over time (by publish date).
export function viewsTimeline(items: Item[]) {
  return published(items)
    .filter((i) => i.publishedAt)
    .sort((a, b) => (a.publishedAt! < b.publishedAt! ? -1 : 1))
    .map((i) => ({
      date: (i.publishedAt || '').slice(0, 10),
      title: i.finalTitle || i.title || 'Sans titre',
      views: i.stats.views,
      retention: i.stats.retention,
      subs: i.stats.subsGained,
    }));
}

export function statusCounts(items: Item[]) {
  const counts: Record<string, number> = {};
  for (const key of Object.keys(STATUS_LABELS)) counts[key] = 0;
  for (const i of items) counts[i.status] = (counts[i.status] || 0) + 1;
  return counts;
}
