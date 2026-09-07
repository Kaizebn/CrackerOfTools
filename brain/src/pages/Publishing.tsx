import { useMemo, useRef, useState } from 'react';
import {
  ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, ReferenceLine, CartesianGrid,
} from 'recharts';
import { useItems, useSettings } from '../lib/hooks';
import { updateItem, saveSettings } from '../lib/store';
import {
  Card, Field, Input, Textarea, Select, Modal, EmptyState, Badge, Stat,
} from '../components/ui';
import { fileToThumbnail } from '../lib/image';
import { fmtDate, fmtDateTime } from '../lib/format';
import type { Item, Platform } from '../db/types';

const MONTHS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];
const DOW = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

function iso(d: Date) { return d.toISOString().slice(0, 10); }
function startOfWeek(d: Date) { const x = new Date(d); const day = (x.getDay() + 6) % 7; x.setDate(x.getDate() - day); x.setHours(0, 0, 0, 0); return x; }

export default function Publishing() {
  const items = useItems();
  const settings = useSettings();
  const [cursor, setCursor] = useState(new Date());
  const [editing, setEditing] = useState<Item | null>(null);

  const targetPerWeek = settings.longsPerWeek + settings.shortsPerWeek;

  // This week's published count.
  const weekStart = startOfWeek(new Date());
  const publishedThisWeek = items.filter(
    (i) => i.status === 'published' && i.publishedAt && new Date(i.publishedAt) >= weekStart,
  ).length;

  const ready = items.filter((i) => i.status === 'edited');
  const planned = items.filter((i) => i.plannedDate && i.status !== 'published');

  // ----- Calendar grid for the month in `cursor` -----
  const grid = useMemo(() => {
    const y = cursor.getFullYear(), m = cursor.getMonth();
    const first = new Date(y, m, 1);
    const startPad = (first.getDay() + 6) % 7; // Monday-first
    const daysInMonth = new Date(y, m + 1, 0).getDate();
    const cells: (Date | null)[] = [];
    for (let i = 0; i < startPad; i++) cells.push(null);
    for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(y, m, d));
    while (cells.length % 7 !== 0) cells.push(null);
    return cells;
  }, [cursor]);

  const itemsOnDay = (d: Date) => {
    const key = iso(d);
    return items.filter(
      (i) => (i.publishedAt && i.publishedAt.slice(0, 10) === key) || i.plannedDate === key,
    );
  };

  // ----- Coherence chart: last 13 weeks -----
  const coherence = useMemo(() => {
    const weeks: { label: string; count: number }[] = [];
    const base = startOfWeek(new Date());
    for (let w = 12; w >= 0; w--) {
      const ws = new Date(base); ws.setDate(ws.getDate() - w * 7);
      const we = new Date(ws); we.setDate(we.getDate() + 7);
      const count = items.filter(
        (i) => i.status === 'published' && i.publishedAt &&
          new Date(i.publishedAt) >= ws && new Date(i.publishedAt) < we,
      ).length;
      weeks.push({ label: `${ws.getDate()}/${ws.getMonth() + 1}`, count });
    }
    return weeks;
  }, [items]);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold text-white">📅 Publication</h1>
        <p className="text-sm text-slate-500">Ton calendrier, ton rythme, et la fiche de chaque vidéo publiée.</p>
      </div>

      {/* Rhythm */}
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="section-title">Rythme cible</h2>
            <p className="text-sm text-slate-500">
              {settings.longsPerWeek} long{settings.longsPerWeek > 1 ? 's' : ''} + {settings.shortsPerWeek} short{settings.shortsPerWeek > 1 ? 's' : ''} / semaine
            </p>
          </div>
          <div className="flex items-center gap-3">
            <Stat label="Cette semaine" value={`${publishedThisWeek}/${targetPerWeek}`} sub="publiées" />
            <RhythmEditor
              longs={settings.longsPerWeek}
              shorts={settings.shortsPerWeek}
              onSave={(l, s) => saveSettings({ longsPerWeek: l, shortsPerWeek: s })}
            />
          </div>
        </div>
      </Card>

      {/* Ready to publish */}
      {ready.length > 0 && (
        <Card>
          <h2 className="section-title mb-3">Prêtes à publier ({ready.length})</h2>
          <div className="grid gap-2 sm:grid-cols-2">
            {ready.map((i) => (
              <button key={i.id} onClick={() => setEditing(i)} className="flex items-center justify-between rounded-lg border border-ink-700 bg-ink-850 p-3 text-left hover:border-brand/50">
                <span className="text-sm font-semibold text-slate-100 line-clamp-1">{i.title || 'Sans titre'}</span>
                <Badge color="green">Publier →</Badge>
              </button>
            ))}
          </div>
        </Card>
      )}

      {/* Calendar */}
      <Card>
        <div className="mb-3 flex items-center justify-between">
          <button className="btn-ghost btn-sm" onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() - 1, 1))}>←</button>
          <h2 className="section-title">{MONTHS[cursor.getMonth()]} {cursor.getFullYear()}</h2>
          <button className="btn-ghost btn-sm" onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1))}>→</button>
        </div>
        <div className="grid grid-cols-7 gap-1 text-center text-xs text-slate-500 mb-1">
          {DOW.map((d) => <div key={d}>{d}</div>)}
        </div>
        <div className="grid grid-cols-7 gap-1">
          {grid.map((d, idx) => {
            if (!d) return <div key={idx} className="aspect-square rounded-md bg-ink-950/40" />;
            const dayItems = itemsOnDay(d);
            const isToday = iso(d) === iso(new Date());
            return (
              <div
                key={idx}
                className={`aspect-square rounded-md border p-1 text-left overflow-hidden ${
                  isToday ? 'border-brand bg-brand/10' : 'border-ink-700 bg-ink-850'
                }`}
              >
                <div className="text-[11px] text-slate-500">{d.getDate()}</div>
                <div className="space-y-0.5">
                  {dayItems.slice(0, 2).map((i) => (
                    <button
                      key={i.id}
                      onClick={() => setEditing(i)}
                      title={i.finalTitle || i.title}
                      className={`block w-full truncate rounded px-1 text-[10px] leading-tight ${
                        i.status === 'published' ? 'bg-accent-green/25 text-accent-green' : 'bg-accent-blue/25 text-accent-blue'
                      }`}
                    >
                      {i.finalTitle || i.title || '•'}
                    </button>
                  ))}
                  {dayItems.length > 2 && <div className="text-[10px] text-slate-500">+{dayItems.length - 2}</div>}
                </div>
              </div>
            );
          })}
        </div>
        <div className="mt-3 flex gap-4 text-xs text-slate-500">
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-accent-green" /> Publiée</span>
          <span className="flex items-center gap-1"><span className="h-2 w-2 rounded-full bg-accent-blue" /> Planifiée</span>
        </div>
      </Card>

      {/* Coherence */}
      <Card>
        <h2 className="section-title mb-1">Cohérence — 13 dernières semaines</h2>
        <p className="mb-3 text-sm text-slate-500">Est-ce que tu tiens ton rythme ? La ligne = ta cible ({targetPerWeek}/sem).</p>
        <div className="h-56">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={coherence} margin={{ top: 6, right: 6, bottom: 0, left: -20 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#232838" vertical={false} />
              <XAxis dataKey="label" tick={{ fill: '#64748b', fontSize: 11 }} tickLine={false} axisLine={{ stroke: '#232838' }} />
              <YAxis allowDecimals={false} tick={{ fill: '#64748b', fontSize: 11 }} tickLine={false} axisLine={false} />
              <Tooltip
                contentStyle={{ background: '#0f1117', border: '1px solid #232838', borderRadius: 8, fontSize: 12 }}
                labelStyle={{ color: '#94a3b8' }}
              />
              <ReferenceLine y={targetPerWeek} stroke="#7c5cff" strokeDasharray="4 4" />
              <Bar dataKey="count" name="Publiées" fill="#2ecc9b" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </Card>

      {planned.length > 0 && (
        <Card>
          <h2 className="section-title mb-2">Vidéos planifiées</h2>
          <div className="space-y-1.5">
            {planned.map((i) => (
              <button key={i.id} onClick={() => setEditing(i)} className="flex w-full items-center justify-between rounded-md bg-ink-850 px-3 py-2 text-left text-sm hover:bg-ink-800">
                <span className="text-slate-200 line-clamp-1">{i.title || 'Sans titre'}</span>
                <span className="text-slate-500">{fmtDate(i.plannedDate)}</span>
              </button>
            ))}
          </div>
        </Card>
      )}

      {items.length === 0 && (
        <EmptyState icon="📅" title="Rien à publier pour l'instant" hint="Fais avancer une idée jusqu'au montage, puis reviens la publier ici." />
      )}

      {editing && <PublishEditor item={editing} onClose={() => setEditing(null)} />}
    </div>
  );
}

