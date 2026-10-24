import { createHash } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';

export class Directory {
  private db: DatabaseSync;
  constructor(db: DatabaseSync) { this.db = db; }
  markRegistered(phoneDigits: string) {
    const hash = createHash('sha256').update(phoneDigits).digest('hex');
    this.db.prepare('INSERT OR IGNORE INTO registered (hash) VALUES (?)').run(hash);
  }
  lookup(hashes: string[]): string[] {
    if (!Array.isArray(hashes) || hashes.length > 1000 || hashes.some((x) => typeof x !== 'string' || !/^[0-9a-f]{64}$/.test(x))) throw new AppError('bad_request');
    const q = this.db.prepare('SELECT 1 FROM registered WHERE hash = ?');
    return [...new Set(hashes)].filter((x) => q.get(x));
  }
}
