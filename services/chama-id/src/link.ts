import { randomBytes } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';

// Each step (create, offer) gives the next one this long (spec §5: entries expire after 2 minutes).
export const LINK_TTL = 120;
// The web polls about every 2 s; this caps a stuck or hostile poller per entry.
const MAX_POLLS = 200;
const B64 = /^[A-Za-z0-9+/]+={0,2}$/;

// A box is vodozemac's PkEncryption output (curve25519, AES, HMAC), all base64.
export type Box = { ciphertext: string; mac: string; ephemeral: string };
export function box(v: unknown): Box {
  const o = v as Record<string, unknown> | null;
  const ok = typeof o === 'object' && o !== null && !Array.isArray(o) && Object.keys(o).length === 3 &&
    (['ciphertext', 'mac', 'ephemeral'] as const).every((k) => typeof o[k] === 'string' && B64.test(o[k] as string)) &&
    (o.ciphertext as string).length + (o.mac as string).length + (o.ephemeral as string).length <= 4096;
  if (!ok) throw new AppError('bad_request');
  return { ciphertext: o.ciphertext as string, mac: o.mac as string, ephemeral: o.ephemeral as string };
}

// Device-link rendezvous (spec §5). The web shows {id, its public key} in a QR code; the key never
// reaches chama-id, so it relays only boxes it cannot open or forge. The phone posts the offer (a
// login token for the web), the web the answer (its device keys), each once.
export class Links {
  private db: DatabaseSync;
  private now: () => number;
  constructor(db: DatabaseSync, o: { now?: () => number } = {}) {
    this.db = db;
    this.now = o.now ?? (() => Math.floor(Date.now() / 1000));
  }
  create(): { id: string; expires_in: number } {
    const now = this.now();
    this.db.prepare('DELETE FROM links WHERE expires_at <= ?').run(now);
    const id = randomBytes(16).toString('base64url');
    this.db.prepare('INSERT INTO links (id, expires_at) VALUES (?, ?)').run(id, now + LINK_TTL);
    return { id, expires_in: LINK_TTL };
  }
  private live(id: unknown) {
    const row = typeof id === 'string' ? this.db.prepare('SELECT user_id, offer, answer FROM links WHERE id = ? AND expires_at > ?').get(id, this.now()) : undefined;
    if (!row) throw new AppError('not_found');
    return row as { user_id: string | null; offer: string | null; answer: string | null };
  }
  offer(id: unknown, userId: string, b: Box) {
    if (this.live(id).offer !== null) throw new AppError('conflict');
    this.db.prepare('UPDATE links SET offer = ?, user_id = ?, expires_at = ? WHERE id = ? AND offer IS NULL')
      .run(JSON.stringify(b), userId, this.now() + LINK_TTL, id as string);
  }
  // Only the account that made the offer can answer: the web is signed in by then.
  answer(id: unknown, userId: string, b: Box) {
    const row = this.live(id);
    if (row.offer === null || row.answer !== null) throw new AppError('conflict');
    if (row.user_id !== userId) throw new AppError('forbidden');
    this.db.prepare('UPDATE links SET answer = ? WHERE id = ? AND answer IS NULL').run(JSON.stringify(b), id as string);
  }
  poll(id: unknown): { offer: Box | null; answer: Box | null } {
    this.live(id);
    const row = this.db.prepare('UPDATE links SET polls = polls + 1 WHERE id = ? AND polls < ? RETURNING offer, answer')
      .get(id as string, MAX_POLLS) as { offer: string | null; answer: string | null } | undefined;
    if (!row) throw new AppError('rate_limited', { retry_after: LINK_TTL });
    return { offer: row.offer && JSON.parse(row.offer), answer: row.answer && JSON.parse(row.answer) };
  }
}
