import { useState } from 'react';
import { Link } from 'react-router-dom';

// Small async runner: tracks loading + error for one AI action.
export function useAsync() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const run = async (fn: () => Promise<void>) => {
    setLoading(true); setError('');
    try { await fn(); }
    catch (e) { setError((e as Error).message || 'Erreur.'); }
    finally { setLoading(false); }
  };
  return { loading, error, setError, run };
}

// Sparkle (IA) action button with a loading state.
export function Spark({
  onClick, children, loading, disabled, className = 'btn-ghost btn-sm',
}: {
  onClick: () => void; children: React.ReactNode;
  loading?: boolean; disabled?: boolean; className?: string;
}) {
  return (
    <button className={className} onClick={onClick} disabled={loading || disabled}>
      {loading ? <span className="animate-spin">◌</span> : <span>✨</span>}
      {children}
    </button>
  );
}

export function AIErrorText({ error }: { error: string }) {
  if (!error) return null;
  return <p className="mt-2 text-sm text-accent-red">⚠️ {error}</p>;
}

// Inline hint shown where AI would help but no key is configured.
export function AIHint() {
  return (
    <div className="rounded-lg border border-brand/30 bg-brand/5 px-3 py-2 text-xs text-slate-400">
      ✨ Active l'assistant IA dans les <Link to="/reglages" className="text-brand-soft underline">Réglages</Link> pour générer idées, scripts, titres et analyses automatiquement.
    </div>
  );
}
