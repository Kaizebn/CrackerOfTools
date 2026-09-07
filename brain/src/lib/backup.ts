import { db } from '../db/db';

const TABLES = [
  'items', 'hooks', 'positioning', 'settings', 'monetization',
  'revenues', 'brands', 'learning', 'journal', 'activity',
] as const;

export interface BackupFile {
  app: 'brain';
  version: number;
  exportedAt: string;
  data: Record<string, unknown[]>;
}

export async function exportAll(): Promise<BackupFile> {
  const data: Record<string, unknown[]> = {};
  for (const t of TABLES) {
    data[t] = await (db as any)[t].toArray();
  }
  return {
    app: 'brain',
    version: 1,
    exportedAt: new Date().toISOString(),
    data,
  };
}

export async function downloadBackup(): Promise<void> {
  const backup = await exportAll();
  const blob = new Blob([JSON.stringify(backup, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `brain-sauvegarde-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// Replaces the entire database with the contents of a backup file.
export async function importAll(backup: BackupFile): Promise<void> {
  if (!backup || backup.app !== 'brain' || !backup.data) {
    throw new Error('Fichier de sauvegarde invalide.');
  }
  await db.transaction('rw', db.tables, async () => {
    for (const t of TABLES) {
      const rows = backup.data[t];
      if (!Array.isArray(rows)) continue;
      await (db as any)[t].clear();
      if (rows.length) await (db as any)[t].bulkPut(rows);
    }
  });
}

export async function importFromFile(file: File): Promise<void> {
  const text = await file.text();
  const parsed = JSON.parse(text) as BackupFile;
  await importAll(parsed);
}

// Wipe everything (used by the "reset" action).
export async function wipeAll(): Promise<void> {
  await db.transaction('rw', db.tables, async () => {
    for (const t of TABLES) await (db as any)[t].clear();
  });
}
