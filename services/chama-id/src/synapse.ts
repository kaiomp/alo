import { createHmac, randomBytes } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';

// Actions that need Matrix user-interactive auth, which password-less accounts cannot do (spec §4).
export interface SynapseAdmin {
  whoami(accessToken: string): Promise<string>;
  /** Newest device last_seen_ts in ms; 0 when the user has no devices; null when Synapse does not know the user. */
  lastActiveMs(userId: string): Promise<number | null>;
  deactivate(userId: string): Promise<void>;
  /** Returns updatable_without_uia_before_ms. */
  allowCrossSigningReset(userId: string): Promise<number>;
}

// Talks to Synapse on the internal network. Registers its own admin user with the shared secret
// on first use and keeps the token in the `admin_token` table. The token is never logged.
export class HttpSynapseAdmin implements SynapseAdmin {
  private o: { baseUrl: string; sharedSecret: string; db: DatabaseSync; fetch: typeof fetch };
  private registering?: Promise<string>;
  constructor(opts: { baseUrl: string; sharedSecret: string; db: DatabaseSync; fetch?: typeof fetch }) {
    this.o = { ...opts, baseUrl: opts.baseUrl.replace(/\/$/, ''), fetch: opts.fetch ?? fetch };
  }

  private req(path: string, token: string, method = 'GET', body?: unknown) {
    return this.o.fetch(this.o.baseUrl + path, {
      method, body: body === undefined ? undefined : JSON.stringify(body),
      headers: { authorization: `Bearer ${token}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    });
  }

  private async register(): Promise<string> {
    const url = `${this.o.baseUrl}/_synapse/admin/v1/register`;
    // Limit: linear probe of chama-admin, chama-admin-2, ...; only grows when a token is lost.
    for (let n = 1; n <= 100; n++) {
      const username = n === 1 ? 'chama-admin' : `chama-admin-${n}`;
      const nr = await this.o.fetch(url);
      if (!nr.ok) throw new Error(`synapse register nonce: HTTP ${nr.status}`);
      const { nonce } = await nr.json() as { nonce: string };
      const password = randomBytes(32).toString('hex'); // never used: password login is disabled
      const mac = createHmac('sha1', this.o.sharedSecret).update([nonce, username, password, 'admin'].join('\0')).digest('hex');
      const r = await this.o.fetch(url, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ nonce, username, password, admin: true, mac }),
      });
      const b = await r.json().catch(() => ({})) as { access_token?: string; errcode?: string };
      if (r.ok && b.access_token) {
        this.o.db.prepare('INSERT OR REPLACE INTO admin_token (id, token) VALUES (1, ?)').run(b.access_token);
        console.log(`registered Synapse admin ${username}`);
        return b.access_token;
      }
      if (b.errcode !== 'M_USER_IN_USE') throw new Error(`synapse register ${username}: HTTP ${r.status} ${b.errcode ?? ''}`);
    }
    throw new Error('synapse register: no free chama-admin name');
  }

  private token(): Promise<string> {
    const row = this.o.db.prepare('SELECT token FROM admin_token WHERE id = 1').get() as { token: string } | undefined;
    if (row) return Promise.resolve(row.token);
    return this.registering ??= this.register().finally(() => { this.registering = undefined; });
  }

  // Admin call; a 401 means the stored token is dead, so it is replaced once and the call retried.
  private async admin(path: string, method = 'GET', body?: unknown): Promise<Response> {
    const token = await this.token();
    const r = await this.req(path, token, method, body);
    if (r.status !== 401) return r;
    this.o.db.prepare('DELETE FROM admin_token WHERE token = ?').run(token);
    return this.req(path, await this.token(), method, body);
  }

  private async ok(r: Response, what: string) {
    if (!r.ok) throw new Error(`synapse ${what}: HTTP ${r.status}`);
    return r.json() as Promise<any>;
  }

  async whoami(accessToken: string): Promise<string> {
    const r = await this.req('/_matrix/client/v3/account/whoami', accessToken);
    if (r.status === 401) throw new AppError('invalid_token');
    const b = await this.ok(r, 'whoami');
    if (typeof b.user_id !== 'string') throw new Error('synapse whoami: no user_id');
    return b.user_id;
  }

  async lastActiveMs(userId: string): Promise<number | null> {
    const r = await this.admin(`/_synapse/admin/v2/users/${encodeURIComponent(userId)}/devices`);
    if (r.status === 404) return null;
    const { devices } = await this.ok(r, 'devices') as { devices: { last_seen_ts: number | null }[] };
    return Math.max(0, ...devices.map((d) => d.last_seen_ts ?? 0));
  }

  async deactivate(userId: string): Promise<void> {
    await this.ok(await this.admin(`/_synapse/admin/v1/deactivate/${encodeURIComponent(userId)}`, 'POST', { erase: false }), 'deactivate');
  }

  async allowCrossSigningReset(userId: string): Promise<number> {
    const r = await this.admin(`/_synapse/admin/v1/users/${encodeURIComponent(userId)}/_allow_cross_signing_replacement_without_uia`, 'POST', {});
    if (r.status === 404) throw new AppError('not_found'); // user has no cross-signing keys yet
    const b = await this.ok(r, 'cross-signing reset');
    return b.updatable_without_uia_before_ms;
  }
}
