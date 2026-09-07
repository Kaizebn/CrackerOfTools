export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso.length <= 10 ? iso + 'T00:00:00' : iso);
  if (isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' });
}

export function fmtDateTime(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '—';
  return d.toLocaleString('fr-FR', {
    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  });
}

export function fmtNumber(n: number): string {
  return new Intl.NumberFormat('fr-FR').format(Math.round(n));
}

export function fmtMinutes(min: number): string {
  if (!min) return '0 min';
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  if (h === 0) return `${m} min`;
  if (m === 0) return `${h} h`;
  return `${h} h ${m}`;
}

export function daysBetween(a: Date, b: Date): number {
  const ms = 24 * 3600 * 1000;
  const da = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
  const dbb = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((dbb - da) / ms);
}

export function pct(part: number, whole: number): number {
  if (whole <= 0) return 0;
  return Math.min(100, Math.round((part / whole) * 100));
}
