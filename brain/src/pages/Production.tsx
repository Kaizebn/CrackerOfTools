import { useMemo, useState } from 'react';
import { useItems, useSettings, usePositioning } from '../lib/hooks';
import { updateItem } from '../lib/store';
import { uid } from '../db/db';
import { Card, Input, EmptyState, Badge, Stat } from '../components/ui';
import { fmtMinutes } from '../lib/format';
import type { Item, ChecklistItem, TimeSpent, Shot } from '../db/types';
import { aiConfigured, aiGenerateStoryboard, hasScript } from '../lib/ai';
import { useAsync, Spark, AIErrorText, AIHint } from '../components/ai';
import { STATUS_LABELS } from '../db/types';

const STEP_LABELS: Record<keyof TimeSpent, string> = {
  scripting: 'Écriture', filming: 'Tournage', editing: 'Montage',
  thumbnail: 'Miniature', other: 'Autre',
};

export default function Production() {
  const items = useItems();
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // In production = has a script or is further along, but not published.
  const inProd = items.filter((i) => ['script', 'filmed', 'edited'].includes(i.status));
  const selected = items.find((i) => i.id === selectedId) ?? inProd[0] ?? null;

  // Aggregate time per step across every item (published included).
  const totals = useMemo(() => {
    const t: TimeSpent = { scripting: 0, filming: 0, editing: 0, thumbnail: 0, other: 0 };
    for (const i of items) {
      (Object.keys(t) as (keyof TimeSpent)[]).forEach((k) => (t[k] += i.timeSpent[k] || 0));
    }
    return t;
  }, [items]);
  const grandTotal = Object.values(totals).reduce((a, b) => a + b, 0);
  const maxStep = Math.max(1, ...Object.values(totals));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold text-white">🎬 Production</h1>
        <p className="text-sm text-slate-500">Tes checklists de tournage/montage et le temps passé par étape.</p>
      </div>

      {/* Time analysis */}
      <Card>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="section-title">Où passe ton temps ?</h2>
          <span className="text-sm text-slate-500">Total : {fmtMinutes(grandTotal)}</span>
        </div>
        {grandTotal === 0 ? (
          <p className="text-sm text-slate-600 italic">Renseigne le temps passé sur tes vidéos pour voir où tu perds du temps.</p>
        ) : (
          <div className="space-y-2">
            {(Object.keys(totals) as (keyof TimeSpent)[]).map((k) => (
              <div key={k} className="flex items-center gap-3">
                <span className="w-20 shrink-0 text-sm text-slate-400">{STEP_LABELS[k]}</span>
                <div className="h-5 flex-1 overflow-hidden rounded bg-ink-800">
                  <div className="h-full rounded bg-brand/70" style={{ width: `${(totals[k] / maxStep) * 100}%` }} />
                </div>
                <span className="w-20 shrink-0 text-right text-sm tabular-nums text-slate-300">{fmtMinutes(totals[k])}</span>
              </div>
            ))}
          </div>
        )}
      </Card>

      {inProd.length === 0 ? (
        <EmptyState
          icon="🎬"
          title="Rien en production"
          hint="Écris le script d'une idée (branche Écriture) pour la faire passer en production."
        />
      ) : (
        <div className="grid gap-4 lg:grid-cols-[260px_1fr]">
          <div className="space-y-2">
            {inProd.map((i) => (
              <button
                key={i.id}
                onClick={() => setSelectedId(i.id)}
                className={`w-full rounded-lg border p-3 text-left transition-colors ${
                  selected?.id === i.id ? 'border-brand bg-brand/10' : 'border-ink-700 bg-ink-850 hover:border-ink-600'
                }`}
              >
                <div className="text-sm font-semibold text-slate-100 line-clamp-1">{i.title || 'Sans titre'}</div>
                <div className="mt-1"><Badge color="amber">{STATUS_LABELS[i.status]}</Badge></div>
              </button>
            ))}
          </div>
          {selected && <ProdEditor key={selected.id} item={selected} />}
        </div>
      )}
    </div>
  );
}

function ProdEditor({ item }: { item: Item }) {
  return (
    <div className="space-y-4">
      <Card className="space-y-4">
        <h2 className="section-title line-clamp-1">{item.title || 'Sans titre'}</h2>

        <div className="grid gap-4 sm:grid-cols-2">
          <Checklist
            title="Checklist de tournage"
            list={item.filmingChecklist}
            onChange={(list) => updateItem(item.id, { filmingChecklist: list })}
          />
          <Checklist
            title="Checklist de montage"
            list={item.editingChecklist}
            onChange={(list) => updateItem(item.id, { editingChecklist: list })}
          />
        </div>
      </Card>

      <StoryboardCard item={item} />

      <TimeTracker item={item} />

      <div className="flex flex-wrap gap-2">
        {item.status === 'script' && (
          <button className="btn-primary" onClick={() => updateItem(item.id, { status: 'filmed' })}>
            ✅ Marquer comme tournée
          </button>
        )}
        {item.status === 'filmed' && (
          <button className="btn-primary" onClick={() => updateItem(item.id, { status: 'edited' })}>
            ✅ Marquer comme montée
          </button>
        )}
        {item.status === 'edited' && (
          <span className="text-sm text-accent-green">✓ Prête à publier — direction la branche Publication.</span>
        )}
      </div>
    </div>
  );
}

