import { Link, Outlet, useLocation } from 'react-router-dom';

// Branch metadata for the header (label + icon per route).
const BRANCH: Record<string, { label: string; icon: string }> = {
  '/positionnement': { label: 'Positionnement', icon: '🎯' },
  '/idees': { label: 'Idées', icon: '💡' },
  '/ecriture': { label: 'Écriture', icon: '✍️' },
  '/production': { label: 'Production', icon: '🎬' },
  '/publication': { label: 'Publication', icon: '📅' },
  '/analyse': { label: 'Analyse', icon: '📊' },
  '/monetisation': { label: 'Monétisation', icon: '💰' },
  '/progression': { label: 'Progression', icon: '🚀' },
  '/reglages': { label: 'Réglages', icon: '⚙️' },
};

export default function Layout() {
  const { pathname } = useLocation();
  const current = BRANCH[pathname] ?? { label: '', icon: '🧠' };

  return (
    <div className="min-h-screen">
      {/* Slim immersive top bar: back to the brain, current branch, settings */}
      <header className="sticky top-0 z-30 border-b border-ink-700 bg-ink-950/90 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-3 sm:px-6">
          <Link to="/" className="btn-ghost btn-sm">
            <span className="text-base">🧠</span> Cerveau
          </Link>
          <div className="flex items-center gap-2 font-bold text-white">
            <span>{current.icon}</span>
            <span className="text-sm sm:text-base">{current.label}</span>
          </div>
          <Link
            to="/reglages"
            className={`btn-ghost btn-sm ${pathname === '/reglages' ? 'opacity-40 pointer-events-none' : ''}`}
            title="Réglages"
          >
            ⚙️
          </Link>
        </div>
      </header>

      <main className="mx-auto max-w-5xl px-4 py-6 sm:px-6 sm:py-8">
        <Outlet />
      </main>
    </div>
  );
}
