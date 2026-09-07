import React, { useEffect, useState } from 'react';

export function Card({ className = '', children }: { className?: string; children: React.ReactNode }) {
  return <div className={`card card-pad ${className}`}>{children}</div>;
}

export function SectionTitle({ children, right }: { children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 mb-3">
      <h2 className="section-title">{children}</h2>
      {right}
    </div>
  );
}

export function Field({
  label, hint, required, children,
}: { label: string; hint?: string; required?: boolean; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="label">
        {label} {required && <span className="text-accent-red">*</span>}
      </span>
      {children}
      {hint && <span className="mt-1 block text-xs text-slate-500">{hint}</span>}
    </label>
  );
}

type InputProps = React.InputHTMLAttributes<HTMLInputElement>;
export function Input(props: InputProps) {
  return <input {...props} className={`input ${props.className || ''}`} />;
}

type TextareaProps = React.TextareaHTMLAttributes<HTMLTextAreaElement>;
export function Textarea(props: TextareaProps) {
  return <textarea {...props} className={`input min-h-[80px] resize-y ${props.className || ''}`} />;
}

type SelectProps = React.SelectHTMLAttributes<HTMLSelectElement>;
export function Select(props: SelectProps) {
  return <select {...props} className={`input ${props.className || ''}`} />;
}

export function EmptyState({
  icon = '✨', title, hint, action,
}: { icon?: string; title: string; hint?: string; action?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-ink-700 bg-ink-900/50 px-6 py-10 text-center">
      <div className="text-3xl mb-2">{icon}</div>
      <div className="font-semibold text-slate-200">{title}</div>
      {hint && <p className="mt-1 max-w-sm text-sm text-slate-500">{hint}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function ProgressBar({ value, className = '' }: { value: number; className?: string }) {
  return (
    <div className={`h-2 w-full overflow-hidden rounded-full bg-ink-700 ${className}`}>
      <div
        className="h-full rounded-full bg-brand transition-all"
        style={{ width: `${Math.max(0, Math.min(100, value))}%` }}
      />
    </div>
  );
}

export function Stat({ label, value, sub }: { label: string; value: React.ReactNode; sub?: string }) {
  return (
    <div className="rounded-lg bg-ink-850 border border-ink-700 px-3 py-2.5">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">{label}</div>
      <div className="mt-0.5 text-xl font-bold text-white tabular-nums">{value}</div>
      {sub && <div className="text-xs text-slate-500">{sub}</div>}
    </div>
  );
}

export function Modal({
  open, onClose, title, children, wide,
}: { open: boolean; onClose: () => void; title: string; children: React.ReactNode; wide?: boolean }) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;
  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4 sm:p-8"
      onMouseDown={onClose}
    >
      <div
        className={`w-full ${wide ? 'max-w-3xl' : 'max-w-lg'} rounded-xl border border-ink-700 bg-ink-900 shadow-glow`}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-ink-700 px-5 py-3.5">
          <h3 className="font-bold text-white">{title}</h3>
          <button className="btn-ghost btn-sm" onClick={onClose} aria-label="Fermer">✕</button>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}

// A delete button that asks for confirmation inline.
export function ConfirmButton({
  onConfirm, children = 'Supprimer', className = 'btn-danger btn-sm',
}: { onConfirm: () => void; children?: React.ReactNode; className?: string }) {
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!armed) return;
    const t = setTimeout(() => setArmed(false), 3000);
    return () => clearTimeout(t);
  }, [armed]);
  return (
    <button
      className={className}
      onClick={() => (armed ? onConfirm() : setArmed(true))}
    >
      {armed ? 'Confirmer ?' : children}
    </button>
  );
}

export function Badge({
  children, color = 'slate',
}: { children: React.ReactNode; color?: string }) {
  const map: Record<string, string> = {
    slate: 'bg-ink-700 text-slate-300',
    brand: 'bg-brand/20 text-brand-soft',
    green: 'bg-accent-green/20 text-accent-green',
    amber: 'bg-accent-amber/20 text-accent-amber',
    red: 'bg-accent-red/20 text-accent-red',
    blue: 'bg-accent-blue/20 text-accent-blue',
    pink: 'bg-accent-pink/20 text-accent-pink',
  };
  return <span className={`chip ${map[color] || map.slate}`}>{children}</span>;
}

// Small star rating input (1-5).
export function StarRating({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  return (
    <div className="flex gap-0.5">
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          type="button"
          onClick={() => onChange(n)}
          className={`text-lg leading-none ${n <= value ? 'text-accent-amber' : 'text-ink-600'} hover:scale-110 transition-transform`}
          aria-label={`${n} sur 5`}
        >
          ★
        </button>
      ))}
    </div>
  );
}
