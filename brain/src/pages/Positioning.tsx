import { useEffect, useState } from 'react';
import { usePositioning } from '../lib/hooks';
import { savePositioning, positioningComplete } from '../lib/store';
import { uid } from '../db/db';
import {
  Card, Field, Input, Textarea, Select, SectionTitle, ConfirmButton, Badge,
} from '../components/ui';
import type { ContentFormat, Positioning as P, ReferenceChannel } from '../db/types';

export default function Positioning() {
  const stored = usePositioning();
  const [form, setForm] = useState<P>(stored);
  const [saved, setSaved] = useState(false);

  // Keep local form in sync when the DB row first loads.
  useEffect(() => { setForm(stored); }, [stored.id, stored.niche]); // eslint-disable-line

  const set = <K extends keyof P>(k: K, v: P[K]) => setForm((f) => ({ ...f, [k]: v }));

  const save = async () => {
    await savePositioning(form);
    setSaved(true);
    setTimeout(() => setSaved(false), 1500);
  };

  const addRef = () => {
    const ref: ReferenceChannel = { id: uid(), name: '', subscribers: '', note: '' };
    set('references', [...form.references, ref]);
  };
  const updateRef = (id: string, patch: Partial<ReferenceChannel>) =>
    set('references', form.references.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  const removeRef = (id: string) =>
    set('references', form.references.filter((r) => r.id !== id));

  const complete = positioningComplete(form);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-white">🎯 Positionnement</h1>
          <p className="text-sm text-slate-500">La fondation de ta chaîne. Tout part de là.</p>
        </div>
        {complete
          ? <Badge color="green">✓ Complet</Badge>
          : <Badge color="red">À compléter</Badge>}
      </div>

      <Card className="space-y-4">
        <SectionTitle>Ton identité</SectionTitle>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Niche" required>
            <Input value={form.niche} onChange={(e) => set('niche', e.target.value)} placeholder="Ex : la productivité" />
          </Field>
          <Field label="Sous-niche">
            <Input value={form.subNiche} onChange={(e) => set('subNiche', e.target.value)} placeholder="Ex : productivité pour étudiants" />
          </Field>
          <Field label="Audience cible" required>
            <Input value={form.audience} onChange={(e) => set('audience', e.target.value)} placeholder="Ex : étudiants de 18-25 ans" />
          </Field>
          <Field label="Ton" required>
            <Input value={form.tone} onChange={(e) => set('tone', e.target.value)} placeholder="Ex : direct, fun, cash" />
          </Field>
          <Field label="Promesse" required hint="Ce que gagne le spectateur">
            <Input value={form.promise} onChange={(e) => set('promise', e.target.value)} placeholder="Ex : gagner 1h par jour" />
          </Field>
          <Field label="Format dominant">
            <Select value={form.dominantFormat} onChange={(e) => set('dominantFormat', e.target.value as ContentFormat)}>
              <option value="short">Short</option>
              <option value="long">Long</option>
            </Select>
          </Field>
        </div>
      </Card>

      <Card className="space-y-4">
        <SectionTitle>Avatar spectateur</SectionTitle>
        <p className="text-sm text-slate-500 -mt-2">La personne précise à qui tu t'adresses.</p>
        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Âge">
            <Input value={form.avatarAge} onChange={(e) => set('avatarAge', e.target.value)} placeholder="Ex : 20 ans" />
          </Field>
          <Field label="Son problème">
            <Input value={form.avatarProblem} onChange={(e) => set('avatarProblem', e.target.value)} placeholder="Ex : procrastine" />
          </Field>
          <Field label="Ce qu'il regarde déjà">
            <Input value={form.avatarWatches} onChange={(e) => set('avatarWatches', e.target.value)} placeholder="Ex : Ali Abdaal" />
          </Field>
        </div>
      </Card>

      <Card className="space-y-4">
        <SectionTitle right={<button className="btn-ghost btn-sm" onClick={addRef}>+ Chaîne</button>}>
          Chaînes de référence
        </SectionTitle>
        <p className="text-sm text-slate-500 -mt-2">5 à 10 chaînes qui t'inspirent et ce que tu fais différemment.</p>
        {form.references.length === 0 ? (
          <p className="text-sm text-slate-600 italic">Aucune chaîne pour l'instant.</p>
        ) : (
          <div className="space-y-3">
            {form.references.map((r) => (
              <div key={r.id} className="rounded-lg border border-ink-700 bg-ink-850 p-3">
                <div className="grid gap-2 sm:grid-cols-[1fr_140px]">
                  <Input value={r.name} onChange={(e) => updateRef(r.id, { name: e.target.value })} placeholder="Nom de la chaîne" />
                  <Input value={r.subscribers} onChange={(e) => updateRef(r.id, { subscribers: e.target.value })} placeholder="Abonnés (ex: 250k)" />
                </div>
                <Textarea
                  className="mt-2"
                  value={r.note}
                  onChange={(e) => updateRef(r.id, { note: e.target.value })}
                  placeholder="Ce que je fais différemment…"
                />
                <div className="mt-2 flex justify-end">
                  <ConfirmButton onConfirm={() => removeRef(r.id)}>Retirer</ConfirmButton>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      <div className="sticky bottom-4 flex items-center justify-end gap-3">
        {saved && <span className="text-sm text-accent-green">Enregistré ✓</span>}
        <button className="btn-primary shadow-glow" onClick={save}>Enregistrer</button>
      </div>
    </div>
  );
}
