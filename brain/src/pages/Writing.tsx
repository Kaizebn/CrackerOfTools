import { useMemo, useState } from 'react';
import { useItems, useHooks } from '../lib/hooks';
import { updateItem } from '../lib/store';
import { db, uid } from '../db/db';
import {
  Card, Field, Input, Textarea, Select, EmptyState, Badge, Stat, ConfirmButton,
} from '../components/ui';
import { HOOK_TYPES, STATUS_LABELS } from '../db/types';
import type { Item, ScriptData, HookType } from '../db/types';

const WPM = 150; // mots par minute à l'oral

function wordCount(s: string): number {
  return s.trim() ? s.trim().split(/\s+/).length : 0;
}

function scriptWordCount(sc: ScriptData, format: Item['format']): number {
  const parts = format === 'short'
    ? [sc.hook, sc.development, sc.punchline, sc.cta]
    : [sc.hook, sc.promise, sc.chapters, sc.retention, sc.cta];
  return parts.reduce((a, p) => a + wordCount(p), 0);
}

export default function Writing() {
  const items = useItems();
  const [tab, setTab] = useState<'scripts' | 'hooks'>('scripts');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Items worth writing for: everything not yet published.
  const writable = items.filter((i) => i.status !== 'published');
  const selected = items.find((i) => i.id === selectedId) ?? writable[0] ?? null;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-white">✍️ Écriture</h1>
          <p className="text-sm text-slate-500">Structure tes scripts et réutilise tes meilleurs hooks.</p>
        </div>
        <div className="flex gap-1 rounded-lg bg-ink-800 p-1">
          <button className={`btn-sm rounded-md px-3 ${tab === 'scripts' ? 'bg-brand text-white' : 'text-slate-400'}`} onClick={() => setTab('scripts')}>Scripts</button>
          <button className={`btn-sm rounded-md px-3 ${tab === 'hooks' ? 'bg-brand text-white' : 'text-slate-400'}`} onClick={() => setTab('hooks')}>Bibliothèque de hooks</button>
        </div>
      </div>

      {tab === 'hooks' ? (
        <HookLibrary />
      ) : writable.length === 0 ? (
        <EmptyState
          icon="✍️"
          title="Aucune idée à scripter"
          hint="Ajoute d'abord des idées dans la branche Idées, puis reviens écrire leurs scripts."
        />
      ) : (
        <div className="grid gap-4 lg:grid-cols-[260px_1fr]">
          {/* Item list */}
          <div className="space-y-2">
            {writable.map((i) => (
              <button
                key={i.id}
                onClick={() => setSelectedId(i.id)}
                className={`w-full rounded-lg border p-3 text-left transition-colors ${
                  selected?.id === i.id ? 'border-brand bg-brand/10' : 'border-ink-700 bg-ink-850 hover:border-ink-600'
                }`}
              >
                <div className="text-sm font-semibold text-slate-100 line-clamp-1">{i.title || 'Sans titre'}</div>
                <div className="mt-1 flex items-center gap-1.5">
                  <Badge color={i.format === 'short' ? 'blue' : 'brand'}>{i.format === 'short' ? 'Short' : 'Long'}</Badge>
                  <span className="text-xs text-slate-500">{STATUS_LABELS[i.status]}</span>
                </div>
              </button>
            ))}
          </div>

          {selected && <ScriptEditor key={selected.id} item={selected} />}
        </div>
      )}
    </div>
  );
}

