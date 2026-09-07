import { useState } from 'react';
import {
  ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, Legend,
} from 'recharts';
import { useItems, useSettings, pillarLookup } from '../lib/hooks';
import { updateItem } from '../lib/store';
import {
  Card, Field, Input, Textarea, Modal, EmptyState, Badge, Stat,
} from '../components/ui';
import {
  published, topAndFlop, detectPatterns, viewsTimeline, itemScore,
} from '../lib/analysis';
import { fmtNumber, fmtDate } from '../lib/format';
import type { Item, VideoStats } from '../db/types';

export default function Analysis() {
  const items = useItems();
  const settings = useSettings();
  const pl = pillarLookup(settings.pillars);
  const [editing, setEditing] = useState<Item | null>(null);

  const pub = published(items);
  const { top, flop } = topAndFlop(items);
  const patterns = detectPatterns(items, (id) => pl.name(id));
  const timeline = viewsTimeline(items);

  const totals = pub.reduce(
    (a, i) => ({
      views: a.views + i.stats.views,
      subs: a.subs + i.stats.subsGained,
      likes: a.likes + i.stats.likes,
    }),
    { views: 0, subs: 0, likes: 0 },
  );

  if (pub.length === 0) {
    return (
      <div className="space-y-6">
        <Header />
        <EmptyState
          icon="📊"
          title="Aucune vidéo publiée à analyser"
          hint="Publie une vidéo (branche Publication), puis reviens saisir ses statistiques pour mesurer ce qui marche."
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <Header />

      {/* Totals */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Stat label="Vidéos publiées" value={pub.length} />
        <Stat label="Vues totales" value={fmtNumber(totals.views)} />
        <Stat label="Abonnés gagnés" value={fmtNumber(totals.subs)} />
        <Stat label="Likes totaux" value={fmtNumber(totals.likes)} />
      </div>

      {/* Evolution */}
      <Card>
        <h2 className="section-title mb-1">Évolution dans le temps</h2>
        <p className="mb-3 text-sm text-slate-500">Vues et abonnés gagnés par vidéo publiée.</p>
        {timeline.length < 2 ? (
          <p className="text-sm text-slate-600 italic">Publie et renseigne au moins 2 vidéos pour voir une courbe.</p>
        ) : (
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={timeline} margin={{ top: 6, right: 8, bottom: 0, left: -18 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#232838" vertical={false} />
                <XAxis dataKey="date" tick={{ fill: '#64748b', fontSize: 11 }} tickLine={false} axisLine={{ stroke: '#232838' }} />
                <YAxis tick={{ fill: '#64748b', fontSize: 11 }} tickLine={false} axisLine={false} />
                <Tooltip contentStyle={{ background: '#0f1117', border: '1px solid #232838', borderRadius: 8, fontSize: 12 }} labelStyle={{ color: '#94a3b8' }} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Line type="monotone" dataKey="views" name="Vues" stroke="#3aa0ff" strokeWidth={2} dot={{ r: 3 }} />
                <Line type="monotone" dataKey="subs" name="Abonnés gagnés" stroke="#2ecc9b" strokeWidth={2} dot={{ r: 3 }} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        )}
      </Card>

      {/* Top / Flop */}
      <div className="grid gap-4 lg:grid-cols-2">
        <RankCard title="🏆 Top 5" items={top} onOpen={setEditing} accent="green" />
        <RankCard title="📉 Flop 5" items={flop} onOpen={setEditing} accent="red" />
      </div>

      {/* Patterns */}
      <Card>
        <h2 className="section-title mb-1">Détection de motifs</h2>
        <p className="mb-3 text-sm text-slate-500">
          Ce qui performe le mieux en moyenne (sur {patterns.sampleSize} vidéo{patterns.sampleSize > 1 ? 's' : ''} avec des vues).
        </p>
        <div className="grid gap-4 sm:grid-cols-2">
          <PatternBlock title="Par pilier" rows={patterns.byPillar} />
          <PatternBlock title="Par format" rows={patterns.byFormat} />
          <PatternBlock title="Par type de hook" rows={patterns.byHook} />
          <PatternBlock title="Par jour de publication" rows={patterns.byWeekday} />
        </div>
      </Card>

      {/* All videos to edit stats */}
      <Card>
        <h2 className="section-title mb-3">Toutes tes vidéos publiées</h2>
        <div className="space-y-1.5">
          {pub.map((i) => (
            <button key={i.id} onClick={() => setEditing(i)} className="flex w-full items-center justify-between gap-3 rounded-md bg-ink-850 px-3 py-2 text-left hover:bg-ink-800">
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-semibold text-slate-100">{i.finalTitle || i.title || 'Sans titre'}</span>
                <span className="text-xs text-slate-500">{fmtDate(i.publishedAt)}</span>
              </span>
              <span className="shrink-0 text-right text-xs text-slate-400">
                {i.stats.views > 0 ? `${fmtNumber(i.stats.views)} vues` : <Badge color="amber">stats à saisir</Badge>}
              </span>
            </button>
          ))}
        </div>
      </Card>

      {editing && <StatsEditor item={editing} onClose={() => setEditing(null)} />}
    </div>
  );
}

function Header() {
  return (
    <div>
      <h1 className="text-2xl font-extrabold text-white">📊 Analyse</h1>
      <p className="text-sm text-slate-500">Mesure, compare, et apprends de chaque vidéo.</p>
    </div>
  );
}

function RankCard({
  title, items, onOpen, accent,
}: { title: string; items: Item[]; onOpen: (i: Item) => void; accent: 'green' | 'red' }) {
  return (
    <Card>
      <h3 className="mb-2 font-bold text-white">{title}</h3>
      {items.length === 0 ? (
        <p className="text-sm text-slate-600 italic">Pas encore assez de données.</p>
      ) : (
        <div className="space-y-1.5">
          {items.map((i, n) => (
            <button key={i.id} onClick={() => onOpen(i)} className="flex w-full items-center gap-3 rounded-md bg-ink-850 px-3 py-2 text-left hover:bg-ink-800">
              <span className={`text-sm font-bold ${accent === 'green' ? 'text-accent-green' : 'text-accent-red'}`}>#{n + 1}</span>
              <span className="min-w-0 flex-1 truncate text-sm text-slate-200">{i.finalTitle || i.title || 'Sans titre'}</span>
              <span className="shrink-0 text-xs text-slate-500">{fmtNumber(i.stats.views)} vues · {fmtNumber(itemScore(i))} pts</span>
            </button>
          ))}
        </div>
      )}
    </Card>
  );
}

function PatternBlock({ title, rows }: { title: string; rows: { key: string; count: number; avgViews: number; avgRetention: number }[] }) {
  const max = Math.max(1, ...rows.map((r) => r.avgViews));
  return (
    <div className="rounded-lg border border-ink-700 bg-ink-850 p-3">
      <div className="mb-2 text-xs font-bold uppercase tracking-wide text-slate-400">{title}</div>
      {rows.length === 0 ? (
        <p className="text-xs text-slate-600 italic">Pas de données.</p>
      ) : (
        <div className="space-y-2">
          {rows.map((r) => (
            <div key={r.key}>
              <div className="flex justify-between text-xs">
                <span className="capitalize text-slate-300">{r.key} <span className="text-slate-600">({r.count})</span></span>
                <span className="tabular-nums text-slate-400">{fmtNumber(r.avgViews)} vues moy.</span>
              </div>
              <div className="mt-0.5 h-1.5 overflow-hidden rounded-full bg-ink-800">
                <div className="h-full rounded-full bg-brand" style={{ width: `${(r.avgViews / max) * 100}%` }} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

const STAT_FIELDS: { key: keyof VideoStats; label: string }[] = [
  { key: 'views', label: 'Vues' },
  { key: 'watchTimeMinutes', label: 'Durée de visionnage (min)' },
  { key: 'retention', label: 'Rétention (%)' },
  { key: 'likes', label: 'Likes' },
  { key: 'comments', label: 'Commentaires' },
  { key: 'shares', label: 'Partages' },
  { key: 'subsGained', label: 'Abonnés gagnés' },
];

function StatsEditor({ item, onClose }: { item: Item; onClose: () => void }) {
  const [stats, setStats] = useState<VideoStats>(item.stats);
  const [worked, setWorked] = useState(item.lessonWorked);
  const [failed, setFailed] = useState(item.lessonFailed);

  const setStat = (k: keyof VideoStats, v: number) => setStats((s) => ({ ...s, [k]: Math.max(0, v) }));

  const save = async () => {
    await updateItem(item.id, { stats, lessonWorked: worked, lessonFailed: failed });
    onClose();
  };

  return (
    <Modal open onClose={onClose} title="Statistiques & leçons" wide>
      <div className="space-y-4">
        <div className="text-sm font-semibold text-white">{item.finalTitle || item.title || 'Sans titre'}</div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {STAT_FIELDS.map((f) => (
            <Field key={f.key} label={f.label}>
              <Input type="number" min={0} value={stats[f.key]} onChange={(e) => setStat(f.key, +e.target.value)} />
            </Field>
          ))}
        </div>

        <div className="rounded-lg border border-ink-700 bg-ink-850 p-3 space-y-3">
          <div className="text-xs font-bold uppercase tracking-wide text-slate-400">Leçons</div>
          <Field label="✅ Ce qui a marché">
            <Textarea value={worked} onChange={(e) => setWorked(e.target.value)} placeholder="Hook, sujet, format, montage…" />
          </Field>
          <Field label="❌ Ce qui n'a pas marché">
            <Textarea value={failed} onChange={(e) => setFailed(e.target.value)} placeholder="Ce que tu ferais différemment" />
          </Field>
        </div>

        <div className="flex justify-end gap-2">
          <button className="btn-ghost" onClick={onClose}>Annuler</button>
          <button className="btn-primary" onClick={save}>Enregistrer</button>
        </div>
      </div>
    </Modal>
  );
}
