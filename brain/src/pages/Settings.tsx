import { useEffect, useRef, useState } from 'react';
import { useSettings } from '../lib/hooks';
import { saveSettings } from '../lib/store';
import { uid } from '../db/db';
import {
  Card, Field, Input, Select, SectionTitle, ConfirmButton,
} from '../components/ui';
import { useAsync, Spark, AIErrorText } from '../components/ai';
import { AI_MODELS, aiTest } from '../lib/ai';
import { downloadBackup, importFromFile, wipeAll } from '../lib/backup';
import type { Settings as S, Pillar } from '../db/types';

const PILLAR_COLORS = ['#7c5cff', '#2ecc9b', '#f5a623', '#3aa0ff', '#ff6ec7', '#ff5c72', '#9b82ff'];

export default function SettingsPage() {
  const stored = useSettings();
  const [form, setForm] = useState<S>(stored);
  const [saved, setSaved] = useState(false);
  const [msg, setMsg] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => { setForm(stored); }, [stored.id, stored.mainGoalTitle, stored.pillars.length]); // eslint-disable-line

  const set = <K extends keyof S>(k: K, v: S[K]) => setForm((f) => ({ ...f, [k]: v }));

  const save = async () => {
    await saveSettings(form);
    setSaved(true);
    setTimeout(() => setSaved(false), 1500);
  };

  const addPillar = () => {
    if (form.pillars.length >= 5) return;
    const p: Pillar = { id: uid(), name: '', color: PILLAR_COLORS[form.pillars.length % PILLAR_COLORS.length] };
    set('pillars', [...form.pillars, p]);
  };
  const updatePillar = (id: string, patch: Partial<Pillar>) =>
    set('pillars', form.pillars.map((p) => (p.id === id ? { ...p, ...patch } : p)));
  const removePillar = (id: string) => set('pillars', form.pillars.filter((p) => p.id !== id));

  const onImport = async (f: File | undefined) => {
    if (!f) return;
    try {
      await importFromFile(f);
      setMsg('Sauvegarde importée ✓ (recharge la page si besoin)');
    } catch (e) {
      setMsg('Erreur : ' + (e as Error).message);
    }
    setTimeout(() => setMsg(''), 4000);
  };

  const reset = async () => {
    await wipeAll();
    location.reload();
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold text-white">⚙️ Réglages</h1>
        <p className="text-sm text-slate-500">Objectif, piliers, rythme et sauvegardes.</p>
      </div>

      <Card className="space-y-4">
        <SectionTitle>Objectif principal</SectionTitle>
        <Field label="Intitulé">
          <Input value={form.mainGoalTitle} onChange={(e) => set('mainGoalTitle', e.target.value)} />
        </Field>
        <div className="grid grid-cols-3 gap-3">
          <Field label="Actuel"><Input type="number" value={form.mainGoalCurrent} onChange={(e) => set('mainGoalCurrent', +e.target.value)} /></Field>
          <Field label="Cible"><Input type="number" value={form.mainGoalTarget} onChange={(e) => set('mainGoalTarget', +e.target.value)} /></Field>
          <Field label="Unité"><Input value={form.mainGoalUnit} onChange={(e) => set('mainGoalUnit', e.target.value)} /></Field>
        </div>
      </Card>

      <Card className="space-y-4">
        <SectionTitle right={form.pillars.length < 5 ? <button className="btn-ghost btn-sm" onClick={addPillar}>+ Pilier</button> : undefined}>
          Piliers de contenu
        </SectionTitle>
        <p className="text-sm text-slate-500 -mt-2">3 à 5 thèmes récurrents. Chaque idée sera rattachée à un pilier.</p>
        <div className="space-y-2">
          {form.pillars.map((p) => (
            <div key={p.id} className="flex items-center gap-2">
              <input
                type="color"
                value={p.color}
                onChange={(e) => updatePillar(p.id, { color: e.target.value })}
                className="h-9 w-9 shrink-0 cursor-pointer rounded border border-ink-700 bg-ink-850"
              />
              <Input value={p.name} onChange={(e) => updatePillar(p.id, { name: e.target.value })} placeholder="Nom du pilier" />
              <button className="btn-ghost btn-sm" onClick={() => removePillar(p.id)}>✕</button>
            </div>
          ))}
          {form.pillars.length === 0 && <p className="text-sm text-slate-600 italic">Aucun pilier.</p>}
        </div>
      </Card>

      <Card className="space-y-4">
        <SectionTitle>Rythme cible</SectionTitle>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Vidéos longues / semaine"><Input type="number" min={0} value={form.longsPerWeek} onChange={(e) => set('longsPerWeek', +e.target.value)} /></Field>
          <Field label="Shorts / semaine"><Input type="number" min={0} value={form.shortsPerWeek} onChange={(e) => set('shortsPerWeek', +e.target.value)} /></Field>
        </div>
      </Card>

      <div className="sticky bottom-4 flex items-center justify-end gap-3">
        {saved && <span className="text-sm text-accent-green">Enregistré ✓</span>}
        <button className="btn-primary shadow-glow" onClick={save}>Enregistrer les réglages</button>
      </div>

      <AICard form={form} set={set} />

      <Card className="space-y-4">
        <SectionTitle>Sauvegarde des données</SectionTitle>
        <p className="text-sm text-slate-500 -mt-2">
          Tes données vivent uniquement dans ce navigateur. Exporte régulièrement un
          fichier JSON pour ne rien perdre (changement d'appareil, nettoyage du navigateur…).
        </p>
        <div className="flex flex-wrap gap-2">
          <button className="btn-primary" onClick={() => downloadBackup()}>⬇️ Exporter (JSON)</button>
          <button className="btn-ghost" onClick={() => fileRef.current?.click()}>⬆️ Importer (JSON)</button>
          <input ref={fileRef} type="file" accept="application/json" className="hidden" onChange={(e) => onImport(e.target.files?.[0])} />
        </div>
        {msg && <p className="text-sm text-brand-soft">{msg}</p>}
        <p className="text-xs text-accent-amber">⚠️ L'import remplace toutes les données actuelles.</p>
      </Card>

      <Card className="space-y-3">
        <SectionTitle>Zone sensible</SectionTitle>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="text-sm font-medium text-slate-200">Tout réinitialiser</div>
            <div className="text-xs text-slate-500">Efface toutes les données et relance l'assistant de démarrage.</div>
          </div>
          <ConfirmButton onConfirm={reset}>Réinitialiser</ConfirmButton>
        </div>
      </Card>
    </div>
  );
}

