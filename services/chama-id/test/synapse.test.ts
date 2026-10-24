import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createHmac, randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { openDb } from '../src/db.ts';
import { HttpSynapseAdmin } from '../src/synapse.ts';
import { Accounts } from '../src/accounts.ts';

const SECRET = 'shared-secret';
type Device = { device_id: string; last_seen_ts: number | null };

// Mimics the Synapse endpoints chama-id uses, and checks the registration HMAC.
async function stub() {
  const s = {
    nonces: new Set<string>(), taken: new Set<string>(), registered: [] as string[],
    adminTokens: new Set<string>(), users: new Map<string, Device[]>(), userLastSeen: new Map<string, number | null>(),
    deactivated: [] as { user: string; body: unknown }[], resets: [] as string[],
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
      return send(200, { access_token: token, user_id: `@${body.username}:chama.test`, device_id: 'D' });
    }
    if (p === '/_matrix/client/v3/account/whoami') {
      return bearer === 'good' ? send(200, { user_id: '@ualice:chama.test', device_id: 'D' })
        : send(401, { errcode: 'M_UNKNOWN_TOKEN', error: 'Unknown access token' });
    }
    if (!bearer || !s.adminTokens.has(bearer)) return send(401, { errcode: 'M_UNKNOWN_TOKEN', error: 'Unknown access token' });
    let m;
    if (req.method === 'GET' && (m = p.match(/^\/_synapse\/admin\/v2\/users\/([^/]+)$/))) {
      const user = decodeURIComponent(m[1]);
      return s.users.has(user) ? send(200, { name: user, deactivated: false, last_seen_ts: s.userLastSeen.get(user) ?? null })
        : send(404, { errcode: 'M_NOT_FOUND', error: 'User not found' });
    }
    if (req.method === 'GET' && (m = p.match(/^\/_synapse\/admin\/v2\/users\/([^/]+)\/devices$/))) {
      const devices = s.users.get(decodeURIComponent(m[1]));
      return devices ? send(200, { devices, total: devices.length }) : send(404, { errcode: 'M_NOT_FOUND', error: 'Unknown user' });
    }
    if (req.method === 'POST' && (m = p.match(/^\/_synapse\/admin\/v1\/deactivate\/([^/]+)$/))) {
      s.deactivated.push({ user: decodeURIComponent(m[1]), body });
      return send(200, { id_server_unbind_result: 'success' });
    }
    if (req.method === 'POST' && (m = p.match(/^\/_synapse\/admin\/v1\/users\/([^/]+)\/_allow_cross_signing_replacement_without_uia$/))) {
      const user = decodeURIComponent(m[1]);
      if (!s.users.has(user)) return send(404, { errcode: 'M_NOT_FOUND', error: 'No master key found' });
      s.resets.push(user);
      return send(200, { updatable_without_uia_before_ms: 1_700_000_600_000 });
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
  return { db, admin: new HttpSynapseAdmin({ baseUrl: s.base, sharedSecret: SECRET, db }) };
}
const storedTokens = (db: ReturnType<typeof openDb>) => db.prepare('SELECT token FROM admin_token').all().map((r: any) => r.token);

test('registers an admin with a correct HMAC once, stores and reuses its token', async () => {
  const s = await stub();
  try {
    const { db, admin } = setup(s);
    s.users.set('@ua:chama.test', []);
    assert.equal(await admin.lastActiveMs('@ua:chama.test'), 0);
    assert.equal(await admin.lastActiveMs('@ua:chama.test'), 0);
    assert.deepEqual(s.registered, ['chama-admin']);
    assert.equal(s.badMacs, 0);
    assert.deepEqual(storedTokens(db), ['admin-chama-admin']);
    // A new instance on the same DB (a restart) reuses the stored token.
    await new HttpSynapseAdmin({ baseUrl: s.base, sharedSecret: SECRET, db }).lastActiveMs('@ua:chama.test');
    assert.deepEqual(s.registered, ['chama-admin']);
  } finally { s.close(); }
});
test('concurrent first calls register only one admin', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:chama.test', []);
    await Promise.all([admin.lastActiveMs('@ua:chama.test'), admin.lastActiveMs('@ua:chama.test'), admin.deactivate('@ua:chama.test')]);
    assert.deepEqual(s.registered, ['chama-admin']);
  } finally { s.close(); }
});
test('falls back to chama-admin-2 when chama-admin is taken', async () => {
  const s = await stub();
  try {
    const { db, admin } = setup(s);
    s.taken.add('chama-admin');
    await admin.deactivate('@ua:chama.test');
    assert.deepEqual(s.registered, ['chama-admin-2']);
    assert.deepEqual(storedTokens(db), ['admin-chama-admin-2']);
  } finally { s.close(); }
});
test('a stored token that gets 401 is discarded and a new admin registered', async () => {
  const s = await stub();
  try {
    const { db, admin } = setup(s);
    s.users.set('@ua:chama.test', []);
    await admin.lastActiveMs('@ua:chama.test');
    s.adminTokens.clear(); // e.g. the admin was logged out
    assert.equal(await admin.lastActiveMs('@ua:chama.test'), 0);
    assert.deepEqual(s.registered, ['chama-admin', 'chama-admin-2']);
    assert.deepEqual(storedTokens(db), ['admin-chama-admin-2']);
  } finally { s.close(); }
});
test('wrong shared secret fails instead of looping', async () => {
  const s = await stub();
  try {
    const admin = new HttpSynapseAdmin({ baseUrl: s.base, sharedSecret: 'wrong', db: openDb(':memory:') });
    await assert.rejects(admin.deactivate('@ua:chama.test'), /register/);
    assert.equal(s.badMacs, 1);
  } finally { s.close(); }
});
test('lastActiveMs is the newest device last_seen_ts; unknown user is null', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:chama.test', [{ device_id: 'A', last_seen_ts: 1000 }, { device_id: 'B', last_seen_ts: 5000 }, { device_id: 'C', last_seen_ts: null }]);
    assert.equal(await admin.lastActiveMs('@ua:chama.test'), 5000);
    s.users.set('@ub:chama.test', [{ device_id: 'C', last_seen_ts: null }]);
    assert.equal(await admin.lastActiveMs('@ub:chama.test'), 0);
    assert.equal(await admin.lastActiveMs('@nobody:chama.test'), null);
  } finally { s.close(); }
});
test('deactivate does not erase; cross-signing reset returns the deadline', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:chama.test', []);
    await admin.deactivate('@ua:chama.test');
    assert.deepEqual(s.deactivated, [{ user: '@ua:chama.test', body: { erase: false } }]);
    assert.equal(await admin.allowCrossSigningReset('@ua:chama.test'), 1_700_000_600_000);
    assert.deepEqual(s.resets, ['@ua:chama.test']);
    await assert.rejects(admin.allowCrossSigningReset('@nokeys:chama.test'), /not_found/);
  } finally { s.close(); }
});
test('whoami returns the user id; 401 is invalid_token', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    assert.equal(await admin.whoami('good'), '@ualice:chama.test');
    await assert.rejects(admin.whoami('bad'), (e: any) => e.code === 'invalid_token' && e.status === 401);
    assert.deepEqual(s.registered, [], 'whoami needs no admin token');
  } finally { s.close(); }
});
test('lastActiveMs also counts the user-level last_seen_ts, which survives logout', async () => {
  const s = await stub();
  try {
    const { admin } = setup(s);
    s.users.set('@ua:chama.test', [{ device_id: 'A', last_seen_ts: 1000 }]);
    s.userLastSeen.set('@ua:chama.test', 9000);
    assert.equal(await admin.lastActiveMs('@ua:chama.test'), 9000);
    s.users.set('@ua:chama.test', []); // logged out
    assert.equal(await admin.lastActiveMs('@ua:chama.test'), 9000);
    s.userLastSeen.set('@ua:chama.test', null); // user_ips pruned
    assert.equal(await admin.lastActiveMs('@ua:chama.test'), 0);
  } finally { s.close(); }
});
test('active 100 days, logged out to switch phones, signs in 2 days later: same account', async () => {
  const s = await stub();
  try {
    const DAY = 86400;
    let clock = 1_000_000_000;
    const { db, admin } = setup(s);
    const accounts = new Accounts(db, admin, { serverName: 'chama.test', now: () => clock });
    const a = await accounts.resolve('5511987654321');
    clock += 102 * DAY;
    s.users.set(a.userId, []); // devices gone after logout
    s.userLastSeen.set(a.userId, (clock - 2 * DAY) * 1000);
    assert.deepEqual(await accounts.resolve('5511987654321'), { ...a, created: false });
    assert.deepEqual(s.deactivated, []);
  } finally { s.close(); }
});
