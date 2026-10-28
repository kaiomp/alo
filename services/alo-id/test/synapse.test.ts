import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createHmac, randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { openDb } from '../src/db.ts';
import { HttpSynapseAdmin } from '../src/synapse.ts';
import { Accounts } from '../src/accounts.ts';

const SECRET = 'shared-secret', AS_TOKEN = 'as-token';
type Device = { device_id: string; last_seen_ts: number | null };

// Mimics the Synapse endpoints alo-id uses, and checks the registration HMAC.
async function stub() {
  const s = {
    nonces: new Set<string>(), taken: new Set<string>(), registered: [] as string[],
    adminTokens: new Set<string>(), users: new Map<string, Device[]>(), userLastSeen: new Map<string, number | null>(),
    deactivated: [] as { user: string; body: unknown }[], dead: new Set<string>(), uploads: [] as { user: string; body: unknown }[], masterKeys: new Set<string>(),
    badMacs: 0, base: '', close: () => {},
  };
  const server = http.createServer(async (req, res) => {
    const chunks: Buffer[] = [];
    for await (const c of req) chunks.push(c);
    const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : undefined;
    const send = (status: number, b: unknown) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(b)); };
    const url = new URL(req.url!, 'http://x');
    const p = url.pathname;
    const bearer = req.headers.authorization?.replace(/^Bearer /, '');
    if (p === '/_synapse/admin/v1/register') {
      if (req.method === 'GET') { const nonce = randomUUID(); s.nonces.add(nonce); return send(200, { nonce }); }
      if (!s.nonces.delete(body.nonce)) return send(400, { errcode: 'M_UNKNOWN', error: 'unrecognised nonce' });
      const want = createHmac('sha1', SECRET).update([body.nonce, body.username, body.password, body.admin ? 'admin' : 'notadmin'].join('\0')).digest('hex');
      if (body.mac !== want || body.admin !== true) { s.badMacs++; return send(403, { errcode: 'M_FORBIDDEN', error: 'HMAC incorrect' }); }
      if (s.taken.has(body.username)) return send(400, { errcode: 'M_USER_IN_USE', error: 'User ID already taken.' });
      s.taken.add(body.username); s.registered.push(body.username);
      const token = `admin-${body.username}`; s.adminTokens.add(token);
      return send(200, { access_token: token, user_id: `@${body.username}:alo.test`, device_id: 'D' });
    }
    if (p === '/_matrix/client/v3/account/whoami') {
      return bearer === 'good' ? send(200, { user_id: '@ualice:alo.test', device_id: 'D' })
        : send(401, { errcode: 'M_UNKNOWN_TOKEN', error: 'Unknown access token' });
    }
    if (p === '/_matrix/client/v3/keys/query' && req.method === 'POST') {
      if (bearer !== 'good') return send(401, { errcode: 'M_UNKNOWN_TOKEN', error: 'Unknown access token' });
      const master_keys = Object.fromEntries(Object.keys(body.device_keys).filter((u) => s.masterKeys.has(u)).map((u) => [u, { user_id: u }]));
      return send(200, { device_keys: {}, master_keys });
    }
    if (p === '/_matrix/client/v3/keys/device_signing/upload' && req.method === 'POST') {
      if (bearer !== AS_TOKEN) return send(401, { errcode: 'M_UNKNOWN_TOKEN', error: 'Unknown access token' });
      if (body.bad) return send(400, { errcode: 'M_INVALID_SIGNATURE', error: 'Invalid signature' });
      s.uploads.push({ user: url.searchParams.get('user_id')!, body });
      return send(200, {});
    }
    if (!bearer || !s.adminTokens.has(bearer)) return send(401, { errcode: 'M_UNKNOWN_TOKEN', error: 'Unknown access token' });
    let m;
    if (req.method === 'GET' && (m = p.match(/^\/_synapse\/admin\/v2\/users\/([^/]+)$/))) {
      const user = decodeURIComponent(m[1]);
      return s.users.has(user) ? send(200, { name: user, deactivated: s.dead.has(user), last_seen_ts: s.userLastSeen.get(user) ?? null })
        : send(404, { errcode: 'M_NOT_FOUND', error: 'User not found' });
    }
    if (req.method === 'GET' && (m = p.match(/^\/_synapse\/admin\/v2\/users\/([^/]+)\/devices$/))) {
      const devices = s.users.get(decodeURIComponent(m[1]));
      return devices ? send(200, { devices, total: devices.length }) : send(404, { errcode: 'M_NOT_FOUND', error: 'Unknown user' });
    }
    if (req.method === 'POST' && (m = p.match(/^\/_synapse\/admin\/v2\/users\/([^/]+)\/delete_devices$/))) {
      const user = decodeURIComponent(m[1]);
      s.users.set(user, (s.users.get(user) ?? []).filter((d) => !body.devices.includes(d.device_id)));
      return send(200, {});
    }
    if (req.method === 'POST' && (m = p.match(/^\/_synapse\/admin\/v1\/deactivate\/([^/]+)$/))) {
      s.deactivated.push({ user: decodeURIComponent(m[1]), body });
      return send(200, { id_server_unbind_result: 'success' });
    }
    send(404, { errcode: 'M_UNRECOGNIZED' });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  s.base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  s.close = () => server.close();
  return s;
}
function setup(s: Awaited<ReturnType<typeof stub>>) {
  const db = openDb(':memory:');
  return { db, admin: new HttpSynapseAdmin({ baseUrl: s.base, sharedSecret: SECRET, asToken: AS_TOKEN, db }) };
}
const lastMs = async (admin: HttpSynapseAdmin, u: string) => (await admin.activity(u))?.lastActiveMs ?? null;
const storedTokens = (db: ReturnType<typeof openDb>) => db.prepare('SELECT token FROM admin_token').all().map((r: any) => r.token);