function Checklist({
  title, list, onChange,
}: { title: string; list: ChecklistItem[]; onChange: (l: ChecklistItem[]) => void }) {
  const [newLabel, setNewLabel] = useState('');
  const done = list.filter((c) => c.done).length;

  const toggle = (id: string) => onChange(list.map((c) => (c.id === id ? { ...c, done: !c.done } : c)));
  const add = () => {
    if (!newLabel.trim()) return;
    onChange([...list, { id: uid(), label: newLabel.trim(), done: false }]);
    setNewLabel('');
  };
  const remove = (id: string) => onChange(list.filter((c) => c.id !== id));

  return (
    <div className="rounded-lg border border-ink-700 bg-ink-850 p-3">
      <div className="mb-2 flex items-center justify-between">
        <span className="text-xs font-bold uppercase tracking-wide text-slate-400">{title}</span>
        <span className="text-xs text-slate-500">{done}/{list.length}</span>
      </div>
      <div className="space-y-1">
        {list.map((c) => (
          <div key={c.id} className="group flex items-center gap-2 text-sm">
            <input type="checkbox" className="h-4 w-4 accent-brand" checked={c.done} onChange={() => toggle(c.id)} />
            <span className={`flex-1 ${c.done ? 'text-slate-500 line-through' : 'text-slate-200'}`}>{c.label}</span>
            <button className="text-slate-600 opacity-0 group-hover:opacity-100 hover:text-accent-red" onClick={() => remove(c.id)}>✕</button>
          </div>
        ))}
      </div>
      <div className="mt-2 flex gap-1.5">
        <Input className="text-sm" value={newLabel} onChange={(e) => setNewLabel(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && add()} placeholder="Ajouter…" />
        <button className="btn-ghost btn-sm" onClick={add}>+</button>
      </div>
    </div>
  );
}

function TimeTracker({ item }: { item: Item }) {
  const set = (k: keyof TimeSpent, v: number) =>
    updateItem(item.id, { timeSpent: { ...item.timeSpent, [k]: Math.max(0, v) } });
  const total = Object.values(item.timeSpent).reduce((a, b) => a + b, 0);

  return (
    <Card>
      <div className="mb-3 flex items-center justify-between">
        <h3 className="font-bold text-white">Temps passé (minutes)</h3>
        <Stat label="Total vidéo" value={fmtMinutes(total)} />
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        {(Object.keys(STEP_LABELS) as (keyof TimeSpent)[]).map((k) => (
          <label key={k} className="block">
            <span className="mb-1 block text-xs text-slate-400">{STEP_LABELS[k]}</span>
            <Input type="number" min={0} value={item.timeSpent[k]} onChange={(e) => set(k, +e.target.value)} />
          </label>
        ))}
      </div>
    </Card>
  );
}

function StoryboardCard({ item }: { item: Item }) {
  const settings = useSettings();
  const positioning = usePositioning();
  const { loading, error, run } = useAsync();
  const shots: Shot[] = item.storyboard || [];
  const total = shots.reduce((a, sh) => a + (sh.duration || 0), 0);

  const generate = () => run(async () => {
    const sb = await aiGenerateStoryboard(settings, item, positioning);
    await updateItem(item.id, { storyboard: sb });
  });

  return (
    <Card>
      <div className="flex items-center justify-between">
        <div>
          <h3 className="font-bold text-white">🎬 Plan de tournage</h3>
          <p className="text-xs text-slate-500">L'IA découpe ton script en plans prêts à filmer.</p>
        </div>
        {aiConfigured(settings) && (
          <Spark onClick={generate} loading={loading} disabled={!hasScript(item)} className="btn-primary btn-sm">
            {shots.length ? 'Régénérer' : 'Générer le plan'}
          </Spark>
        )}
      </div>

      {!aiConfigured(settings) && <div className="mt-3"><AIHint /></div>}
      {aiConfigured(settings) && !hasScript(item) && (
        <p className="mt-2 text-sm text-slate-500">Écris d'abord le script de cette vidéo (branche Écriture), puis reviens générer le plan.</p>
      )}
      <AIErrorText error={error} />

      {shots.length > 0 && (
        <div className="mt-3 space-y-2">
          <div className="text-xs text-slate-500">{shots.length} plan(s) · durée estimée ≈ {total}s</div>
          {shots.map((sh, i) => (
            <div key={i} className="rounded-lg border border-ink-700 bg-ink-850 p-3">
              <div className="mb-1 flex items-center justify-between">
                <span className="text-xs font-bold uppercase tracking-wide text-brand-soft">Plan {i + 1}</span>
                {sh.duration > 0 && <span className="text-xs text-slate-500">≈ {sh.duration}s</span>}
              </div>
              {sh.visual && <p className="text-sm text-slate-200"><span className="text-slate-500">🎥 Visuel :</span> {sh.visual}</p>}
              {sh.voiceover && <p className="mt-0.5 text-sm text-slate-300"><span className="text-slate-500">🎙️ Voix off :</span> {sh.voiceover}</p>}
              {sh.text && <p className="mt-0.5 text-sm text-accent-amber"><span className="text-slate-500">💬 Texte écran :</span> {sh.text}</p>}
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