function AICard({ form, set }: { form: S; set: <K extends keyof S>(k: K, v: S[K]) => void }) {
  const { loading, error, run } = useAsync();
  const [ok, setOk] = useState('');
  const test = () =>
    run(async () => {
      setOk('');
      await aiTest(form);
      setOk('Connexion réussie ✓');
    });
  return (
    <Card className="space-y-4">
      <SectionTitle>✨ Assistant IA (optionnel)</SectionTitle>
      <p className="-mt-2 text-sm text-slate-500">
        Branche BRAIN sur Claude pour générer des idées, des scripts, des titres et
        des analyses. Ta clé est stockée <b>uniquement sur cet appareil</b> et n'est
        envoyée qu'à Anthropic.
      </p>
      <Field label="Clé API Anthropic" hint="Se crée sur console.anthropic.com → API keys. Commence par sk-ant-…">
        <Input
          type="password"
          value={form.aiApiKey ?? ''}
          onChange={(e) => set('aiApiKey', e.target.value)}
          placeholder="sk-ant-..."
          autoComplete="off"
        />
      </Field>
      <Field label="Modèle" hint="Pour débuter et dépenser le moins, choisis Haiku.">
        <Select value={form.aiModel || 'claude-opus-5'} onChange={(e) => set('aiModel', e.target.value)}>
          {AI_MODELS.map((m) => <option key={m.id} value={m.id}>{m.label}</option>)}
        </Select>
      </Field>
      <div className="flex items-center gap-3">
        <Spark onClick={test} loading={loading} disabled={!form.aiApiKey?.trim()} className="btn-ghost">
          Tester la connexion
        </Spark>
        {ok && <span className="text-sm text-accent-green">{ok}</span>}
      </div>
      <AIErrorText error={error} />
      <p className="text-xs text-accent-amber">
        ⚠️ Chaque génération consomme des crédits payants sur ton compte Anthropic
        (quelques centimes). N'oublie pas d'enregistrer les réglages après avoir collé ta clé.
      </p>
    </Card>
  );
}
