import { createHmac, randomBytes } from 'node:crypto';
import type { DatabaseSync } from 'node:sqlite';
import { AppError } from './errors.ts';

// Actions that need Matrix user-interactive auth, which password-less accounts cannot do (spec §4).
export interface SynapseAdmin {
  whoami(accessToken: string): Promise<{ userId: string; deviceId?: string }>;
  /** True when the user has a master cross-signing key. Asked with the user's own token. */
  hasMasterKey(accessToken: string, userId: string): Promise<boolean>;
  /** Deletes every device of the user except `keepDeviceId` (this also kills their access tokens); returns how many. */
  logoutOtherDevices(userId: string, keepDeviceId: string): Promise<number>;
  /** Deletes those of `deviceIds` the user has (and their access tokens); returns how many. */
  deleteDevices(userId: string, deviceIds: string[]): Promise<number>;
  /** Last activity in ms (devices and user-level last_seen; 0 when none is left) and whether the account
   *  is deactivated; null when Synapse does not know the user. */
  activity(userId: string): Promise<{ lastActiveMs: number; deactivated: boolean } | null>;
  deactivate(userId: string): Promise<void>;
  /** Uploads public cross-signing keys as the user, through the application service, so no UIA is asked. */
  uploadCrossSigningKeys(userId: string, keys: CrossSigningKeys): Promise<void>;
}
export type CrossSigningKeys = Record<'master_key' | 'self_signing_key' | 'user_signing_key', object>;

// Talks to Synapse on the internal network. Registers its own admin user with the shared secret
// on first use and keeps the token in the `admin_token` table. `asToken` is the application
// service token (server/synapse/appservice.yaml.tmpl). No token is ever logged.
export class HttpSynapseAdmin implements SynapseAdmin {
  private o: { baseUrl: string; sharedSecret: string; asToken: string; db: DatabaseSync; fetch: typeof fetch };
  private registering?: Promise<string>;
  constructor(opts: { baseUrl: string; sharedSecret: string; asToken: string; db: DatabaseSync; fetch?: typeof fetch }) {
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

  async whoami(accessToken: string): Promise<{ userId: string; deviceId?: string }> {
    const r = await this.req('/_matrix/client/v3/account/whoami', accessToken);
    if (r.status === 401) throw new AppError('invalid_token');
    const b = await this.ok(r, 'whoami');
    if (typeof b.user_id !== 'string') throw new Error('synapse whoami: no user_id');
    return { userId: b.user_id, deviceId: typeof b.device_id === 'string' ? b.device_id : undefined };
  }

  async hasMasterKey(accessToken: string, userId: string): Promise<boolean> {
    const r = await this.req('/_matrix/client/v3/keys/query', accessToken, 'POST', { device_keys: { [userId]: [] } });
    if (r.status === 401) throw new AppError('invalid_token');
    const b = await this.ok(r, 'keys query');
    return !!b.master_keys?.[userId];
  }

  private async removeDevices(userId: string, which: (deviceId: string) => boolean): Promise<number> {
    const id = encodeURIComponent(userId);
    const { devices } = await this.ok(await this.admin(`/_synapse/admin/v2/users/${id}/devices`), 'devices') as { devices: { device_id: string }[] };
    const gone = devices.map((d) => d.device_id).filter(which);
    if (gone.length) await this.ok(await this.admin(`/_synapse/admin/v2/users/${id}/delete_devices`, 'POST', { devices: gone }), 'delete devices');
    return gone.length;
  }
  logoutOtherDevices(userId: string, keepDeviceId: string) { return this.removeDevices(userId, (d) => d !== keepDeviceId); }
  deleteDevices(userId: string, deviceIds: string[]) { return this.removeDevices(userId, (d) => deviceIds.includes(d)); }

  // Newest of: any current device's last_seen_ts, and the user-level last_seen_ts (MAX over user_ips,
  // which survives logout until Synapse prunes it after user_ips_max_age).
  async activity(userId: string): Promise<{ lastActiveMs: number; deactivated: boolean } | null> {
    const id = encodeURIComponent(userId);
    const u = await this.admin(`/_synapse/admin/v2/users/${id}`);
    if (u.status === 404) return null;
    const { last_seen_ts, deactivated } = await this.ok(u, 'user') as { last_seen_ts: number | null; deactivated: boolean };
    const r = await this.admin(`/_synapse/admin/v2/users/${id}/devices`);
    if (r.status === 404) return null;
    const { devices } = await this.ok(r, 'devices') as { devices: { last_seen_ts: number | null }[] };
    return { lastActiveMs: Math.max(0, last_seen_ts ?? 0, ...devices.map((d) => d.last_seen_ts ?? 0)), deactivated: !!deactivated };
  }

  async deactivate(userId: string): Promise<void> {
    await this.ok(await this.admin(`/_synapse/admin/v1/deactivate/${encodeURIComponent(userId)}`, 'POST', { erase: false }), 'deactivate');
  }

  // Synapse skips UIA for application services (it honours the admin "replace without UIA"
  // flag only with MAS). It still checks that the sub-keys are signed by the new master key.
  async uploadCrossSigningKeys(userId: string, keys: CrossSigningKeys): Promise<void> {
    const r = await this.req(`/_matrix/client/v3/keys/device_signing/upload?user_id=${encodeURIComponent(userId)}`, this.o.asToken, 'POST', keys);
    if (r.status === 400) throw new AppError('invalid_keys');
    await this.ok(r, 'cross-signing upload');
  }
}
