import { createHash } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';

// Hashes one account may look up per day (issue #7: phone hashes are enumerable,
// so this caps how many numbers one SMS-verified account can test).
// Limit: a fixed 24 h window from the first lookup, so up to 2x the quota right
// at a window edge; a rolling window needs per-request rows.
export const DAILY_HASHES = 10_000;
const DAY = 86400;

// Maps sha256(phone digits) to the phone's current account localpart.
export class Directory {
  private db: DatabaseSync;
  private serverName: string;
  constructor(db: DatabaseSync, serverName: string) { this.db = db; this.serverName = serverName; }
  markRegistered(phoneDigits: string, localpart: string) {
    const hash = createHash('sha256').update(phoneDigits).digest('hex');
    this.db.prepare('INSERT INTO directory (hash, localpart) VALUES (?, ?) ON CONFLICT(hash) DO UPDATE SET localpart = excluded.localpart').run(hash, localpart);
  }
  // `userId` pays for the distinct hashes it sends; the hashes themselves are never stored.
  lookup(hashes: string[], userId: string, o: { now: number; quota?: number }): { hash: string; user_id: string }[] {
    if (!Array.isArray(hashes) || hashes.length > 1000 || hashes.some((x) => typeof x !== 'string' || !/^[0-9a-f]{64}$/.test(x))) throw new AppError('bad_request');
    const unique = [...new Set(hashes)];
    this.charge(userId, unique.length, o.now, o.quota ?? DAILY_HASHES);
    const q = this.db.prepare('SELECT localpart FROM directory WHERE hash = ?');
    return unique.flatMap((hash) => {
      const row = q.get(hash) as { localpart: string } | undefined;
      return row ? [{ hash, user_id: `@${row.localpart}:${this.serverName}` }] : [];
    });
  }
  private charge(userId: string, n: number, now: number, quota: number) {
    const row = this.db.prepare('SELECT window_start, used FROM lookup_quota WHERE user_id = ?').get(userId) as
      { window_start: number; used: number } | undefined;
    const fresh = !row || now - row.window_start >= DAY;
    const start = fresh ? now : row.window_start;
    const used = fresh ? 0 : row.used;
    if (used + n > quota) throw new AppError('rate_limited', { retry_after: start + DAY - now });
    this.db.prepare(`INSERT INTO lookup_quota (user_id, window_start, used) VALUES (?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET window_start = excluded.window_start, used = excluded.used`).run(userId, start, used + n);
  }
}
