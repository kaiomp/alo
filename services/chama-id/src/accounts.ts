import { randomBytes } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import type { SynapseAdmin } from './synapse.ts';

const ALPHABET = 'abcdefghijklmnopqrstuvwxyz234567';
// `u` + 16 base32 chars (80 bits). 256 is a multiple of 32, so `& 31` is unbiased.
const randomLocalpart = () => 'u' + [...randomBytes(16)].map((b) => ALPHABET[b & 31]).join('');

// phone → current account (spec §4). A phone number is never the Matrix ID, because carriers recycle numbers.
export class Accounts {
  private db: DatabaseSync;
  private admin: SynapseAdmin;
  private o: { serverName: string; inactiveDays: number; now: () => number; randomLocalpart: () => string };
  constructor(db: DatabaseSync, admin: SynapseAdmin, opts: { serverName: string; inactiveDays?: number; now?: () => number; randomLocalpart?: () => string }) {
    this.db = db; this.admin = admin;
    this.o = {
      serverName: opts.serverName, inactiveDays: opts.inactiveDays ?? 45,
      now: opts.now ?? (() => Math.floor(Date.now() / 1000)), randomLocalpart: opts.randomLocalpart ?? randomLocalpart,
    };
  }
  private userId(localpart: string) { return `@${localpart}:${this.o.serverName}`; }

  current(phone: string): { localpart: string; userId: string } | null {
    const row = this.db.prepare('SELECT localpart FROM accounts WHERE phone = ?').get(phone) as { localpart: string } | undefined;
    return row ? { localpart: row.localpart, userId: this.userId(row.localpart) } : null;
  }

  // Call only after the phone proved ownership (OTP verified).
  async resolve(phone: string): Promise<{ localpart: string; userId: string; created: boolean }> {
    const now = this.o.now();
    const row = this.db.prepare('SELECT localpart, last_signin_at FROM accounts WHERE phone = ?').get(phone) as
      { localpart: string; last_signin_at: number } | undefined;
    const localpart = this.o.randomLocalpart();
    if (!row) {
      const { changes } = this.db.prepare('INSERT INTO accounts (phone, localpart, last_signin_at) VALUES (?, ?, ?) ON CONFLICT(phone) DO NOTHING')
        .run(phone, localpart, now);
      if (changes) return { localpart, userId: this.userId(localpart), created: true };
      return { ...this.current(phone)!, created: false };
    }
    const old = row.localpart;
    const ms = await this.admin.lastActiveMs(this.userId(old));
    // Logging out deletes the device, so a recent sign-in through chama-id also counts as activity.
    const lastActive = Math.max(ms ?? Infinity, row.last_signin_at * 1000);
    if (ms === null || lastActive > (now - this.o.inactiveDays * 86400) * 1000) {
      this.db.prepare('UPDATE accounts SET last_signin_at = MAX(last_signin_at, ?) WHERE phone = ?').run(now, phone);
      return { ...this.current(phone)!, created: false };
    }
    // Inactive too long: most likely a recycled number. Retire the old account before mapping a new one.
    await this.admin.deactivate(this.userId(old));
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const { changes } = this.db.prepare('UPDATE accounts SET localpart = ?, last_signin_at = ? WHERE phone = ? AND localpart = ?')
        .run(localpart, now, phone, old);
      if (changes) this.db.prepare('INSERT INTO retired_accounts (phone, localpart, retired_at) VALUES (?, ?, ?)').run(phone, old, now);
      this.db.exec('COMMIT');
      if (changes) return { localpart, userId: this.userId(localpart), created: true };
    } catch (e) { this.db.exec('ROLLBACK'); throw e; }
    return { ...this.current(phone)!, created: false }; // a concurrent sign-in already replaced it
  }
}
