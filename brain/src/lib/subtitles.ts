// ---------------------------------------------------------------------------
// Sous-titres automatiques — transcription 100% locale, dans le navigateur.
// Utilise Whisper via transformers.js (WebAssembly). Le modèle se télécharge
// une fois (puis reste en cache). Aucune clé, aucun serveur : ton audio ne
// quitte jamais ton appareil.
// ---------------------------------------------------------------------------

export interface Chunk { text: string; start: number; end: number; }
export interface TranscriptResult { text: string; chunks: Chunk[]; }

export const SUB_MODELS = [
  { id: 'Xenova/whisper-tiny', label: 'Rapide (léger, ~40 Mo)' },
  { id: 'Xenova/whisper-base', label: 'Meilleur (plus lent, ~150 Mo)' },
];

export type ProgressFn = (info: { label: string; percent: number }) => void;

// Decode any audio/video file to 16 kHz mono Float32 samples (what Whisper wants).
export async function decodeToMono16k(file: File): Promise<Float32Array> {
  const buf = await file.arrayBuffer();
  const AC: typeof AudioContext =
    window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
  const ac = new AC();
  let decoded: AudioBuffer;
  try {
    decoded = await ac.decodeAudioData(buf.slice(0));
  } catch {
    try { ac.close(); } catch { /* ignore */ }
    throw new Error(
      "Impossible de lire l'audio de ce fichier. Essaie un .mp3 / .m4a / .wav, " +
      "ou exporte l'audio de ta vidéo puis réessaie.",
    );
  }
  try { ac.close(); } catch { /* ignore */ }

  const rate = 16000;
  const length = Math.max(1, Math.ceil(decoded.duration * rate));
  const off = new OfflineAudioContext(1, length, rate);
  const src = off.createBufferSource();
  src.buffer = decoded;
  src.connect(off.destination);
  src.start();
  const rendered = await off.startRendering();
  return rendered.getChannelData(0);
}

// Run Whisper on the file and return the transcript + timed chunks.
export async function transcribe(
  file: File,
  opts: { model: string; language?: string; onProgress?: ProgressFn },
): Promise<TranscriptResult> {
  opts.onProgress?.({ label: 'Lecture de l\'audio…', percent: 5 });
  const audio = await decodeToMono16k(file);

  const { pipeline, env } = await import('@huggingface/transformers');
  // Fetch models from the Hugging Face hub (no local model files bundled).
  env.allowLocalModels = false;

  opts.onProgress?.({ label: 'Chargement du modèle (1re fois : téléchargement)…', percent: 10 });
  const transcriber = await pipeline('automatic-speech-recognition', opts.model, {
    dtype: 'q8',
    progress_callback: (p: { status?: string; progress?: number; file?: string }) => {
      if (p?.status === 'progress' && typeof p.progress === 'number') {
        opts.onProgress?.({
          label: `Téléchargement du modèle… ${Math.round(p.progress)}%`,
          percent: 10 + Math.round(p.progress * 0.5), // 10% → 60%
        });
      }
    },
  });

  opts.onProgress?.({ label: 'Transcription en cours…', percent: 65 });
  const out = (await transcriber(audio, {
    return_timestamps: true,
    chunk_length_s: 30,
    stride_length_s: 5,
    language: opts.language || undefined,
    task: 'transcribe',
  })) as { text?: string; chunks?: { text: string; timestamp: [number, number | null] }[] };

  opts.onProgress?.({ label: 'Terminé', percent: 100 });

  const chunks: Chunk[] = (out.chunks || [])
    .map((c, i, arr) => {
      const start = c.timestamp?.[0] ?? 0;
      const end = c.timestamp?.[1] ?? (arr[i + 1]?.timestamp?.[0] ?? start + 2);
      return { text: (c.text || '').trim(), start, end };
    })
    .filter((c) => c.text);

  return { text: (out.text || '').trim(), chunks };
}

// Split long chunks into short caption groups (TikTok style), distributing the
// time span proportionally across words.
export function toShortCaptions(chunks: Chunk[], maxWords = 4): Chunk[] {
  const out: Chunk[] = [];
  for (const c of chunks) {
    const words = c.text.split(/\s+/).filter(Boolean);
    if (words.length <= maxWords) { out.push(c); continue; }
    const span = Math.max(0.001, c.end - c.start);
    const per = span / words.length;
    for (let i = 0; i < words.length; i += maxWords) {
      const group = words.slice(i, i + maxWords);
      out.push({
        text: group.join(' '),
        start: c.start + per * i,
        end: c.start + per * Math.min(words.length, i + maxWords),
      });
    }
  }
  return out;
}

function pad(n: number, len = 2): string { return String(n).padStart(len, '0'); }
function stamp(t: number, sep: string): string {
  const ms = Math.floor((t % 1) * 1000);
  const s = Math.floor(t) % 60;
  const m = Math.floor(t / 60) % 60;
  const h = Math.floor(t / 3600);
  return `${pad(h)}:${pad(m)}:${pad(s)}${sep}${pad(ms, 3)}`;
}

export function toSRT(chunks: Chunk[]): string {
  return chunks
    .map((c, i) => `${i + 1}\n${stamp(c.start, ',')} --> ${stamp(c.end, ',')}\n${c.text}\n`)
    .join('\n');
}

export function toVTT(chunks: Chunk[]): string {
  return 'WEBVTT\n\n' + chunks
    .map((c) => `${stamp(c.start, '.')} --> ${stamp(c.end, '.')}\n${c.text}\n`)
    .join('\n');
}

// Trigger a file download in the browser (works in the local app / PWA).
export function downloadText(filename: string, content: string): void {
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
