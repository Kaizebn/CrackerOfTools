import { useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';
import { useLiveQuery } from 'dexie-react-hooks';
import { db } from '../db/db';
import { positioningComplete } from '../lib/store';
import { defaultPositioning } from '../db/defaults';

interface NavItem {
  to: string;
  label: string;
  icon: string;
  branch?: string;
}

const NAV: NavItem[] = [
  { to: '/', label: 'Aujourd\'hui', icon: '🧠', branch: 'Noyau' },
  { to: '/positionnement', label: 'Positionnement', icon: '🎯', branch: '1' },
  { to: '/idees', label: 'Idées', icon: '💡', branch: '2' },
  { to: '/ecriture', label: 'Écriture', icon: '✍️', branch: '3' },
  { to: '/production', label: 'Production', icon: '🎬', branch: '4' },
  { to: '/publication', label: 'Publication', icon: '📅', branch: '5' },
  { to: '/analyse', label: 'Analyse', icon: '📊', branch: '6' },
  { to: '/monetisation', label: 'Monétisation', icon: '💰', branch: '7' },
  { to: '/progression', label: 'Progression', icon: '🚀', branch: '8' },
  { to: '/reglages', label: 'Réglages', icon: '⚙️' },
];

export default function Layout() {
  const [open, setOpen] = useState(false);
  const positioning = useLiveQuery(() => db.positioning.get(1), []) ?? defaultPositioning();
  const items = useLiveQuery(() => db.items.toArray(), []) ?? [];

  const locked = !positioningComplete(positioning);
  const reserveCount = items.filter((i) => i.status !== 'published').length;

  const badgeFor = (to: string): string | null => {
    if (to === '/positionnement' && locked) return '!';
    if (to === '/idees' && reserveCount < 10) return String(reserveCount);
    return null;
  };

  return (
    <div className="min-h-screen lg:flex">
      {/* Mobile top bar */}
      <header className="sticky top-0 z-30 flex items-center justify-between border-b border-ink-700 bg-ink-950/95 px-4 py-3 backdrop-blur lg:hidden">
        <div className="flex items-center gap-2 font-extrabold text-white">
          <span className="text-xl">🧠</span> BRAIN
        </div>
        <button className="btn-ghost btn-sm" onClick={() => setOpen((v) => !v)}>
          {open ? '✕' : '☰'} Menu
        </button>
      </header>

      {/* Sidebar */}
      <aside
        className={`${open ? 'block' : 'hidden'} lg:block lg:sticky lg:top-0 lg:h-screen w-full lg:w-60 shrink-0 border-r border-ink-700 bg-ink-900/60`}
      >
        <div className="hidden lg:flex items-center gap-2 px-5 py-5 text-xl font-extrabold text-white">
          <span className="text-2xl">🧠</span> BRAIN
        </div>
        <nav className="flex flex-col gap-0.5 p-3">
          {NAV.map((item) => {
            const badge = badgeFor(item.to);
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.to === '/'}
                onClick={() => setOpen(false)}
                className={({ isActive }) =>
                  `group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                    isActive
                      ? 'bg-brand/20 text-white'
                      : 'text-slate-400 hover:bg-ink-800 hover:text-slate-100'
                  }`
                }
              >
                <span className="text-base w-5 text-center">{item.icon}</span>
                <span className="flex-1">{item.label}</span>
                {badge && (
                  <span
                    className={`min-w-[20px] rounded-full px-1.5 py-0.5 text-center text-[11px] font-bold ${
                      badge === '!' ? 'bg-accent-red text-white' : 'bg-ink-700 text-slate-300'
                    }`}
                  >
                    {badge}
                  </span>
                )}
              </NavLink>
            );
          })}
        </nav>
        <div className="px-5 py-4 text-[11px] leading-relaxed text-slate-600">
          Tes données restent sur cet appareil. Pense à exporter une sauvegarde
          régulièrement (Réglages).
        </div>
      </aside>

      {/* Main content */}
      <main className="min-w-0 flex-1">
        <div className="mx-auto max-w-5xl px-4 py-6 sm:px-6 sm:py-8">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
