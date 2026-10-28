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

  phoneOf(localpart: string): string | null {
    const row = this.db.prepare('SELECT phone FROM accounts WHERE localpart = ?').get(localpart) as { phone: string } | undefined;
    return row?.phone ?? null;
  }

  // Counts a sign-in that `resolve(phone, { keep: true })` held back until the PIN was right.
  touch(phone: string) {
    this.db.prepare('UPDATE accounts SET last_signin_at = MAX(last_signin_at, ?) WHERE phone = ?').run(this.o.now(), phone);
  }

  // Call only after the phone proved ownership (OTP verified). `keep`: the account has a PIN, so it is
  // never retired for inactivity (issue #3), and this sign-in does not count until the PIN is right.
  async resolve(phone: string, o: { keep?: boolean } = {}): Promise<{ localpart: string; userId: string; created: boolean }> {
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
    const activity = await this.admin.activity(this.userId(old));
    // Deactivated outside the retire path (an operator, or account deletion): map a fresh account (issue #3).
    if (activity?.deactivated) return this.replace(phone, old, localpart, now);
    if (o.keep) return { ...this.current(phone)!, created: false };
    const ms = activity?.lastActiveMs ?? null;
    // Activity = newest of: current devices, user-level last_seen (Synapse keeps IP logs 7 days), and the
    // PREVIOUS sign-in through alo-id (logout deletes devices). Known gap: logged out, then away 8-45 days,
    // with the last sign-in over 45 days ago → fresh account, unless the account has a PIN (`keep`).
    const lastActive = Math.max(ms ?? Infinity, row.last_signin_at * 1000);
    if (ms === null || lastActive > (now - this.o.inactiveDays * 86400) * 1000) {
      this.db.prepare('UPDATE accounts SET last_signin_at = MAX(last_signin_at, ?) WHERE phone = ?').run(now, phone);
      return { ...this.current(phone)!, created: false };
    }
    // Inactive too long: most likely a recycled number. Retire the old account before mapping a new one.
    await this.admin.deactivate(this.userId(old));
    return this.replace(phone, old, localpart, now);
  }

  private replace(phone: string, old: string, localpart: string, now: number) {
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
