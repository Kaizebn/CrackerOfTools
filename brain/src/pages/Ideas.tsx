import { useMemo, useState } from 'react';
import { useItems, useSettings, usePositioning, pillarLookup } from '../lib/hooks';
import { createItem, updateItem, deleteItem } from '../lib/store';
import {
  Field, Input, Textarea, Select, Modal, EmptyState, Badge,
  StarRating, ConfirmButton,
} from '../components/ui';
import { STATUS_ORDER, STATUS_LABELS } from '../db/types';
import type { Item, ContentFormat, ItemStatus, HookType } from '../db/types';
import { HOOK_TYPES } from '../db/types';
import { aiConfigured, aiGenerateIdeas } from '../lib/ai';
import type { AIIdea } from '../lib/ai';
import { useAsync, Spark, AIErrorText, AIHint } from '../components/ai';

export default function Ideas() {
  const items = useItems();
  const settings = useSettings();
  const pl = pillarLookup(settings.pillars);
  const positioning = usePositioning();
  const [editing, setEditing] = useState<Item | null>(null);
  const [pillarFilter, setPillarFilter] = useState<string>('all');
  const [showAI, setShowAI] = useState(false);

  const reserveCount = items.filter((i) => i.status !== 'published').length;

  const filtered = useMemo(() => {
    if (pillarFilter === 'all') return items;
    if (pillarFilter === 'none') return items.filter((i) => !i.pillarId);
    return items.filter((i) => i.pillarId === pillarFilter);
  }, [items, pillarFilter]);

  const byStatus = (s: ItemStatus) => filtered.filter((i) => i.status === s);

  const openNew = async () => {
    const item = await createItem();
    setEditing(item);
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-white">💡 Idées</h1>
          <p className="text-sm text-slate-500">
            Ta banque d'idées et ton pipeline de production.
          </p>
        </div>
        <div className="flex items-center gap-2">
          {aiConfigured(settings) && (
            <Spark onClick={() => setShowAI(true)}>Générer des idées</Spark>
          )}
          <button className="btn-primary" onClick={openNew}>+ Nouvelle idée</button>
        </div>
      </div>

      {!aiConfigured(settings) && <AIHint />}

      {reserveCount < 10 && (
        <div className="rounded-lg border border-accent-amber/40 bg-accent-amber/5 px-4 py-2.5 text-sm text-accent-amber">
          ⚠️ Seulement {reserveCount} idée(s) en réserve. Vise au moins 10 pour ne jamais être à sec.
        </div>
      )}

      {/* Pillar filter */}
      {settings.pillars.length > 0 && (
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500">Filtrer :</span>
          <button
            onClick={() => setPillarFilter('all')}
            className={`chip ${pillarFilter === 'all' ? 'bg-brand/20 text-brand-soft' : 'bg-ink-800 text-slate-400'}`}
          >Tous</button>
          {settings.pillars.map((p) => (
            <button
              key={p.id}
              onClick={() => setPillarFilter(p.id)}
              className="chip"
              style={pillarFilter === p.id
                ? { background: p.color + '33', color: p.color }
                : { background: '#1a1e2e', color: '#94a3b8' }}
            >
              <span className="h-2 w-2 rounded-full" style={{ background: p.color }} />
              {p.name}
            </button>
          ))}
        </div>
      )}

      {items.length === 0 ? (
        <EmptyState
          icon="💡"
          title="Ta banque d'idées est vide"
          hint="Note toutes tes idées, même mauvaises. On triera après. Vise 10 idées d'avance."
          action={<button className="btn-primary" onClick={openNew}>Ajouter ma première idée</button>}
        />
      ) : (
        <div className="grid gap-3 overflow-x-auto lg:grid-cols-6">
          {STATUS_ORDER.map((s) => {
            const list = byStatus(s);
            return (
              <div key={s} className="min-w-[220px] lg:min-w-0">
                <div className="mb-2 flex items-center justify-between px-1">
                  <span className="text-xs font-bold uppercase tracking-wide text-slate-400">
                    {STATUS_LABELS[s]}
                  </span>
                  <span className="text-xs text-slate-600">{list.length}</span>
                </div>
                <div className="space-y-2">
                  {list.map((item) => (
                    <IdeaCard key={item.id} item={item} pl={pl} onOpen={() => setEditing(item)} />
                  ))}
                  {list.length === 0 && (
                    <div className="rounded-lg border border-dashed border-ink-700/60 py-6 text-center text-xs text-slate-600">
                      —
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {editing && (
        <IdeaEditor
          item={editing}
          pillars={settings.pillars}
          onClose={() => setEditing(null)}
        />
      )}

      {showAI && (
        <AIIdeasModal
          settings={settings}
          positioning={positioning}
          pillars={settings.pillars}
          existingTitles={items.map((i) => i.title).filter(Boolean)}
          onClose={() => setShowAI(false)}
        />
      )}
    </div>
  );
}

function IdeaCard({
  item, pl, onOpen,
}: { item: Item; pl: ReturnType<typeof pillarLookup>; onOpen: () => void }) {
  const pillar = pl.get(item.pillarId);
  return (
    <button
      onClick={onOpen}
      className="w-full rounded-lg border border-ink-700 bg-ink-850 p-3 text-left transition-colors hover:border-brand/50"
    >
      <div className="flex items-start justify-between gap-2">
        <span className="text-sm font-semibold text-slate-100 leading-snug line-clamp-2">
          {item.title || 'Sans titre'}
        </span>
        <span className="shrink-0 text-xs text-accent-amber">{'★'.repeat(item.potential)}</span>
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-1.5">
        <Badge color={item.format === 'short' ? 'blue' : 'brand'}>
          {item.format === 'short' ? 'Short' : 'Long'}
        </Badge>
        {pillar && (
          <span className="chip" style={{ background: pillar.color + '26', color: pillar.color }}>
            {pillar.name}
          </span>
        )}
      </div>
    </button>
  );
}

function IdeaEditor({
  item, pillars, onClose,
}: { item: Item; pillars: { id: string; name: string; color: string }[]; onClose: () => void }) {
  const [form, setForm] = useState<Item>(item);
  const set = <K extends keyof Item>(k: K, v: Item[K]) => setForm((f) => ({ ...f, [k]: v }));
  const [warn, setWarn] = useState('');

  const save = async () => {
    await updateItem(item.id, form);
    onClose();
  };

  // Advancing to "validated" (or beyond) requires the "why it works" field.
  const changeStatus = (s: ItemStatus) => {
    const idx = STATUS_ORDER.indexOf(s);
    if (idx >= 1 && !form.whyItWorks.trim()) {
      setWarn('Renseigne "Pourquoi ça marcherait" pour valider cette idée.');
      return;
    }
    setWarn('');
    set('status', s);
  };

  const remove = async () => {
    await deleteItem(item.id);
    onClose();
  };

  return (
    <Modal open onClose={onClose} title="Idée" wide>
      <div className="space-y-4">
        <Field label="Titre">
          <Input value={form.title} onChange={(e) => set('title', e.target.value)} placeholder="Titre accrocheur de la vidéo" autoFocus />
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Angle">
            <Input value={form.angle} onChange={(e) => set('angle', e.target.value)} placeholder="L'approche originale" />
          </Field>
          <Field label="Source d'inspiration">
            <Input value={form.source} onChange={(e) => set('source', e.target.value)} placeholder="D'où vient l'idée ?" />
          </Field>
          <Field label="Format">
            <Select value={form.format} onChange={(e) => set('format', e.target.value as ContentFormat)}>
              <option value="short">Short</option>
              <option value="long">Long</option>
            </Select>
          </Field>
          <Field label="Pilier de contenu">
            <Select value={form.pillarId ?? ''} onChange={(e) => set('pillarId', e.target.value || null)}>
              <option value="">— Aucun —</option>
              {pillars.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </Select>
          </Field>
          <Field label="Type de hook (optionnel)">
            <Select value={form.hookType ?? ''} onChange={(e) => set('hookType', (e.target.value || null) as HookType | null)}>
              <option value="">— Non défini —</option>
              {HOOK_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </Select>
          </Field>
          <Field label="Potentiel">
            <div className="pt-1.5"><StarRating value={form.potential} onChange={(v) => set('potential', v)} /></div>
          </Field>
        </div>

        <Field label="Pourquoi ça marcherait ?" required hint="Obligatoire pour valider l'idée">
          <Textarea value={form.whyItWorks} onChange={(e) => set('whyItWorks', e.target.value)} placeholder="Pourquoi les gens vont regarder ça jusqu'au bout ?" />
        </Field>

        <div>
          <span className="label">Étape du pipeline</span>
          <div className="flex flex-wrap gap-1.5">
            {STATUS_ORDER.map((s) => (
              <button
                key={s}
                onClick={() => changeStatus(s)}
                className="chip"
                style={form.status === s
                  ? { background: '#7c5cff33', color: '#9b82ff', boxShadow: 'inset 0 0 0 1px #7c5cff' }
                  : { background: '#1a1e2e', color: '#94a3b8' }}
              >
                {STATUS_LABELS[s]}
              </button>
            ))}
          </div>
          {warn && <p className="mt-2 text-sm text-accent-red">{warn}</p>}
        </div>

        <div className="flex items-center justify-between pt-2">
          <ConfirmButton onConfirm={remove}>Supprimer l'idée</ConfirmButton>
          <div className="flex gap-2">
            <button className="btn-ghost" onClick={onClose}>Annuler</button>
            <button className="btn-primary" onClick={save}>Enregistrer</button>
          </div>
        </div>
      </div>
    </Modal>
  );
}

function AIIdeasModal({
  settings, positioning, pillars, existingTitles, onClose,
}: {
  settings: import('../db/types').Settings;
  positioning: import('../db/types').Positioning;
  pillars: import('../db/types').Pillar[];
  existingTitles: string[];
  onClose: () => void;
}) {
  const { loading, error, run } = useAsync();
  const [ideas, setIdeas] = useState<AIIdea[]>([]);
  const [picked, setPicked] = useState<Record<number, boolean>>({});
  const [done, setDone] = useState(0);

  const generate = () =>
    run(async () => {
      const res = await aiGenerateIdeas(settings, positioning, pillars, existingTitles, 8);
      setIdeas(res);
      setPicked(Object.fromEntries(res.map((_, i) => [i, true])));
    });

  // Generate on first open.
  useMemo(() => { generate(); }, []); // eslint-disable-line

  const toggle = (i: number) => setPicked((p) => ({ ...p, [i]: !p[i] }));

  const addPicked = async () => {
    const chosen = ideas.filter((_, i) => picked[i]);
    for (const idea of chosen) {
      const pillar = pillars.find((p) => p.name.toLowerCase() === idea.pillar.toLowerCase());
      await createItem({
        title: idea.title,
        angle: idea.angle,
        format: idea.format,
        whyItWorks: idea.whyItWorks,
        potential: idea.potential,
        pillarId: pillar?.id ?? null,
        status: 'idea',
      });
    }
    setDone(chosen.length);
    setTimeout(onClose, 700);
  };

  const count = Object.values(picked).filter(Boolean).length;

  return (
    <Modal open onClose={onClose} title="✨ Idées générées par l'IA" wide>
      {loading ? (
        <div className="py-10 text-center text-slate-400">
          <div className="animate-spin text-2xl">◌</div>
          <p className="mt-2 text-sm">L'IA réfléchit à des idées pour ta chaîne…</p>
        </div>
      ) : error ? (
        <div>
          <AIErrorText error={error} />
          <div className="mt-3 flex justify-end gap-2">
            <button className="btn-ghost" onClick={onClose}>Fermer</button>
            <Spark onClick={generate} className="btn-primary">Réessayer</Spark>
          </div>
        </div>
      ) : done > 0 ? (
        <div className="py-8 text-center text-accent-green">✓ {done} idée(s) ajoutée(s) à ta banque !</div>
      ) : (
        <div className="space-y-3">
          <p className="text-sm text-slate-500">Décoche celles que tu ne veux pas, puis ajoute-les à ta banque.</p>
          <div className="space-y-2 max-h-[50vh] overflow-y-auto pr-1">
            {ideas.map((idea, i) => (
              <label key={i} className="flex cursor-pointer items-start gap-3 rounded-lg border border-ink-700 bg-ink-850 p-3">
                <input type="checkbox" className="mt-1 h-4 w-4 accent-brand" checked={!!picked[i]} onChange={() => toggle(i)} />
                <span className="min-w-0 flex-1">
                  <span className="flex items-center gap-2">
                    <span className="font-semibold text-slate-100">{idea.title}</span>
                    <Badge color={idea.format === 'short' ? 'blue' : 'brand'}>{idea.format === 'short' ? 'Short' : 'Long'}</Badge>
                    <span className="text-xs text-accent-amber">{'★'.repeat(idea.potential)}</span>
                  </span>
                  {idea.angle && <span className="mt-0.5 block text-sm text-slate-400">{idea.angle}</span>}
                  {idea.whyItWorks && <span className="mt-0.5 block text-xs text-slate-500">💡 {idea.whyItWorks}</span>}
                  {idea.pillar && <span className="mt-1 inline-block text-xs text-brand-soft">#{idea.pillar}</span>}
                </span>
              </label>
            ))}
          </div>
          <div className="flex items-center justify-between pt-1">
            <Spark onClick={generate} className="btn-ghost btn-sm">Régénérer</Spark>
            <button className="btn-primary" onClick={addPicked} disabled={count === 0}>
              Ajouter {count} idée(s)
            </button>
          </div>
        </div>
      )}
    </Modal>
  );
}
