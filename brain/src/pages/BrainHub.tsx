import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  useSettings, usePositioning, useItems, useLearning, useActivity,
} from '../lib/hooks';
import { generateActions, generateAlerts } from '../lib/today';
import { computeStreak } from '../lib/streak';
import { published } from '../lib/analysis';
import { positioningComplete } from '../lib/store';
import { pct } from '../lib/format';
import BrainArt from '../components/BrainArt';
import type { Item } from '../db/types';

interface Branch {
  to: string; label: string; icon: string; color: string;
  badge: (ctx: BranchCtx) => { text: string; alert?: boolean } | null;
}
interface BranchCtx {
  items: Item[];
  reserve: number;
  positioningOk: boolean;
  learningDone: number;
  learningTotal: number;
}

const BRANCHES: Branch[] = [
  { to: '/positionnement', label: 'Positionnement', icon: '🎯', color: '#ff5c72',
    badge: (c) => (c.positioningOk ? { text: '✓' } : { text: '!', alert: true }) },
  { to: '/idees', label: 'Idées', icon: '💡', color: '#f5a623',
    badge: (c) => ({ text: `${c.reserve}`, alert: c.reserve < 10 }) },
  { to: '/ecriture', label: 'Écriture', icon: '✍️', color: '#3aa0ff',
    badge: (c) => { const n = c.items.filter((i) => i.status === 'validated').length; return n ? { text: `${n}` } : null; } },
  { to: '/production', label: 'Production', icon: '🎬', color: '#2ecc9b',
    badge: (c) => { const n = c.items.filter((i) => ['script', 'filmed', 'edited'].includes(i.status)).length; return n ? { text: `${n}` } : null; } },
  { to: '/publication', label: 'Publication', icon: '📅', color: '#7c5cff',
    badge: (c) => { const n = c.items.filter((i) => i.status === 'edited').length; return n ? { text: `${n}`, alert: true } : null; } },
  { to: '/analyse', label: 'Analyse', icon: '📊', color: '#38c6d9',
    badge: (c) => { const n = published(c.items).length; return n ? { text: `${n}` } : null; } },
  { to: '/monetisation', label: 'Monétisation', icon: '💰', color: '#ffce54',
    badge: () => null },
  { to: '/progression', label: 'Progression', icon: '🚀', color: '#ff6ec7',
    badge: (c) => ({ text: `${c.learningDone}/${c.learningTotal}` }) },
];

// Node coordinates in a 0..1000 square, evenly spread on a circle (top-first).
const R = 385, C = 500;
const NODES = BRANCHES.map((b, i) => {
  const angle = (-90 + i * (360 / BRANCHES.length)) * (Math.PI / 180);
  return { ...b, x: C + R * Math.cos(angle), y: C + R * Math.sin(angle) };
});

