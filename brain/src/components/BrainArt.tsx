// A stylized, glowing brain drawn in SVG. Scales to its container.
export default function BrainArt({ className = '' }: { className?: string }) {
  return (
    <svg viewBox="0 0 240 210" className={className} aria-hidden="true">
      <defs>
        <radialGradient id="brainFill" cx="42%" cy="34%" r="75%">
          <stop offset="0%" stopColor="#c9bcff" />
          <stop offset="42%" stopColor="#9b82ff" />
          <stop offset="78%" stopColor="#7c5cff" />
          <stop offset="100%" stopColor="#5b41c9" />
        </radialGradient>
        <linearGradient id="stemFill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#7c5cff" />
          <stop offset="100%" stopColor="#4c34a8" />
        </linearGradient>
      </defs>

      {/* brain stem */}
      <path d="M112 150 q8 26 8 44 q0 8 8 8 q8 0 8 -8 q0 -18 8 -44 Z" fill="url(#stemFill)" />

      {/* bumpy cerebrum mass: overlapping blobs sharing the same fill read as gyri bumps */}
      <g fill="url(#brainFill)">
        <ellipse cx="120" cy="92" rx="86" ry="66" />
        <circle cx="60" cy="66" r="30" />
        <circle cx="92" cy="46" r="30" />
        <circle cx="120" cy="40" r="27" />
        <circle cx="150" cy="46" r="30" />
        <circle cx="182" cy="66" r="29" />
        <circle cx="44" cy="96" r="26" />
        <circle cx="198" cy="96" r="25" />
        <circle cx="66" cy="132" r="27" />
        <circle cx="120" cy="140" r="28" />
        <circle cx="176" cy="132" r="27" />
      </g>

      {/* soft top-left highlight */}
      <ellipse cx="92" cy="58" rx="48" ry="30" fill="#ffffff" opacity="0.12" />

      {/* central fissure */}
      <path d="M120 30 C112 60 128 78 120 100 C112 124 128 138 120 158"
            fill="none" stroke="#4c34a8" strokeWidth="3.5" strokeLinecap="round" opacity="0.85" />

      {/* gyri folds (left) */}
      <g fill="none" stroke="#c9bcff" strokeWidth="3" strokeLinecap="round" opacity="0.55">
        <path d="M48 78 q14 -10 26 2 q12 12 24 2" />
        <path d="M42 104 q16 -8 30 6 q12 12 26 0" />
        <path d="M56 130 q14 -10 26 2 q10 10 22 4" />
        <path d="M70 54 q12 -8 22 4" />
      </g>
      {/* gyri folds (right) */}
      <g fill="none" stroke="#c9bcff" strokeWidth="3" strokeLinecap="round" opacity="0.55">
        <path d="M192 78 q-14 -10 -26 2 q-12 12 -24 2" />
        <path d="M198 104 q-16 -8 -30 6 q-12 12 -26 0" />
        <path d="M184 130 q-14 -10 -26 2 q-10 10 -22 4" />
        <path d="M170 54 q-12 -8 -22 4" />
      </g>
    </svg>
  );
}
