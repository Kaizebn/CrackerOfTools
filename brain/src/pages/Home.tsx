import { Link } from 'react-router-dom';
import {
  useSettings, usePositioning, useItems, useLearning, useActivity,
} from '../lib/hooks';
import { generateActions, generateAlerts, daysSinceLastPublish } from '../lib/today';
import { computeStreak } from '../lib/streak';
import { published } from '../lib/analysis';
import { Card, ProgressBar, Stat, Badge } from '../components/ui';
import { pct } from '../lib/format';
import { logActivity } from '../lib/store';

const toneStyles: Record<string, string> = {
  urgent: 'border-accent-red/40 bg-accent-red/5',
  normal: 'border-brand/40 bg-brand/5',
  good: 'border-accent-green/40 bg-accent-green/5',
};
const toneBadge: Record<string, 'red' | 'brand' | 'green'> = {
  urgent: 'red', normal: 'brand', good: 'green',
};

export default function Home() {
  const settings = useSettings();
  const positioning = usePositioning();
  const items = useItems();
  const learning = useLearning();
  const activity = useActivity();

  const ctx = { settings, positioning, items, learning };
  const actions = generateActions(ctx);
  const alerts = generateAlerts(ctx);
  const streak = computeStreak(activity);

  const pubCount = published(items).length;
  const reserveCount = items.filter((i) => i.status !== 'published').length;
  const since = daysSinceLastPublish(items);

  const goalPct = pct(settings.mainGoalCurrent, settings.mainGoalTarget);

  // Recent lessons surfaced on the home screen.
  const recentLessons = published(items)
    .filter((i) => i.lessonWorked || i.lessonFailed)
    .sort((a, b) => (b.publishedAt || '').localeCompare(a.publishedAt || ''))
    .slice(0, 3);

  const markLearned = async () => {
    await logActivity('manual', 'Action manuelle validée');
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-white">Aujourd'hui</h1>
          <p className="text-sm text-slate-500">Ta question du jour : je fais quoi maintenant ?</p>
        </div>
        <div className="flex items-center gap-2">
          <div className="rounded-xl border border-ink-700 bg-ink-900 px-4 py-2 text-center">
            <div className="text-2xl font-extrabold text-accent-amber leading-none">
              🔥 {streak}
            </div>
            <div className="text-[11px] uppercase tracking-wide text-slate-500">
              jour{streak > 1 ? 's' : ''} de série
            </div>
          </div>
        </div>
      </div>

      {/* Priority actions */}
      <section>
        <h2 className="mb-3 text-sm font-bold uppercase tracking-wide text-slate-400">
          Tes 3 priorités
        </h2>
        <div className="grid gap-3 sm:grid-cols-3">
          {actions.map((a, i) => (
            <Link
              key={a.id}
              to={a.to}
              onClick={markLearned}
              className={`block rounded-xl border p-4 transition-transform hover:-translate-y-0.5 ${toneStyles[a.tone]}`}
            >
              <div className="mb-2 flex items-center justify-between">
                <span className="text-lg font-extrabold text-slate-600">#{i + 1}</span>
                <Badge color={toneBadge[a.tone]}>
                  {a.tone === 'urgent' ? 'Urgent' : a.tone === 'good' ? 'Bonus' : 'À faire'}
                </Badge>
              </div>
              <div className="font-bold text-white leading-snug">{a.title}</div>
              <p className="mt-1 text-sm text-slate-400">{a.detail}</p>
              <div className="mt-3 text-xs font-semibold text-brand-soft">Y aller →</div>
            </Link>
          ))}
        </div>
      </section>

      {/* Goal + stats */}
      <section className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <div className="mb-1 flex items-center justify-between">
            <h3 className="font-bold text-white">Objectif principal</h3>
            <Link to="/reglages" className="text-xs text-slate-500 hover:text-slate-300">Modifier</Link>
          </div>
          <p className="text-sm text-slate-400">{settings.mainGoalTitle}</p>
          <div className="mt-3 mb-1.5 flex items-end justify-between">
            <span className="text-2xl font-extrabold text-white tabular-nums">
              {settings.mainGoalCurrent}
              <span className="text-sm font-medium text-slate-500"> / {settings.mainGoalTarget} {settings.mainGoalUnit}</span>
            </span>
            <span className="text-sm font-bold text-brand-soft">{goalPct}%</span>
          </div>
          <ProgressBar value={goalPct} />
        </Card>

        <div className="grid grid-cols-2 gap-3">
          <Stat label="Publiées" value={pubCount} />
          <Stat label="En réserve" value={reserveCount} />
          <Stat label="Dernière pub." value={since === null ? '—' : `${since}j`} sub={since === null ? 'jamais' : 'il y a'} />
          <Stat label="Piliers" value={settings.pillars.length} />
        </div>
      </section>

      {/* Alerts */}
      {alerts.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-slate-400">Alertes</h2>
          <div className="space-y-2">
            {alerts.map((al) => (
              <Link
                key={al.id}
                to={al.to}
                className={`flex items-center gap-3 rounded-lg border px-4 py-2.5 text-sm ${
                  al.level === 'warn'
                    ? 'border-accent-amber/40 bg-accent-amber/5 text-accent-amber'
                    : 'border-ink-700 bg-ink-900 text-slate-300'
                }`}
              >
                <span>{al.level === 'warn' ? '⚠️' : 'ℹ️'}</span>
                <span className="flex-1">{al.text}</span>
                <span className="text-xs opacity-70">→</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* Recent lessons */}
      {recentLessons.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-slate-400">Tes dernières leçons</h2>
          <div className="grid gap-3 sm:grid-cols-3">
            {recentLessons.map((i) => (
              <Card key={i.id} className="text-sm">
                <div className="mb-1 font-semibold text-white truncate">{i.finalTitle || i.title || 'Sans titre'}</div>
                {i.lessonWorked && <p className="text-accent-green">✅ {i.lessonWorked}</p>}
                {i.lessonFailed && <p className="mt-1 text-accent-red">❌ {i.lessonFailed}</p>}
              </Card>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