function RhythmEditor({ longs, shorts, onSave }: { longs: number; shorts: number; onSave: (l: number, s: number) => void }) {
  const [open, setOpen] = useState(false);
  const [l, setL] = useState(longs);
  const [s, setS] = useState(shorts);
  return (
    <>
      <button className="btn-ghost btn-sm" onClick={() => { setL(longs); setS(shorts); setOpen(true); }}>Modifier</button>
      <Modal open={open} onClose={() => setOpen(false)} title="Rythme cible">
        <div className="grid grid-cols-2 gap-3">
          <Field label="Longs / semaine"><Input type="number" min={0} value={l} onChange={(e) => setL(+e.target.value)} /></Field>
          <Field label="Shorts / semaine"><Input type="number" min={0} value={s} onChange={(e) => setS(+e.target.value)} /></Field>
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <button className="btn-ghost" onClick={() => setOpen(false)}>Annuler</button>
          <button className="btn-primary" onClick={() => { onSave(l, s); setOpen(false); }}>Enregistrer</button>
        </div>
      </Modal>
    </>
  );
}

function PublishEditor({ item, onClose }: { item: Item; onClose: () => void }) {
  const [form, setForm] = useState<Item>(item);
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const set = <K extends keyof Item>(k: K, v: Item[K]) => setForm((f) => ({ ...f, [k]: v }));

  const onFile = async (f: File | undefined) => {
    if (!f) return;
    setBusy(true);
    try { set('thumbnail', await fileToThumbnail(f)); }
    finally { setBusy(false); }
  };

  const save = async () => { await updateItem(item.id, form); onClose(); };

  const publishNow = async () => {
    const now = new Date().toISOString();
    await updateItem(item.id, { ...form, status: 'published', publishedAt: form.publishedAt || now });
    onClose();
  };

  return (
    <Modal open onClose={onClose} title={item.status === 'published' ? 'Vidéo publiée' : 'Publier / programmer'} wide>
      <div className="space-y-4">
        <Field label="Titre final">
          <Input value={form.finalTitle} onChange={(e) => set('finalTitle', e.target.value)} placeholder={form.title || 'Titre publié'} />
        </Field>

        {/* Thumbnail */}
        <div>
          <span className="label">Miniature</span>
          <div className="flex items-center gap-3">
            <div className="flex h-20 w-32 items-center justify-center overflow-hidden rounded-lg border border-ink-700 bg-ink-850 text-xs text-slate-600">
              {form.thumbnail ? <img src={form.thumbnail} alt="miniature" className="h-full w-full object-cover" /> : 'Aucune'}
            </div>
            <div className="space-y-1.5">
              <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => onFile(e.target.files?.[0])} />
              <button className="btn-ghost btn-sm" onClick={() => fileRef.current?.click()} disabled={busy}>
                {busy ? 'Traitement…' : 'Choisir une image'}
              </button>
              {form.thumbnail && <button className="btn-danger btn-sm ml-2" onClick={() => set('thumbnail', null)}>Retirer</button>}
            </div>
          </div>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Plateforme">
            <Select value={form.platform} onChange={(e) => set('platform', e.target.value as Platform)}>
              <option value="both">YouTube + TikTok</option>
              <option value="youtube">YouTube</option>
              <option value="tiktok">TikTok</option>
            </Select>
          </Field>
          <Field label="Créneau planifié (date)">
            <Input type="date" value={form.plannedDate ?? ''} onChange={(e) => set('plannedDate', e.target.value || null)} />
          </Field>
        </div>

        <Field label="Description">
          <Textarea value={form.description} onChange={(e) => set('description', e.target.value)} placeholder="Description de la vidéo" />
        </Field>
        <Field label="Hashtags">
          <Input value={form.hashtags} onChange={(e) => set('hashtags', e.target.value)} placeholder="#productivite #etudiant" />
        </Field>

        <Field label="Date & heure de publication réelle">
          <Input
            type="datetime-local"
            value={form.publishedAt ? form.publishedAt.slice(0, 16) : ''}
            onChange={(e) => set('publishedAt', e.target.value ? new Date(e.target.value).toISOString() : null)}
          />
        </Field>

        {item.status === 'published' && form.publishedAt && (
          <p className="text-xs text-slate-500">Publiée le {fmtDateTime(form.publishedAt)}</p>
        )}

        <div className="flex items-center justify-end gap-2 pt-2">
          <button className="btn-ghost" onClick={save}>Enregistrer</button>
          {item.status !== 'published' && (
            <button className="btn-primary" onClick={publishNow}>Marquer comme publiée</button>
          )}
        </div>
      </div>
    </Modal>
  );
}