function ScriptEditor({ item }: { item: Item }) {
  const [sc, setSc] = useState<ScriptData>(item.script);
  const [saved, setSaved] = useState(false);
  const set = <K extends keyof ScriptData>(k: K, v: ScriptData[K]) => setSc((s) => ({ ...s, [k]: v }));

  const words = scriptWordCount(sc, item.format);
  const minutes = words / WPM;
  const duration = words === 0 ? '0s' : minutes < 1 ? `${Math.round(minutes * 60)}s` : `${minutes.toFixed(1)} min`;

  const save = async (advance = false) => {
    const patch: Partial<Item> = { script: sc };
    // First time a real script exists, bump the pipeline stage.
    if (advance && (item.status === 'idea' || item.status === 'validated')) {
      patch.status = 'script';
    }
    await updateItem(item.id, patch);
    setSaved(true);
    setTimeout(() => setSaved(false), 1500);
  };

  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="section-title line-clamp-1">{item.title || 'Sans titre'}</h2>
        <div className="flex gap-2">
          <Stat label="Mots" value={words} />
          <Stat label="Durée lecture" value={duration} />
        </div>
      </div>

      <div className="rounded-lg border border-ink-700 bg-ink-850 p-3 text-xs text-slate-500">
        Structure imposée pour un <b className="text-slate-300">{item.format === 'short' ? 'Short' : 'Long'}</b> —
        remplis chaque bloc dans l'ordre.
      </div>

      <Field label="① Hook (0-3s) — accroche immédiate">
        <Textarea value={sc.hook} onChange={(e) => set('hook', e.target.value)} placeholder="La première phrase qui empêche de scroller." />
      </Field>

      {item.format === 'short' ? (
        <>
          <Field label="② Développement">
            <Textarea value={sc.development} onChange={(e) => set('development', e.target.value)} placeholder="Le cœur de la valeur, sans temps mort." />
          </Field>
          <Field label="③ Chute">
            <Textarea value={sc.punchline} onChange={(e) => set('punchline', e.target.value)} placeholder="La punchline finale qui marque." />
          </Field>
        </>
      ) : (
        <>
          <Field label="② Promesse">
            <Textarea value={sc.promise} onChange={(e) => set('promise', e.target.value)} placeholder="Ce que le spectateur va apprendre / obtenir." />
          </Field>
          <Field label="③ Corps (en chapitres)">
            <Textarea className="min-h-[140px]" value={sc.chapters} onChange={(e) => set('chapters', e.target.value)} placeholder={'Chapitre 1 : …\nChapitre 2 : …\nChapitre 3 : …'} />
          </Field>
          <Field label="④ Rétention (relances, boucles ouvertes)">
            <Textarea value={sc.retention} onChange={(e) => set('retention', e.target.value)} placeholder="Comment tu gardes l'attention jusqu'au bout." />
          </Field>
        </>
      )}

      <Field label={`${item.format === 'short' ? '④' : '⑤'} CTA (appel à l'action)`}>
        <Textarea value={sc.cta} onChange={(e) => set('cta', e.target.value)} placeholder="Abonne-toi, commente, regarde la suivante…" />
      </Field>

      {/* Pre-shoot checklist */}
      <div className="rounded-lg border border-ink-700 bg-ink-850 p-3">
        <div className="mb-2 text-xs font-bold uppercase tracking-wide text-slate-400">Checklist avant tournage</div>
        <div className="space-y-1.5">
          {[
            ['hookTested', 'Hook testé (il accroche vraiment)'],
            ['valueClear', 'Valeur claire (on sait ce qu\'on gagne)'],
            ['cleanEnding', 'Fin nette (pas de bafouillage)'],
          ].map(([k, label]) => (
            <label key={k} className="flex items-center gap-2 text-sm text-slate-300">
              <input
                type="checkbox"
                className="h-4 w-4 accent-brand"
                checked={sc[k as keyof ScriptData] as boolean}
                onChange={(e) => set(k as keyof ScriptData, e.target.checked as never)}
              />
              {label}
            </label>
          ))}
        </div>
      </div>

      <div className="flex items-center justify-end gap-3">
        {saved && <span className="text-sm text-accent-green">Enregistré ✓</span>}
        <button className="btn-ghost" onClick={() => save(false)}>Enregistrer</button>
        <button className="btn-primary" onClick={() => save(true)}>Enregistrer + marquer "Script"</button>
      </div>
    </Card>
  );
}

function HookLibrary() {
  const hooks = useHooks();
  const [text, setText] = useState('');
  const [type, setType] = useState<HookType>('question');

  const grouped = useMemo(() => {
    const map: Record<string, typeof hooks> = {};
    for (const t of HOOK_TYPES) map[t] = [];
    for (const h of hooks) (map[h.type] ||= []).push(h);
    return map;
  }, [hooks]);

  const add = async () => {
    if (!text.trim()) return;
    await db.hooks.add({ id: uid(), text: text.trim(), type, createdAt: Date.now() });
    setText('');
  };

  return (
    <div className="space-y-5">
      <Card className="space-y-3">
        <h2 className="section-title">Ajouter un hook réutilisable</h2>
        <div className="grid gap-2 sm:grid-cols-[1fr_160px_auto]">
          <Input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && add()}
            placeholder="Ex : « Personne ne te dira ça mais… »"
          />
          <Select value={type} onChange={(e) => setType(e.target.value as HookType)}>
            {HOOK_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </Select>
          <button className="btn-primary" onClick={add}>Ajouter</button>
        </div>
      </Card>

      {hooks.length === 0 ? (
        <EmptyState icon="🪝" title="Aucun hook enregistré" hint="Collectionne les accroches qui te font arrêter de scroller. Classe-les par type." />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {HOOK_TYPES.map((t) => (
            <Card key={t}>
              <div className="mb-2 flex items-center justify-between">
                <span className="font-bold capitalize text-white">{t}</span>
                <span className="text-xs text-slate-500">{grouped[t].length}</span>
              </div>
              <div className="space-y-1.5">
                {grouped[t].length === 0 && <p className="text-xs text-slate-600 italic">Aucun</p>}
                {grouped[t].map((h) => (
                  <div key={h.id} className="group flex items-start justify-between gap-2 rounded-md bg-ink-850 px-2.5 py-1.5 text-sm text-slate-300">
                    <span>{h.text}</span>
                    <ConfirmButton className="btn-danger btn-sm opacity-0 group-hover:opacity-100" onConfirm={() => db.hooks.delete(h.id)}>✕</ConfirmButton>
                  </div>
                ))}
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
