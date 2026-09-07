import { useState } from 'react';
import { useLearning, useJournal } from '../lib/hooks';
import { logActivity } from '../lib/store';
import { db, uid, todayISO } from '../db/db';
import { Card, Textarea, ProgressBar, ConfirmButton, Badge } from '../components/ui';
import { fmtDate, pct } from '../lib/format';
import type { LearningStep } from '../db/types';

export default function Progression() {
  const steps = useLearning();
  const journal = useJournal();
  const [text, setText] = useState('');

  const doneCount = steps.filter((s) => s.done).length;
  const progress = pct(doneCount, steps.length);
  // A step unlocks once all previous steps are done.
  const firstUndone = steps.findIndex((s) => !s.done);

  const toggle = async (step: LearningStep) => {
    await db.learning.put({ ...step, done: !step.done });
    if (!step.done) await logActivity('learning', `Étape apprise : ${step.title}`);
  };

  const addJournal = async () => {
    if (!text.trim()) return;
    await db.journal.add({ id: uid(), date: todayISO(), text: text.trim(), createdAt: Date.now() });
    await logActivity('journal', 'Note de journal ajoutée');
    setText('');
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold text-white">🚀 Progression</h1>
        <p className="text-sm text-slate-500">Ton parcours d'apprentissage et ton journal.</p>
      </div>

      <Card>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="section-title">Parcours d'apprentissage</h2>
          <span className="text-sm text-slate-500">{doneCount}/{steps.length} étapes</span>
        </div>
        <ProgressBar value={progress} className="mb-4" />

        <div className="space-y-2">
          {steps.map((s, idx) => {
            const locked = idx > firstUndone && firstUndone !== -1;
            return (
              <div
                key={s.id}
                className={`rounded-lg border p-3 transition-opacity ${
                  s.done ? 'border-accent-green/40 bg-accent-green/5' : 'border-ink-700 bg-ink-850'
                } ${locked ? 'opacity-50' : ''}`}
              >
                <div className="flex items-start gap-3">
                  <button
                    onClick={() => !locked && toggle(s)}
                    disabled={locked}
                    className={`mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 text-sm ${
                      s.done ? 'border-accent-green bg-accent-green text-ink-950' : 'border-ink-600 text-transparent'
                    } ${locked ? 'cursor-not-allowed' : 'hover:border-brand'}`}
                    aria-label="Marquer comme fait"
                  >
                    ✓
                  </button>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-white">{idx + 1}. {s.title}</span>
                      {locked && <Badge color="slate">🔒 Verrouillé</Badge>}
                      {s.done && <Badge color="green">Terminé</Badge>}
                    </div>
                    {!locked && (
                      <div className="mt-1.5 space-y-1 text-sm">
                        <p className="text-slate-300"><span className="text-slate-500">🎯 Objectif :</span> {s.goal}</p>
                        <p className="text-slate-400"><span className="text-slate-500">📚 Ressource :</span> {s.resource}</p>
                        <p className="text-slate-400"><span className="text-slate-500">✍️ Exercice :</span> {s.exercise}</p>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </Card>

      <Card>
        <h2 className="section-title mb-3">Journal personnel</h2>
        <div className="mb-4">
          <Textarea value={text} onChange={(e) => setText(e.target.value)} placeholder="Qu'as-tu appris cette semaine ?" />
          <div className="mt-2 flex justify-end">
            <button className="btn-primary" onClick={addJournal}>Ajouter au journal</button>
          </div>
        </div>

        {journal.length === 0 ? (
          <p className="text-sm text-slate-600 italic">Ton journal est vide. Note tes prises de conscience, même petites.</p>
        ) : (
          <div className="space-y-2">
            {journal.map((j) => (
              <div key={j.id} className="group rounded-lg border border-ink-700 bg-ink-850 p-3">
                <div className="mb-1 flex items-center justify-between">
                  <span className="text-xs text-slate-500">{fmtDate(j.date)}</span>
                  <ConfirmButton className="btn-danger btn-sm opacity-0 group-hover:opacity-100" onConfirm={() => db.journal.delete(j.id)}>Supprimer</ConfirmButton>
                </div>
                <p className="whitespace-pre-wrap text-sm text-slate-200">{j.text}</p>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
