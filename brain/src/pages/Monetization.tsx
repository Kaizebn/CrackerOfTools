import { useState } from 'react';
import { useMonetization, useRevenues, useBrands } from '../lib/hooks';
import { saveMonetization } from '../lib/store';
import { db, uid } from '../db/db';
import {
  Card, Field, Input, Select, Modal, EmptyState, Badge, ProgressBar, ConfirmButton,
} from '../components/ui';
import { fmtNumber, fmtDate, pct } from '../lib/format';
import type { Revenue, BrandContact, BrandStatus } from '../db/types';

const SOURCE_LABELS: Record<Revenue['source'], string> = {
  pub: 'Publicité', affiliation: 'Affiliation', sponsor: 'Sponsors', produit: 'Produits',
};
const SOURCE_COLORS: Record<Revenue['source'], string> = {
  pub: '#3aa0ff', affiliation: '#2ecc9b', sponsor: '#f5a623', produit: '#ff6ec7',
};
const BRAND_LABELS: Record<BrandStatus, string> = {
  contacted: 'Contacté', talking: 'En discussion', signed: 'Signé',
};
const BRAND_COLORS: Record<BrandStatus, 'slate' | 'amber' | 'green'> = {
  contacted: 'slate', talking: 'amber', signed: 'green',
};

export default function Monetization() {
  const mon = useMonetization();
  const revenues = useRevenues();
  const brands = useBrands();

  const revBySource = (['pub', 'affiliation', 'sponsor', 'produit'] as const).map((s) => ({
    source: s,
    total: revenues.filter((r) => r.source === s).reduce((a, r) => a + r.amount, 0),
  }));
  const totalRevenue = revenues.reduce((a, r) => a + r.amount, 0);
  const maxSource = Math.max(1, ...revBySource.map((r) => r.total));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-extrabold text-white">💰 Monétisation</h1>
        <p className="text-sm text-slate-500">Tes seuils, tes revenus et tes contacts marques.</p>
      </div>

      {/* Thresholds */}
      <Card className="space-y-4">
        <h2 className="section-title">Seuils de monétisation</h2>
        <Threshold label="YouTube — Abonnés" value={mon.ytSubs} target={1000} unit="abonnés" onChange={(v) => saveMonetization({ ytSubs: v })} />
        <Threshold label="YouTube — Heures de visionnage" value={mon.ytWatchHours} target={4000} unit="h" onChange={(v) => saveMonetization({ ytWatchHours: v })} />
        <Threshold label="TikTok — Abonnés" value={mon.tiktokFollowers} target={10000} unit="abonnés" onChange={(v) => saveMonetization({ tiktokFollowers: v })} />
        <p className="text-xs text-slate-500">
          YouTube Partner Program : 1000 abonnés + 4000h sur 12 mois (ou 10M vues Shorts / 90j).
          TikTok : conditions variables selon le programme et le pays.
        </p>
      </Card>

      {/* Revenue */}
      <RevenueSection revenues={revenues} revBySource={revBySource} total={totalRevenue} maxSource={maxSource} />

      {/* Brands */}
      <BrandSection brands={brands} />
    </div>
  );
}

function Threshold({
  label, value, target, unit, onChange,
}: { label: string; value: number; target: number; unit: string; onChange: (v: number) => void }) {
  const p = pct(value, target);
  return (
    <div>
      <div className="mb-1 flex items-center justify-between gap-2">
        <span className="text-sm font-medium text-slate-300">{label}</span>
        <div className="flex items-center gap-2">
          <Input
            type="number" min={0} value={value}
            onChange={(e) => onChange(Math.max(0, +e.target.value))}
            className="w-28 text-right text-sm py-1"
          />
          <span className="text-sm text-slate-500">/ {fmtNumber(target)} {unit}</span>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <ProgressBar value={p} />
        <span className="w-10 text-right text-xs font-bold text-brand-soft">{p}%</span>
      </div>
    </div>
  );
}