export default function BrainHub() {
  const navigate = useNavigate();
  const settings = useSettings();
  const positioning = usePositioning();
  const items = useItems();
  const learning = useLearning();
  const activity = useActivity();
  const [panelOpen, setPanelOpen] = useState(false);

  const streak = computeStreak(activity);
  const goalPct = pct(settings.mainGoalCurrent, settings.mainGoalTarget);
  const ctx: BranchCtx = {
    items,
    reserve: items.filter((i) => i.status !== 'published').length,
    positioningOk: positioningComplete(positioning),
    learningDone: learning.filter((s) => s.done).length,
    learningTotal: learning.length || 7,
  };

  const actions = generateActions({ settings, positioning, items, learning });
  const alerts = generateAlerts({ settings, positioning, items, learning });

  // Goal ring geometry (radius 150 around the 1000-space center).
  const ringR = 150;
  const ringC = 2 * Math.PI * ringR;

  return (
    <div className="hub-bg min-h-screen w-full overflow-x-hidden">
      {/* Top bar */}
      <div className="flex items-center justify-between px-5 py-4">
        <div className="flex items-center gap-2 text-lg font-extrabold text-white">
          <span className="text-2xl">🧠</span> BRAIN
        </div>
        <div className="flex items-center gap-2">
          <div className="rounded-full border border-ink-700 bg-ink-900/70 px-3 py-1.5 text-sm font-bold text-accent-amber">
            🔥 {streak} <span className="font-medium text-slate-500">série</span>
          </div>
          <button onClick={() => navigate('/reglages')} className="btn-ghost btn-sm" title="Réglages">⚙️</button>
        </div>
      </div>

      {/* Hub */}
      <div className="flex flex-col items-center px-4 pb-10">
        <p className="mb-2 text-center text-sm text-slate-400">
          Appuie sur le cerveau pour voir <b className="text-slate-200">quoi faire maintenant</b> — ou choisis une branche.
        </p>

        <div className="relative mx-auto aspect-square w-full max-w-[620px]">
          {/* Connector lines */}
          <svg viewBox="0 0 1000 1000" className="absolute inset-0 h-full w-full overflow-visible">
            {NODES.map((n) => (
              <line
                key={n.to}
                x1={C} y1={C} x2={n.x} y2={n.y}
                stroke={n.color} strokeOpacity={0.5} strokeWidth={3}
                className="synapse"
              />
            ))}
          </svg>

          {/* Center brain button */}
          <button
            onClick={() => setPanelOpen(true)}
            className="absolute left-1/2 top-1/2 z-20 flex aspect-square w-[34%] items-center justify-center rounded-full"
            style={{ transform: 'translate(-50%, -50%)' }}
            aria-label="Voir mes priorités du jour"
          >
            {/* goal ring */}
            <svg viewBox="0 0 1000 1000" className="absolute inset-0 h-full w-full -rotate-90">
              <circle cx="500" cy="500" r={ringR} fill="none" stroke="#232838" strokeWidth="26" />
              <circle
                cx="500" cy="500" r={ringR} fill="none" stroke="#2ecc9b" strokeWidth="26" strokeLinecap="round"
                strokeDasharray={ringC} strokeDashoffset={ringC * (1 - goalPct / 100)}
              />
            </svg>
            <BrainArt className="brain-art relative z-10 w-[78%]" />
            <span className="absolute bottom-[6%] left-1/2 -translate-x-1/2 rounded-full bg-ink-950/80 px-2 py-0.5 text-[10px] font-semibold text-slate-300">
              {goalPct}% objectif
            </span>
          </button>

          {/* Branch nodes */}
          {NODES.map((n) => {
            const badge = n.badge(ctx);
            return (
              <button
                key={n.to}
                onClick={() => navigate(n.to)}
                className="hub-node group absolute z-10"
                style={{ left: `${n.x / 10}%`, top: `${n.y / 10}%` }}
              >
                <span className="relative mx-auto flex flex-col items-center">
                  <span
                    className="hub-neuron flex h-14 w-14 items-center justify-center rounded-full border text-2xl shadow-lg transition-transform duration-200 sm:h-16 sm:w-16"
                    style={{
                      background: `radial-gradient(circle at 35% 30%, ${n.color}cc, ${n.color}66)`,
                      borderColor: `${n.color}`,
                      boxShadow: `0 0 20px -4px ${n.color}aa`,
                    }}
                  >
                    {n.icon}
                  </span>
                  {badge && (
                    <span
                      className={`absolute -right-1 -top-1 min-w-[20px] rounded-full px-1.5 py-0.5 text-center text-[11px] font-bold ${
                        badge.alert ? 'bg-accent-red text-white' : 'bg-ink-800 text-slate-200 border border-ink-600'
                      }`}
                    >
                      {badge.text}
                    </span>
                  )}
                  <span className="mt-1.5 whitespace-nowrap text-[11px] font-semibold text-slate-300 sm:text-xs">
                    {n.label}
                  </span>
                </span>
              </button>
            );
          })}
        </div>

        {/* Goal caption */}
        <div className="mt-2 text-center text-sm text-slate-500">
          {settings.mainGoalTitle} — <span className="text-slate-300">{settings.mainGoalCurrent}/{settings.mainGoalTarget} {settings.mainGoalUnit}</span>
        </div>
      </div>

      {/* Priorities panel */}
      {panelOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4" onMouseDown={() => setPanelOpen(false)}>
          <div
            className="w-full max-w-md rounded-2xl border border-ink-700 bg-ink-900 p-5 shadow-glow"
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-lg font-extrabold text-white">🧠 Quoi faire maintenant</h2>
              <button className="btn-ghost btn-sm" onClick={() => setPanelOpen(false)}>✕</button>
            </div>

            <div className="space-y-2">
              {actions.map((a, i) => (
                <button
                  key={a.id}
                  onClick={() => { setPanelOpen(false); navigate(a.to); }}
                  className={`flex w-full items-start gap-3 rounded-xl border p-3 text-left transition-colors ${
                    a.tone === 'urgent' ? 'border-accent-red/40 bg-accent-red/5'
                    : a.tone === 'good' ? 'border-accent-green/40 bg-accent-green/5'
                    : 'border-brand/40 bg-brand/5'
                  }`}
                >
                  <span className="text-lg font-extrabold text-slate-600">{i + 1}</span>
                  <span className="min-w-0">
                    <span className="block font-bold text-white">{a.title}</span>
                    <span className="block text-sm text-slate-400">{a.detail}</span>
                  </span>
                </button>
              ))}
            </div>

            {alerts.length > 0 && (
              <div className="mt-3 space-y-1.5">
                {alerts.map((al) => (
                  <button
                    key={al.id}
                    onClick={() => { setPanelOpen(false); navigate(al.to); }}
                    className={`flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm ${
                      al.level === 'warn' ? 'bg-accent-amber/10 text-accent-amber' : 'bg-ink-850 text-slate-300'
                    }`}
                  >
                    <span>{al.level === 'warn' ? '⚠️' : 'ℹ️'}</span>
                    <span className="flex-1">{al.text}</span>
                    <span className="opacity-60">→</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
