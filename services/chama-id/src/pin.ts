import { argon2, randomBytes, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';

const argon2Async = promisify(argon2);
// Wait after the n-th wrong PIN in a row, in seconds; the last entry repeats. Four free tries for typos,
// then up to one try a day, so guessing 1 of 1 000 000 PINs online is hopeless.
const LOCKS = [0, 0, 0, 0, 60, 300, 3600, 86400];
// "Esqueci meu PIN": the wait before a sign-in may go on without it (WhatsApp waits 7 days too).
export const RESET_WAIT = 7 * 86400;

export type PinState = 'none' | 'set' | 'reset_due';
type Row = { hash: string; salt: string; fails: number; locked_until: number; reset_at: number | null };

// Account PIN ("Confirmação em duas etapas", spec §11), keyed by account localpart, so a recycled
// number's new account starts without the old owner's PIN.
// Limit: 6 digits are 1 000 000 guesses. Online guessing is stopped by LOCKS; an offline attacker
// needs the database and the pepper, then about 5 hours on one core (argon2id, 19 MiB, 2 passes).
// The operator holds both, so the PIN protects against SIM swaps, not against the operator.
export class Pins {
  private db: DatabaseSync;
  private o: { pepper: string; now: () => number };
  constructor(db: DatabaseSync, o: { pepper: string; now?: () => number }) {
    this.db = db;
    this.o = { pepper: o.pepper, now: o.now ?? (() => Math.floor(Date.now() / 1000)) };
  }
  private hash(pin: string, salt: Buffer): Promise<Buffer> {
    return argon2Async('argon2id', {
      message: pin, nonce: salt, secret: Buffer.from(this.o.pepper), parallelism: 1, tagLength: 32, memory: 19456, passes: 2,
    });
  }
  private row(localpart: string) {
    return this.db.prepare('SELECT hash, salt, fails, locked_until, reset_at FROM pins WHERE localpart = ?').get(localpart) as Row | undefined;
  }

  state(localpart: string): PinState {
    const r = this.row(localpart);
    if (!r) return 'none';
    return r.reset_at !== null && this.o.now() >= r.reset_at ? 'reset_due' : 'set';
  }
  status(localpart: string): { set: boolean; reset_at: number | null } {
    const r = this.row(localpart);
    return { set: !!r, reset_at: r?.reset_at ?? null };
  }
  async set(localpart: string, pin: string) {
    if (!/^\d{6}$/.test(pin)) throw new AppError('bad_request');
    const salt = randomBytes(16);
    const hash = await this.hash(pin, salt);
    this.db.prepare('INSERT OR REPLACE INTO pins (localpart, hash, salt) VALUES (?, ?, ?)')
      .run(localpart, hash.toString('hex'), salt.toString('hex'));
  }
  remove(localpart: string) { this.db.prepare('DELETE FROM pins WHERE localpart = ?').run(localpart); }

  // Passes when no PIN is set. A try is counted and the next lock set before the slow hash runs,
  // so parallel guesses cannot slip past the lock; a right PIN clears both.
  async check(localpart: string, pin: unknown) {
    if (!this.row(localpart)) return;
    if (typeof pin !== 'string' || !pin) throw new AppError('pin_required');
    const now = this.o.now();
    const r = this.db.prepare('UPDATE pins SET fails = fails + 1 WHERE localpart = ? AND locked_until <= ? RETURNING hash, salt, fails')
      .get(localpart, now) as { hash: string; salt: string; fails: number } | undefined;
    if (!r) {
      const locked = this.row(localpart)?.locked_until ?? now;
      throw new AppError('pin_locked', { retry_after: Math.max(1, locked - now) });
    }
    const wait = LOCKS[Math.min(r.fails, LOCKS.length) - 1];
    if (wait) this.db.prepare('UPDATE pins SET locked_until = ? WHERE localpart = ?').run(now + wait, localpart);
    const got = /^\d{6}$/.test(pin) ? await this.hash(pin, Buffer.from(r.salt, 'hex')) : Buffer.alloc(32);
    if (timingSafeEqual(got, Buffer.from(r.hash, 'hex'))) {
      this.db.prepare('UPDATE pins SET fails = 0, locked_until = 0 WHERE localpart = ?').run(localpart);
      return;
    }
    throw new AppError('invalid_pin', wait ? { retry_after: wait } : undefined);
  }

  // Starts (or keeps) the 7-day wait; returns when it ends.
  requestReset(localpart: string): number {
    const r = this.db.prepare('UPDATE pins SET reset_at = COALESCE(reset_at, ?) WHERE localpart = ? RETURNING reset_at')
      .get(this.o.now() + RESET_WAIT, localpart) as { reset_at: number } | undefined;
    if (!r) throw new AppError('bad_request');
    return r.reset_at;
  }
  cancelReset(localpart: string) { this.db.prepare('UPDATE pins SET reset_at = NULL WHERE localpart = ?').run(localpart); }
}
