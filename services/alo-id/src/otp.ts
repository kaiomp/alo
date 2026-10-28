import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';
import type { SmsProvider } from './sms.ts';

// Dev mode multiplies IP_LIMIT by 100 so test suites can rerun; per-phone limits stay.
const TTL = 300, MAX_TRIES = 5, PHONE_GAP = 60, IP_LIMIT = 10, IP_WINDOW = 3600;
// Daily caps per phone survive new codes, so refreshing the code does not reset them.
const DAY = 86400, DAILY_REQUESTS = 5, DAILY_FAILS = 10;

export class OtpService {
  private db: DatabaseSync;
  private opts: { pepper: string; dev: boolean; sms: SmsProvider; now: () => number };
  constructor(db: DatabaseSync, opts: { pepper: string; dev: boolean; sms: SmsProvider; now?: () => number }) {
    this.db = db;
    this.opts = { ...opts, now: opts.now ?? (() => Math.floor(Date.now() / 1000)) };
  }
  private hash(phone: string, code: string) {
    return createHash('sha256').update(`${this.opts.pepper}:${phone}:${code}`).digest('hex');
  }
  // Throws rate_limited when `phone` already has `limit` events of `kind` in the last 24 h.
  private checkDaily(phone: string, kind: 'request' | 'fail', limit: number, now: number) {
    const { n, oldest } = this.db.prepare('SELECT COUNT(*) AS n, MIN(at) AS oldest FROM phone_events WHERE phone = ? AND kind = ? AND at > ?')
      .get(phone, kind, now - DAY) as { n: number; oldest: number };
    if (n >= limit) throw new AppError('rate_limited', { retry_after: oldest + DAY - now });
  }
  private addEvent(phone: string, kind: 'request' | 'fail', now: number) {
    this.db.prepare('DELETE FROM phone_events WHERE at <= ?').run(now - DAY);
    this.db.prepare('INSERT INTO phone_events (phone, kind, at) VALUES (?, ?, ?)').run(phone, kind, now);
  }
  async request(phone: string, ip: string): Promise<{ retryAfter: number }> {
    const now = this.opts.now();
    const prev = this.db.prepare('SELECT sent_at FROM otp WHERE phone = ?').get(phone) as { sent_at: number } | undefined;
    if (prev && now - prev.sent_at < PHONE_GAP) throw new AppError('rate_limited', { retry_after: PHONE_GAP - (now - prev.sent_at) });
    this.checkDaily(phone, 'request', DAILY_REQUESTS, now);
    this.db.prepare('DELETE FROM ip_requests WHERE at <= ?').run(now - IP_WINDOW);
    const { n, oldest } = this.db.prepare('SELECT COUNT(*) AS n, MIN(at) AS oldest FROM ip_requests WHERE ip = ?').get(ip) as { n: number; oldest: number };
    if (n >= IP_LIMIT * (this.opts.dev ? 100 : 1)) throw new AppError('rate_limited', { retry_after: oldest + IP_WINDOW - now });
    this.db.prepare('DELETE FROM otp WHERE expires_at < ?').run(now - DAY);
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    this.db.prepare(`INSERT INTO otp (phone, code_hash, expires_at, tries, sent_at) VALUES (?, ?, ?, 0, ?)
      ON CONFLICT(phone) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at, tries = 0, sent_at = excluded.sent_at`)
      .run(phone, this.hash(phone, code), now + TTL, now);
    this.db.prepare('INSERT INTO ip_requests (ip, at) VALUES (?, ?)').run(ip, now);
    this.addEvent(phone, 'request', now);
    await this.opts.sms.send(phone, `Seu código Alô: ${code}. Não compartilhe com ninguém.`);
    return { retryAfter: PHONE_GAP };
  }
  verify(phone: string, code: string): void {
    const now = this.opts.now();
    const row = this.db.prepare('SELECT code_hash, expires_at, tries FROM otp WHERE phone = ?').get(phone) as
      { code_hash: string; expires_at: number; tries: number } | undefined;
    if (!row) throw new AppError('invalid_code');
    if (this.opts.dev && code === '000000') { this.db.prepare('DELETE FROM otp WHERE phone = ?').run(phone); return; }
    this.checkDaily(phone, 'fail', DAILY_FAILS, now);
    if (row.tries >= MAX_TRIES) throw new AppError('too_many_attempts');
    if (now > row.expires_at) throw new AppError('expired');
    if (!timingSafeEqual(Buffer.from(this.hash(phone, code), 'hex'), Buffer.from(row.code_hash, 'hex'))) {
      this.db.prepare('UPDATE otp SET tries = tries + 1 WHERE phone = ?').run(phone);
      this.addEvent(phone, 'fail', now);
      throw new AppError('invalid_code');
    }
    this.db.prepare('DELETE FROM otp WHERE phone = ?').run(phone);
  }
}
