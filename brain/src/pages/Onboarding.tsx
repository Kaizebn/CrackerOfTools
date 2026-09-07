import { useState } from 'react';
import { uid } from '../db/db';
import { savePositioning, saveSettings, logActivity } from '../lib/store';
import { Card, Field, Input, Select, ProgressBar } from '../components/ui';
import type { ContentFormat, Pillar } from '../db/types';

const PILLAR_COLORS = ['#7c5cff', '#2ecc9b', '#f5a623', '#3aa0ff', '#ff6ec7'];

export default function Onboarding({ onDone }: { onDone: () => void }) {
  const [step, setStep] = useState(0);

  // Positioning
  const [niche, setNiche] = useState('');
  const [audience, setAudience] = useState('');
  const [promise, setPromise] = useState('');
  const [tone, setTone] = useState('');
  const [dominantFormat, setDominantFormat] = useState<ContentFormat>('short');

  // Pillars
  const [pillarNames, setPillarNames] = useState<string[]>(['', '', '']);

  // Rhythm & goal
  const [longs, setLongs] = useState(1);
  const [shorts, setShorts] = useState(5);
  const [goalTarget, setGoalTarget] = useState(1000);

  const steps = ['Bienvenue', 'Positionnement', 'Piliers', 'Rythme', 'C\'est parti'];
  const progress = (step / (steps.length - 1)) * 100;

  const canNext = () => {
    if (step === 1) return niche.trim() && audience.trim() && promise.trim() && tone.trim();
    if (step === 2) return pillarNames.filter((p) => p.trim()).length >= 3;
    return true;
  };

  const finish = async () => {
    const pillars: Pillar[] = pillarNames
      .map((n) => n.trim())
      .filter(Boolean)
      .map((name, i) => ({ id: uid(), name, color: PILLAR_COLORS[i % PILLAR_COLORS.length] }));

    await savePositioning({ niche, audience, promise, tone, dominantFormat });
    await saveSettings({
      pillars,
      longsPerWeek: longs,
      shortsPerWeek: shorts,
      mainGoalTitle: `Atteindre ${goalTarget} abonnés`,
      mainGoalTarget: goalTarget,
      mainGoalUnit: 'abonnés',
      onboardingDone: true,
    });
    await logActivity('onboarding', 'Configuration initiale terminée');
    onDone();
  };

  const setPillar = (i: number, v: string) => {
    setPillarNames((arr) => arr.map((x, idx) => (idx === i ? v : x)));
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4">
      <div className="w-full max-w-xl">
        <div className="mb-4 flex items-center gap-2 text-2xl font-extrabold text-white">
          <span className="text-3xl">🧠</span> BRAIN
        </div>
        <Card>
          <div className="mb-5">
            <div className="mb-2 flex justify-between text-xs text-slate-500">
              <span>Étape {step + 1} / {steps.length}</span>
              <span>~5 min</span>
            </div>
            <ProgressBar value={progress} />
          </div>

          {step === 0 && (
            <div className="space-y-4">
              <h1 className="text-2xl font-bold text-white">Ton cerveau externe de créateur</h1>
              <p className="text-slate-400 leading-relaxed">
                BRAIN stocke ta stratégie, te dit quoi faire chaque jour, et mesure
                si ça marche. En 5 minutes, on pose les bases : ton positionnement,
                tes piliers de contenu et ton rythme cible.
              </p>
              <p className="text-sm text-slate-500">
                Tout est modifiable plus tard. Tes données restent sur ton appareil.
              </p>
            </div>
          )}

          {step === 1 && (
            <div className="space-y-4">
              <h1 className="text-xl font-bold text-white">Ton positionnement</h1>
              <Field label="Ta niche" required hint="Ex : la productivité, la cuisine rapide, le fitness maison">
                <Input value={niche} onChange={(e) => setNiche(e.target.value)} placeholder="Sur quoi tu fais du contenu ?" />
              </Field>
              <Field label="Ton audience cible" required hint="À qui tu parles précisément ?">
                <Input value={audience} onChange={(e) => setAudience(e.target.value)} placeholder="Ex : étudiants débordés de 18-25 ans" />
              </Field>
              <Field label="Ta promesse" required hint="Ce que le spectateur gagne en te regardant">
                <Input value={promise} onChange={(e) => setPromise(e.target.value)} placeholder="Ex : gagner 1h par jour sans stress" />
              </Field>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Ton ton" required>
                  <Input value={tone} onChange={(e) => setTone(e.target.value)} placeholder="Ex : direct et fun" />
                </Field>
                <Field label="Format dominant">
                  <Select value={dominantFormat} onChange={(e) => setDominantFormat(e.target.value as ContentFormat)}>
                    <option value="short">Short (vertical, court)</option>
                    <option value="long">Long (horizontal)</option>
                  </Select>
                </Field>
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-4">
              <h1 className="text-xl font-bold text-white">Tes piliers de contenu</h1>
              <p className="text-sm text-slate-400">
                3 à 5 thèmes récurrents autour desquels tourneront toutes tes vidéos.
                Ça évite de partir dans tous les sens.
              </p>
              <div className="space-y-2">
                {pillarNames.map((p, i) => (
                  <div key={i} className="flex items-center gap-2">
                    <span
                      className="h-4 w-4 shrink-0 rounded-full"
                      style={{ background: PILLAR_COLORS[i % PILLAR_COLORS.length] }}
                    />
                    <Input value={p} onChange={(e) => setPillar(i, e.target.value)} placeholder={`Pilier ${i + 1}`} />
                    {pillarNames.length > 3 && (
                      <button className="btn-ghost btn-sm" onClick={() => setPillarNames((a) => a.filter((_, idx) => idx !== i))}>✕</button>
                    )}
                  </div>
                ))}
              </div>
              {pillarNames.length < 5 && (
                <button className="btn-ghost btn-sm" onClick={() => setPillarNames((a) => [...a, ''])}>
                  + Ajouter un pilier
                </button>
              )}
            </div>
          )}

          {step === 3 && (
            <div className="space-y-4">
              <h1 className="text-xl font-bold text-white">Ton rythme cible</h1>
              <p className="text-sm text-slate-400">Combien de vidéos par semaine tu veux tenir ? Reste réaliste.</p>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Vidéos longues / semaine">
                  <Input type="number" min={0} value={longs} onChange={(e) => setLongs(+e.target.value)} />
                </Field>
                <Field label="Shorts / semaine">
                  <Input type="number" min={0} value={shorts} onChange={(e) => setShorts(+e.target.value)} />
                </Field>
              </div>
              <Field label="Ton objectif principal (abonnés visés)" hint="Un premier cap à atteindre">
                <Input type="number" min={1} value={goalTarget} onChange={(e) => setGoalTarget(+e.target.value)} />
              </Field>
            </div>
          )}

          {step === 4 && (
            <div className="space-y-4">
              <h1 className="text-xl font-bold text-white">Tout est prêt 🎉</h1>
              <p className="text-slate-400 leading-relaxed">
                Ton cerveau est configuré. Sur l'écran d'accueil, tu verras chaque
                jour tes 3 actions prioritaires. Commence par remplir ta banque
                d'idées, puis fais avancer ta première vidéo.
              </p>
            </div>
          )}

          <div className="mt-6 flex items-center justify-between">
            <button
              className="btn-ghost"
              onClick={() => setStep((s) => Math.max(0, s - 1))}
              disabled={step === 0}
            >
              Retour
            </button>
            {step < steps.length - 1 ? (
              <button className="btn-primary" onClick={() => setStep((s) => s + 1)} disabled={!canNext()}>
                Continuer
              </button>
            ) : (
              <button className="btn-primary" onClick={finish}>Lancer BRAIN</button>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
