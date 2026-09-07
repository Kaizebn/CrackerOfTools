// A detailed, luminous brain. The folds (gyri) are generated as many short,
// organically-placed squiggles clipped to the brain silhouette, which reads as
// real packed brain tissue rather than flat ripples.

function mulberry32(seed: number) {
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Short wavy stroke centred at (x,y), oriented by angle a, of length L.
function squiggle(x: number, y: number, a: number, L: number, amp: number): string {
  const dx = Math.cos(a), dy = Math.sin(a);
  const px = -dy, py = dx; // perpendicular
  const seg = 3, half = L / 2;
  const sx = x - dx * half, sy = y - dy * half;
  let d = `M ${sx.toFixed(1)} ${sy.toFixed(1)}`;
  for (let i = 1; i <= seg; i++) {
    const t = i / seg, mt = (i - 0.5) / seg;
    const bump = (i % 2 ? amp : -amp);
    const ex = x + dx * (-half + L * t);
    const ey = y + dy * (-half + L * t);
    const cx = x + dx * (-half + L * mt) + px * bump;
    const cy = y + dy * (-half + L * mt) + py * bump;
    d += ` Q ${cx.toFixed(1)} ${cy.toFixed(1)} ${ex.toFixed(1)} ${ey.toFixed(1)}`;
  }
  return d;
}

// Silhouette bumps (also the clip path) — a bumpy two-hemisphere mass.
const BUMPS = [
  { cx: 128, cy: 98, rx: 80, ry: 62 },
  { cx: 66, cy: 66, r: 30 }, { cx: 98, cy: 46, r: 30 }, { cx: 128, cy: 40, r: 28 },
  { cx: 158, cy: 46, r: 30 }, { cx: 190, cy: 66, r: 30 },
  { cx: 46, cy: 98, r: 26 }, { cx: 210, cy: 98, r: 26 },
  { cx: 68, cy: 132, r: 27 }, { cx: 128, cy: 142, r: 28 }, { cx: 188, cy: 132, r: 27 },
  { cx: 100, cy: 152, r: 22 }, { cx: 156, cy: 152, r: 22 },
];

// Generate squiggles inside an ellipse approximating the brain body.
function buildGyri(): string[] {
  const rnd = mulberry32(7);
  const out: string[] = [];
  const cx = 128, cy = 96, rx = 92, ry = 70;
  let tries = 0;
  while (out.length < 90 && tries < 900) {
    tries++;
    const x = cx + (rnd() - 0.5) * 2 * rx;
    const y = cy + (rnd() - 0.5) * 2 * ry;
    // inside-ellipse test with margin
    const inside = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 0.92;
    if (!inside) continue;
    // avoid the central fissure gap
    if (Math.abs(x - 128) < 7) continue;
    const a = (rnd() - 0.5) * Math.PI;      // random orientation
    const L = 12 + rnd() * 12;
    const amp = 2.5 + rnd() * 2;
    out.push(squiggle(x, y, a, L, amp));
  }
  return out;
}

const GYRI = buildGyri();

export default function BrainArt({ className = '' }: { className?: string }) {
  return (
    <svg viewBox="0 0 256 224" className={className} aria-hidden="true">
      <defs>
        <radialGradient id="tissue" cx="42%" cy="30%" r="80%">
          <stop offset="0%" stopColor="#e7d9ff" />
          <stop offset="38%" stopColor="#b89dff" />
          <stop offset="70%" stopColor="#8b6cff" />
          <stop offset="100%" stopColor="#5b41c9" />
        </radialGradient>
        <radialGradient id="rimShade" cx="50%" cy="46%" r="62%">
          <stop offset="68%" stopColor="#000" stopOpacity="0" />
          <stop offset="100%" stopColor="#2a1a66" stopOpacity="0.6" />
        </radialGradient>
        <linearGradient id="stem" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#8b6cff" />
          <stop offset="100%" stopColor="#4c34a8" />
        </linearGradient>
        <clipPath id="brainClip">
          {BUMPS.map((b, i) =>
            'rx' in b
              ? <ellipse key={i} cx={b.cx} cy={b.cy} rx={(b as any).rx} ry={(b as any).ry} />
              : <circle key={i} cx={b.cx} cy={b.cy} r={(b as any).r} />,
          )}
        </clipPath>
      </defs>

      {/* brain stem + cerebellum (behind, slightly below) */}
      <path d="M116 156 q12 30 12 50 q0 8 8 8 q8 0 8 -8 q0 -20 12 -50 Z" fill="url(#stem)" />
      <g opacity="0.92">
        <ellipse cx="128" cy="170" rx="42" ry="21" fill="#6a4bd6" />
        <path d="M90 168 q38 -12 76 0 M92 176 q36 -10 72 0 M98 184 q30 -8 60 0"
              fill="none" stroke="#3d2a8f" strokeWidth="2.4" strokeLinecap="round" />
      </g>

      {/* cerebrum with clipped fold detail */}
      <g clipPath="url(#brainClip)">
        <rect x="0" y="0" width="256" height="224" fill="url(#tissue)" />

        {/* sulci (dark, offset down for depth) */}
        <g fill="none" stroke="#33206f" strokeWidth="3.2" strokeLinecap="round" opacity="0.5"
           transform="translate(0.6 2.2)">
          {GYRI.map((d, i) => <path key={i} d={d} />)}
        </g>
        {/* gyri ridges (light) */}
        <g fill="none" stroke="#efe6ff" strokeWidth="2.2" strokeLinecap="round" opacity="0.8">
          {GYRI.map((d, i) => <path key={i} d={d} />)}
        </g>

        {/* central fissure */}
        <path d="M128 28 C121 58 135 78 128 100 C121 126 135 142 128 160"
              fill="none" stroke="#2c1c63" strokeWidth="5.5" strokeLinecap="round" opacity="0.92" />

        {/* highlight + rim shading for volume */}
        <ellipse cx="94" cy="56" rx="54" ry="30" fill="#ffffff" opacity="0.16" />
        <rect x="0" y="0" width="256" height="224" fill="url(#rimShade)" />
      </g>
    </svg>
  );
}