test('registers an admin with a correct HMAC once, stores and reuses its token', async () => {
  const s = await stub();
  try {
    const { db, admin } = setup(s);
    s.users.set('@ua:alo.test', []);
    assert.equal(await lastMs(admin, '@ua:alo.test'), 0);
    assert.equal(await lastMs(admin, '@ua:alo.test'), 0);
    assert.deepEqual(s.registered, ['alo-admin']);
    assert.equal(s.badMacs, 0);
    assert.deepEqual(storedTokens(db), ['admin-alo-admin']);
    // A new instance on the same DB (a restart) reuses the stored token.
    await new HttpSynapseAdmin({ baseUrl: s.base, sharedSecret: SECRET, asToken: AS_TOKEN, db }).activity('@ua:alo.test');
    assert.deepEqual(s.registered, ['alo-admin']);
  } finally { s.close(); }
});
test('concurrent first calls register only one admin', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:alo.test', []);
    await Promise.all([admin.activity('@ua:alo.test'), admin.activity('@ua:alo.test'), admin.deactivate('@ua:alo.test')]);
    assert.deepEqual(s.registered, ['alo-admin']);
  } finally { s.close(); }
});
test('falls back to alo-admin-2 when alo-admin is taken', async () => {
  const s = await stub();
  try {
    const { db, admin } = setup(s);
    s.taken.add('alo-admin');
    await admin.deactivate('@ua:alo.test');
    assert.deepEqual(s.registered, ['alo-admin-2']);
    assert.deepEqual(storedTokens(db), ['admin-alo-admin-2']);
  } finally { s.close(); }
});
test('a stored token that gets 401 is discarded and a new admin registered', async () => {
  const s = await stub();
  try {
    const { db, admin } = setup(s);
    s.users.set('@ua:alo.test', []);
    await admin.activity('@ua:alo.test');
    s.adminTokens.clear(); // e.g. the admin was logged out
    assert.equal(await lastMs(admin, '@ua:alo.test'), 0);
    assert.deepEqual(s.registered, ['alo-admin', 'alo-admin-2']);
    assert.deepEqual(storedTokens(db), ['admin-alo-admin-2']);
  } finally { s.close(); }
});
test('wrong shared secret fails instead of looping', async () => {
  const s = await stub();
  try {
    const admin = new HttpSynapseAdmin({ baseUrl: s.base, sharedSecret: 'wrong', asToken: AS_TOKEN, db: openDb(':memory:') });
    await assert.rejects(admin.deactivate('@ua:alo.test'), /register/);
    assert.equal(s.badMacs, 1);
  } finally { s.close(); }
});
test('lastActiveMs is the newest device last_seen_ts; unknown user is null', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:alo.test', [{ device_id: 'A', last_seen_ts: 1000 }, { device_id: 'B', last_seen_ts: 5000 }, { device_id: 'C', last_seen_ts: null }]);
    assert.equal(await lastMs(admin, '@ua:alo.test'), 5000);
    s.users.set('@ub:alo.test', [{ device_id: 'C', last_seen_ts: null }]);
    assert.equal(await lastMs(admin, '@ub:alo.test'), 0);
    assert.equal(await lastMs(admin, '@nobody:alo.test'), null);
  } finally { s.close(); }
});
test('activity says whether the account is deactivated', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:alo.test', []);
    assert.deepEqual(await admin.activity('@ua:alo.test'), { lastActiveMs: 0, deactivated: false });
    s.dead.add('@ua:alo.test');
    assert.deepEqual(await admin.activity('@ua:alo.test'), { lastActiveMs: 0, deactivated: true });
  } finally { s.close(); }
});
test('deleteDevices deletes only the listed devices the user has', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:alo.test', [{ device_id: 'A', last_seen_ts: 1 }, { device_id: 'B', last_seen_ts: 2 }]);
    assert.equal(await admin.deleteDevices('@ua:alo.test', ['A', 'Z']), 1);
    assert.deepEqual(s.users.get('@ua:alo.test')!.map((d) => d.device_id), ['B']);
  } finally { s.close(); }
});
test('deactivate does not erase', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:alo.test', []);
    await admin.deactivate('@ua:alo.test');
    assert.deepEqual(s.deactivated, [{ user: '@ua:alo.test', body: { erase: false } }]);
  } finally { s.close(); }
});
test('uploadCrossSigningKeys posts as the user with the application service token', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    const keys = { master_key: { k: 1 }, self_signing_key: { k: 2 }, user_signing_key: { k: 3 } };
    await admin.uploadCrossSigningKeys('@ua:alo.test', keys);
    assert.deepEqual(s.uploads, [{ user: '@ua:alo.test', body: keys }]);
    await assert.rejects(admin.uploadCrossSigningKeys('@ua:alo.test', { ...keys, bad: 1 } as any), (e: any) => e.code === 'invalid_keys' && e.status === 400);
    assert.deepEqual(s.registered, [], 'needs no admin token');
  } finally { s.close(); }
});
test('whoami returns the user id; 401 is invalid_token', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    assert.deepEqual(await admin.whoami('good'), { userId: '@ualice:alo.test', deviceId: 'D' });
    await assert.rejects(admin.whoami('bad'), (e: any) => e.code === 'invalid_token' && e.status === 401);
    assert.deepEqual(s.registered, [], 'whoami needs no admin token');
  } finally { s.close(); }
});
test('lastActiveMs also counts the user-level last_seen_ts, which survives logout', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:alo.test', [{ device_id: 'A', last_seen_ts: 1000 }]);
    s.userLastSeen.set('@ua:alo.test', 9000);
    assert.equal(await lastMs(admin, '@ua:alo.test'), 9000);
    s.users.set('@ua:alo.test', []); // logged out
    assert.equal(await lastMs(admin, '@ua:alo.test'), 9000);
    s.userLastSeen.set('@ua:alo.test', null); // user_ips pruned
    assert.equal(await lastMs(admin, '@ua:alo.test'), 0);
  } finally { s.close(); }
});
test('active 100 days, logged out to switch phones, signs in 2 days later: same account', async () => {
  const s = await stub();
  try {
    const DAY = 86400;
    let clock = 1_000_000_000;
    const { db, admin } = setup(s);
    const accounts = new Accounts(db, admin, { serverName: 'alo.test', now: () => clock });
    const a = await accounts.resolve('5511987654321');
    clock += 102 * DAY;
    s.users.set(a.userId, []); // devices gone after logout
    s.userLastSeen.set(a.userId, (clock - 2 * DAY) * 1000);
    assert.deepEqual(await accounts.resolve('5511987654321'), { ...a, created: false });
    assert.deepEqual(s.deactivated, []);
  } finally { s.close(); }
});
test('hasMasterKey asks keys/query with the user token', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    assert.equal(await admin.hasMasterKey('good', '@ualice:alo.test'), false);
    s.masterKeys.add('@ualice:alo.test');
    assert.equal(await admin.hasMasterKey('good', '@ualice:alo.test'), true);
    await assert.rejects(admin.hasMasterKey('bad', '@ualice:alo.test'), (e: any) => e.code === 'invalid_token');
    assert.deepEqual(s.registered, [], 'needs no admin token');
  } finally { s.close(); }
});
test('logoutOtherDevices deletes every device but the kept one', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:alo.test', [{ device_id: 'A', last_seen_ts: 1 }, { device_id: 'B', last_seen_ts: 2 }, { device_id: 'C', last_seen_ts: null }]);
    assert.equal(await admin.logoutOtherDevices('@ua:alo.test', 'B'), 2);
    assert.deepEqual(s.users.get('@ua:alo.test')!.map((d) => d.device_id), ['B']);
    assert.equal(await admin.logoutOtherDevices('@ua:alo.test', 'B'), 0, 'nothing left to delete');
  } finally { s.close(); }
});
