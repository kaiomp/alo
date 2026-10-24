import { createHash } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';

// Maps sha256(phone digits) to the phone's current account localpart.
export class Directory {
  private db: DatabaseSync;
  private serverName: string;
  constructor(db: DatabaseSync, serverName: string) { this.db = db; this.serverName = serverName; }
  markRegistered(phoneDigits: string, localpart: string) {
    const hash = createHash('sha256').update(phoneDigits).digest('hex');
    this.db.prepare('INSERT INTO directory (hash, localpart) VALUES (?, ?) ON CONFLICT(hash) DO UPDATE SET localpart = excluded.localpart').run(hash, localpart);
  }
  lookup(hashes: string[]): { hash: string; user_id: string }[] {
    if (!Array.isArray(hashes) || hashes.length > 1000 || hashes.some((x) => typeof x !== 'string' || !/^[0-9a-f]{64}$/.test(x))) throw new AppError('bad_request');
    const q = this.db.prepare('SELECT localpart FROM directory WHERE hash = ?');
    return [...new Set(hashes)].flatMap((hash) => {
      const row = q.get(hash) as { localpart: string } | undefined;
      return row ? [{ hash, user_id: `@${row.localpart}:${this.serverName}` }] : [];
    });
  }
}
