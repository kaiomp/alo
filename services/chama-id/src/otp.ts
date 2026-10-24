import { createHash, randomInt } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';
import type { SmsProvider } from './sms.ts';

const TTL = 300, MAX_TRIES = 5, PHONE_GAP = 60, IP_LIMIT = 10, IP_WINDOW = 3600;

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
  async request(phone: string, ip: string): Promise<{ retryAfter: number }> {
    const now = this.opts.now();
    const prev = this.db.prepare('SELECT sent_at FROM otp WHERE phone = ?').get(phone) as { sent_at: number } | undefined;
    if (prev && now - prev.sent_at < PHONE_GAP) throw new AppError('rate_limited', { retry_after: PHONE_GAP - (now - prev.sent_at) });
    this.db.prepare('DELETE FROM ip_requests WHERE at <= ?').run(now - IP_WINDOW);
    const { n } = this.db.prepare('SELECT COUNT(*) AS n FROM ip_requests WHERE ip = ?').get(ip) as { n: number };
    if (n >= IP_LIMIT) {
      const { oldest } = this.db.prepare('SELECT MIN(at) AS oldest FROM ip_requests WHERE ip = ?').get(ip) as { oldest: number };
      throw new AppError('rate_limited', { retry_after: oldest + IP_WINDOW - now });
    }
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    this.db.prepare(`INSERT INTO otp (phone, code_hash, expires_at, tries, sent_at) VALUES (?, ?, ?, 0, ?)
      ON CONFLICT(phone) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at, tries = 0, sent_at = excluded.sent_at`)
      .run(phone, this.hash(phone, code), now + TTL, now);
    this.db.prepare('INSERT INTO ip_requests (ip, at) VALUES (?, ?)').run(ip, now);
    await this.opts.sms.send(phone, `Seu código Chama: ${code}. Não compartilhe com ninguém.`);
    return { retryAfter: PHONE_GAP };
  }
  verify(phone: string, code: string): void {
    const row = this.db.prepare('SELECT code_hash, expires_at, tries FROM otp WHERE phone = ?').get(phone) as
      { code_hash: string; expires_at: number; tries: number } | undefined;
    if (!row) throw new AppError('invalid_code');
    if (this.opts.dev && code === '000000') { this.db.prepare('DELETE FROM otp WHERE phone = ?').run(phone); return; }
    if (row.tries >= MAX_TRIES) throw new AppError('too_many_attempts');
    if (this.opts.now() > row.expires_at) throw new AppError('expired');
    if (this.hash(phone, code) !== row.code_hash) {
      this.db.prepare('UPDATE otp SET tries = tries + 1 WHERE phone = ?').run(phone);
      throw new AppError('invalid_code');
    }
    this.db.prepare('DELETE FROM otp WHERE phone = ?').run(phone);
  }
}