function RevenueSection({
  revenues, revBySource, total, maxSource,
}: {
  revenues: Revenue[];
  revBySource: { source: Revenue['source']; total: number }[];
  total: number; maxSource: number;
}) {
  const [open, setOpen] = useState(false);
  const [source, setSource] = useState<Revenue['source']>('pub');
  const [amount, setAmount] = useState(0);
  const [label, setLabel] = useState('');
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));

  const add = async () => {
    if (amount <= 0) return;
    await db.revenues.add({ id: uid(), source, amount, label: label.trim(), date });
    setAmount(0); setLabel(''); setOpen(false);
  };

  return (
    <Card>
      <div className="mb-3 flex items-center justify-between">
        <h2 className="section-title">Revenus</h2>
        <button className="btn-ghost btn-sm" onClick={() => setOpen(true)}>+ Ajouter</button>
      </div>

      <div className="mb-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
        {revBySource.map((r) => (
          <div key={r.source} className="rounded-lg bg-ink-850 border border-ink-700 p-3">
            <div className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
              <span className="h-2 w-2 rounded-full" style={{ background: SOURCE_COLORS[r.source] }} />
              {SOURCE_LABELS[r.source]}
            </div>
            <div className="mt-1 text-lg font-bold text-white tabular-nums">{fmtNumber(r.total)} €</div>
            <div className="mt-1 h-1 overflow-hidden rounded bg-ink-800">
              <div className="h-full rounded" style={{ width: `${(r.total / maxSource) * 100}%`, background: SOURCE_COLORS[r.source] }} />
            </div>
          </div>
        ))}
      </div>

      <div className="mb-3 flex items-center justify-between rounded-lg bg-brand/10 border border-brand/30 px-4 py-2.5">
        <span className="text-sm font-medium text-slate-200">Revenu total</span>
        <span className="text-xl font-extrabold text-white">{fmtNumber(total)} €</span>
      </div>

      {revenues.length === 0 ? (
        <p className="text-sm text-slate-600 italic">Aucun revenu enregistré. C'est le début !</p>
      ) : (
        <div className="space-y-1">
          {revenues.map((r) => (
            <div key={r.id} className="group flex items-center gap-3 rounded-md bg-ink-850 px-3 py-2 text-sm">
              <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: SOURCE_COLORS[r.source] }} />
              <span className="w-24 shrink-0 text-slate-400">{SOURCE_LABELS[r.source]}</span>
              <span className="min-w-0 flex-1 truncate text-slate-300">{r.label || '—'}</span>
              <span className="shrink-0 text-slate-500">{fmtDate(r.date)}</span>
              <span className="w-20 shrink-0 text-right font-semibold text-white">{fmtNumber(r.amount)} €</span>
              <ConfirmButton className="btn-danger btn-sm opacity-0 group-hover:opacity-100" onConfirm={() => db.revenues.delete(r.id)}>✕</ConfirmButton>
            </div>
          ))}
        </div>
      )}

      <Modal open={open} onClose={() => setOpen(false)} title="Ajouter un revenu">
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Source">
              <Select value={source} onChange={(e) => setSource(e.target.value as Revenue['source'])}>
                {(Object.keys(SOURCE_LABELS) as Revenue['source'][]).map((s) => <option key={s} value={s}>{SOURCE_LABELS[s]}</option>)}
              </Select>
            </Field>
            <Field label="Montant (€)">
              <Input type="number" min={0} value={amount} onChange={(e) => setAmount(+e.target.value)} />
            </Field>
          </div>
          <Field label="Libellé"><Input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Ex : AdSense septembre" /></Field>
          <Field label="Date"><Input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
          <div className="flex justify-end gap-2">
            <button className="btn-ghost" onClick={() => setOpen(false)}>Annuler</button>
            <button className="btn-primary" onClick={add}>Ajouter</button>
          </div>
        </div>
      </Modal>
    </Card>
  );
}

function BrandSection({ brands }: { brands: BrandContact[] }) {
  const [open, setOpen] = useState(false);
  const [brand, setBrand] = useState('');
  const [contact, setContact] = useState('');
  const [note, setNote] = useState('');

  const add = async () => {
    if (!brand.trim()) return;
    await db.brands.add({
      id: uid(), brand: brand.trim(), contact: contact.trim(),
      status: 'contacted', note: note.trim(), updatedAt: Date.now(),
    });
    setBrand(''); setContact(''); setNote(''); setOpen(false);
  };
  const setStatus = (b: BrandContact, status: BrandStatus) =>
    db.brands.put({ ...b, status, updatedAt: Date.now() });

  return (
    <Card>
      <div className="mb-3 flex items-center justify-between">
        <h2 className="section-title">Carnet de contacts marques</h2>
        <button className="btn-ghost btn-sm" onClick={() => setOpen(true)}>+ Contact</button>
      </div>

      {brands.length === 0 ? (
        <EmptyState icon="🤝" title="Aucun contact marque" hint="Note ici chaque marque que tu contactes et suis l'avancée de la discussion." />
      ) : (
        <div className="space-y-2">
          {brands.map((b) => (
            <div key={b.id} className="group rounded-lg border border-ink-700 bg-ink-850 p-3">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="font-semibold text-white">{b.brand}</div>
                  {b.contact && <div className="text-xs text-slate-500">{b.contact}</div>}
                  {b.note && <div className="mt-1 text-sm text-slate-400">{b.note}</div>}
                </div>
                <Badge color={BRAND_COLORS[b.status]}>{BRAND_LABELS[b.status]}</Badge>
              </div>
              <div className="mt-2 flex items-center gap-1.5">
                {(Object.keys(BRAND_LABELS) as BrandStatus[]).map((s) => (
                  <button
                    key={s}
                    onClick={() => setStatus(b, s)}
                    className={`chip ${b.status === s ? 'bg-brand/20 text-brand-soft' : 'bg-ink-800 text-slate-500 hover:text-slate-300'}`}
                  >
                    {BRAND_LABELS[s]}
                  </button>
                ))}
                <ConfirmButton className="btn-danger btn-sm ml-auto opacity-0 group-hover:opacity-100" onConfirm={() => db.brands.delete(b.id)}>Supprimer</ConfirmButton>
              </div>
            </div>
          ))}
        </div>
      )}

      <Modal open={open} onClose={() => setOpen(false)} title="Nouveau contact marque">
        <div className="space-y-3">
          <Field label="Marque" required><Input value={brand} onChange={(e) => setBrand(e.target.value)} placeholder="Ex : NordVPN" /></Field>
          <Field label="Contact (email, @, nom)"><Input value={contact} onChange={(e) => setContact(e.target.value)} placeholder="Ex : partenariats@…" /></Field>
          <Field label="Note"><Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Contexte, offre…" /></Field>
          <div className="flex justify-end gap-2">
            <button className="btn-ghost" onClick={() => setOpen(false)}>Annuler</button>
            <button className="btn-primary" onClick={add}>Ajouter</button>
          </div>
        </div>
      </Modal>
    </Card>
  );
}
