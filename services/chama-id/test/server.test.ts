import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { openDb } from '../src/db.ts';
import { OtpService } from '../src/otp.ts';
import { Directory } from '../src/directory.ts';
import { Accounts } from '../src/accounts.ts';
import { AppError } from '../src/errors.ts';
import type { SynapseAdmin } from '../src/synapse.ts';
import { verifyJwt } from '../src/jwt.ts';
import { createServer } from '../src/server.ts';
import { rateKey, windowLimiter, ttlCache } from '../src/http.ts';
import { connect } from 'node:net';

// Any token `tok-<x>` belongs to `@<x>:chama.test`, on device DEV-<x>.
class FakeAdmin implements SynapseAdmin {
  whoamiCalls = 0; uploads: [string, unknown][] = []; logouts: [string, string][] = []; noMasterKey = new Set<string>();
  async whoami(t: string) {
    this.whoamiCalls++;
    if (!t.startsWith('tok-')) throw new AppError('invalid_token');
    return { userId: `@${t.slice(4)}:chama.test`, deviceId: `DEV-${t.slice(4)}` };
  }
  async hasMasterKey(_t: string, u: string) { return !this.noMasterKey.has(u); }
  async logoutOtherDevices(u: string, keep: string) { this.logouts.push([u, keep]); return 2; }
  async lastActiveMs() { return null; }
  async deactivate() {}
  async uploadCrossSigningKeys(u: string, keys: unknown) { this.uploads.push([u, keys]); }
}
// A public cross-signing bundle as the client sends it (signatures are Synapse's job).
const bundle = (userId: string) => Object.fromEntries((['master', 'self_signing', 'user_signing'] as const).map((u) =>
  [`${u}_key`, { user_id: userId, usage: [u], keys: { [`ed25519:${u}`]: u } }]));
function make(o: { now?: () => number; dev?: boolean } = {}) {
  const db = openDb(':memory:');
  const admin = new FakeAdmin();
  const codes = new Map<string, string>();
  const server = createServer({
    otp: new OtpService(db, { pepper: 'p', dev: !!o.dev, now: o.now, sms: { async send(p, t) { codes.set(p, t.match(/\d{6}/)![0]); } } }),
    directory: new Directory(db, 'chama.test'), accounts: new Accounts(db, admin, { serverName: 'chama.test', now: o.now }), admin,
    jwtSecret: 'jwt', publicBaseUrl: 'http://localhost:8080', dev: o.dev, now: o.now,
  });
  return { server, admin, codes };
}
const listen = async (s: Server) => {
  await new Promise<void>((r) => s.listen(0, r));
  return `http://127.0.0.1:${(s.address() as AddressInfo).port}`;
};

let base = '';
const main = make();
const server = main.server;
before(async () => { base = await listen(server); });
after(() => server.close());
const post = (path: string, body: unknown, headers: Record<string, string> = {}, at = base) =>
  fetch(at + path, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });
const bearer = (localpart: string) => ({ authorization: `Bearer tok-${localpart}` });
const sha = (s: string) => createHash('sha256').update(s).digest('hex');
// Requests a code and verifies it; returns the verify response body.
async function signIn(m: ReturnType<typeof make>, at: string, phone: string, ip = '7.7.7.7') {
  const r1 = await post('/id/v1/otp/request', { phone }, { 'x-forwarded-for': ip }, at);
  assert.equal(r1.status, 200, await r1.clone().text());
  const p = (await r1.json()).phone;
  const r2 = await post('/id/v1/otp/verify', { phone, code: m.codes.get(p) }, {}, at);
  assert.equal(r2.status, 200);
  return r2.json();
}

test('health', async () => {
  assert.deepEqual(await (await fetch(`${base}/id/v1/health`)).json(), { ok: true });
});
test('sign-in returns an opaque user_id and a JWT for its localpart', async () => {
  const r1 = await post('/id/v1/otp/request', { phone: '(11) 98765-4321' });
  assert.equal(r1.status, 200);
  assert.deepEqual(await r1.json(), { phone: '5511987654321', retry_after: 60 });
  const r2 = await post('/id/v1/otp/verify', { phone: '+55 11 98765-4321', code: main.codes.get('5511987654321') });
  const body = await r2.json();
  assert.equal(r2.status, 200);
  assert.deepEqual(Object.keys(body).sort(), ['homeserver', 'login_token', 'new_account', 'phone', 'user_id']);
  assert.match(body.user_id, /^@u[a-z2-7]{16}:chama\.test$/);
  assert.equal(body.phone, '5511987654321');
  assert.equal(body.new_account, true);
  assert.equal(body.homeserver, 'http://localhost:8080');
  const claims = verifyJwt(body.login_token, 'jwt');
  assert.equal(`@${claims.sub}:chama.test`, body.user_id);
  assert.equal(claims.iss, 'chama-id');
  assert.equal(claims.aud, 'chama');
  assert.equal(Number(claims.exp) - Number(claims.iat), 120);
});
test('signing in again returns the same account with new_account false', async () => {
  let clock = 1_000_000;
  const m = make({ now: () => clock });
  const at = await listen(m.server);
  try {
    const a = await signIn(m, at, '11987654321');
    clock += 61;
    const b = await signIn(m, at, '11987654321');
    assert.equal(b.user_id, a.user_id);
    assert.equal(b.new_account, false);
  } finally { m.server.close(); }
});
test('typed errors', async () => {
  const r = await post('/id/v1/otp/request', { phone: 'nope' });
  assert.equal(r.status, 400);
  assert.deepEqual(await r.json(), { error: 'invalid_phone' });
  const r2 = await fetch(`${base}/id/v1/nope`);
  assert.equal(r2.status, 404);
  assert.deepEqual(await r2.json(), { error: 'not_found' });
  const r3 = await fetch(`${base}/id/v1/otp/request`, { method: 'POST', body: '{bad' });
  assert.equal(r3.status, 400);
  assert.deepEqual(await r3.json(), { error: 'bad_request' });
});
test('non-object JSON bodies and wrong field types are bad_request, not 500', async () => {
  for (const body of [null, 5, 'x', [1]]) {
    const r = await post('/id/v1/otp/request', body);
    assert.equal(r.status, 400, JSON.stringify(body));
  }
  const r = await post('/id/v1/otp/verify', { phone: '11987654321', code: 123456 });
  assert.equal(r.status, 400);
});
test('body over 16 KiB is bad_request', async () => {
  const r = await post('/id/v1/otp/request', { phone: 'x'.repeat(17_000) });
  assert.equal(r.status, 400);
  assert.deepEqual(await r.json(), { error: 'bad_request' });
});
test('rate limit carries retry_after', async () => {
  await post('/id/v1/otp/request', { phone: '11912345678' });
  const r = await post('/id/v1/otp/request', { phone: '11912345678' });
  assert.equal(r.status, 429);
  const body = await r.json();
  assert.equal(body.error, 'rate_limited');
  assert.equal(typeof body.retry_after, 'number');
});
test('directory lookup needs a valid bearer token', async () => {
  const h = sha('5511987654321');
  for (const headers of [{}, { authorization: 'Bearer nope' }, { authorization: 'Basic tok-x' }, { authorization: 'Bearer ' }]) {
    const r = await post('/id/v1/directory/lookup', { hashes: [h] }, headers);
    assert.equal(r.status, 401, JSON.stringify(headers));
    assert.deepEqual(await r.json(), { error: 'invalid_token' });
  }
});
test('directory lookup after verify returns hash and user_id', async () => {
  const me = await signIn(main, base, '11955554444');
  const r = await post('/id/v1/directory/lookup', { hashes: [sha('5511955554444'), sha('5511900000000')] }, bearer('someone'));
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { registered: [{ hash: sha('5511955554444'), user_id: me.user_id }] });
});

test('directory lookup is capped at 30 per IP per rolling hour', async () => {
  let clock = 1_000_000;
  const { server: s } = make({ now: () => clock });
  const at = await listen(s);
  try {
    let n = 0;
    const look = (ip: string) => post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': `${ip}, 10.0.0.1`, ...bearer(`u${n++}`) }, at);
    for (let i = 0; i < 30; i++) { assert.equal((await look('1.1.1.1')).status, 200); clock += 10; }
    const r = await look('1.1.1.1');
    assert.equal(r.status, 429);
    // The oldest call was at 1_000_000; it leaves the window at 1_003_600.
    assert.deepEqual(await r.json(), { error: 'rate_limited', retry_after: 1_000_000 + 3600 - clock });
    assert.equal((await look('2.2.2.2')).status, 200, 'other IPs keep their own budget');
    clock = 1_000_000 + 3600;
    assert.equal((await look('1.1.1.1')).status, 200, 'oldest call left the window');
  } finally { s.close(); }
});
test('directory lookup is capped at 30 per user per rolling hour, across IPs', async () => {
  let clock = 1_000_000;
  const { server: s } = make({ now: () => clock });
  const at = await listen(s);
  try {
    const look = (ip: number, who: string) => post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': `3.3.3.${ip}`, ...bearer(who) }, at);
    for (let i = 0; i < 30; i++) { assert.equal((await look(i, 'alice')).status, 200); clock += 10; }
    const r = await look(99, 'alice');
    assert.equal(r.status, 429);
    assert.deepEqual(await r.json(), { error: 'rate_limited', retry_after: 1_000_000 + 3600 - clock });
    assert.equal((await look(99, 'bob')).status, 200, 'other users keep their own budget');
  } finally { s.close(); }
});
test('dev mode raises the per-IP and per-user lookup limits 100x', async () => {
  const m = make({ now: () => 1_000_000, dev: true });
  const at = await listen(m.server);
  try {
    for (let i = 0; i < 3000; i += 50) {
      const rs = await Promise.all(Array.from({ length: 50 }, () =>
        post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': '4.4.4.4', ...bearer('alice') }, at)));
      assert.deepEqual(rs.map((r) => r.status), Array(50).fill(200), `calls ${i}..${i + 49}`);
    }
    assert.equal((await post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': '4.4.4.5', ...bearer('alice') }, at)).status, 429, 'per-user');
    assert.equal((await post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': '4.4.4.4', ...bearer('bob') }, at)).status, 429, 'per-IP');
  } finally { m.server.close(); }
});
test('whoami results are cached for 60 s', async () => {
  let clock = 1_000_000;
  const m = make({ now: () => clock });
  const at = await listen(m.server);
  try {
    const look = () => post('/id/v1/directory/lookup', { hashes: [] }, bearer('alice'), at);
    await look(); await look();
    assert.equal(m.admin.whoamiCalls, 1);
    clock += 61;
    await look();
    assert.equal(m.admin.whoamiCalls, 2);
  } finally { m.server.close(); }
});
test('ttlCache expires entries and never holds more than maxKeys', () => {
  let t = 0;
  const c = ttlCache<string>({ ttl: 60, maxKeys: 2, now: () => t });
  c.set('a', 'A'); c.set('b', 'B'); c.set('c', 'C');
  assert.equal(c.size(), 2);
  assert.equal(c.get('a'), undefined, 'oldest dropped when full');
  assert.equal(c.get('c'), 'C');
  t = 60;
  assert.equal(c.get('c'), undefined, 'expired');
});

test('reset-identity checks the code and that the token belongs to the phone', async () => {
  let clock = 1_000_000;
  const m = make({ now: () => clock });
  const at = await listen(m.server);
  try {
    const me = await signIn(m, at, '11977776666');
    const lp = me.user_id.slice(1, me.user_id.indexOf(':'));
    clock += 61;
    await post('/id/v1/otp/request', { phone: '11977776666' }, {}, at);
    const code = m.codes.get('5511977776666');
    const keys = bundle(me.user_id);
    const reset = (headers: Record<string, string>, c = code, k: unknown = keys) =>
      post('/id/v1/account/reset-identity', { phone: '11977776666', code: c, keys: k }, headers, at);

    let r = await reset({});
    assert.equal(r.status, 401);
    assert.deepEqual(await r.json(), { error: 'invalid_token' });
    r = await reset(bearer('someoneelse'));
    assert.equal(r.status, 403);
    assert.deepEqual(await r.json(), { error: 'forbidden' });
    assert.deepEqual(m.admin.uploads, []);
    const bad = [null, [], 'x', { ...keys, master_key: undefined }, bundle('@uother:chama.test'),
      { ...keys, self_signing_key: { ...keys.self_signing_key, usage: ['master'] } }, { ...keys, user_signing_key: { ...keys.user_signing_key, keys: {} } },
      { ...keys, auth: { type: 'm.login.dummy' } }, // exactly the three keys
      { ...keys, master_key: { ...keys.master_key, private_key: 'secret' } }, // only public-key fields
      { ...keys, master_key: { ...keys.master_key, usage: ['master', 'self_signing'] } },
      { ...keys, master_key: { ...keys.master_key, keys: { 'ed25519:x': 1 } } }];
    for (const [i, k] of bad.entries()) {
      r = await reset({ ...bearer(lp), 'x-forwarded-for': `8.8.8.${i}` }, code, k); // own IP: the reset limit is 10 per IP
      assert.equal(r.status, 400, JSON.stringify(k));
      assert.equal(r.status, 400, JSON.stringify(bad));
      assert.deepEqual(await r.json(), { error: 'bad_request' });
    }
    r = await reset(bearer(lp), code === '000000' ? '111111' : '000000');
    assert.equal(r.status, 400);
    assert.deepEqual(await r.json(), { error: 'invalid_code' });
    assert.deepEqual(m.admin.logouts, [], 'no logout before the code is checked');
    r = await reset(bearer(lp));
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), { logged_out_devices: 2 });
    assert.deepEqual(m.admin.uploads, [[me.user_id, keys]], 'the bundle is uploaded as the user');
    assert.deepEqual(m.admin.logouts, [[me.user_id, `DEV-${lp}`]], 'every device but the caller is logged out');
    r = await reset(bearer(lp));
    assert.equal(r.status, 400, 'the code is single use');
  } finally { m.server.close(); }
});
test('reset-identity without a master key is no_identity (409) and keeps the code', async () => {
  let clock = 1_000_000;
  const m = make({ now: () => clock });
  const at = await listen(m.server);
  try {
    const me = await signIn(m, at, '11966665555');
    const lp = me.user_id.slice(1, me.user_id.indexOf(':'));
    clock += 61;
    await post('/id/v1/otp/request', { phone: '11966665555' }, {}, at);
    const code = m.codes.get('5511966665555');
    const reset = () => post('/id/v1/account/reset-identity', { phone: '11966665555', code, keys: bundle(me.user_id) }, bearer(lp), at);
    m.admin.noMasterKey.add(me.user_id);
    const r = await reset();
    assert.equal(r.status, 409);
    assert.deepEqual(await r.json(), { error: 'no_identity' });
    assert.deepEqual(m.admin.logouts, []);
    assert.deepEqual(m.admin.uploads, []);
    m.admin.noMasterKey.clear();
    assert.equal((await reset()).status, 200, 'the code was not spent');
  } finally { m.server.close(); }
});
test('reset-identity body is capped at 8 KiB', async () => {
  const r = await post('/id/v1/account/reset-identity', { phone: '11987654321', code: '000000', keys: { pad: 'x'.repeat(9000) } }, bearer('x'));
  assert.equal(r.status, 400);
  assert.deepEqual(await r.json(), { error: 'bad_request' });
});
test('reset-identity is capped at 10 per IP per hour', async () => {
  const { server: s } = make({ now: () => 1_000_000 });
  const at = await listen(s);
  try {
    const reset = (ip: string) => post('/id/v1/account/reset-identity', { phone: '11933332222', code: '123456' }, { 'x-forwarded-for': ip, ...bearer('x') }, at);
    for (let i = 0; i < 10; i++) assert.equal((await reset('5.5.5.5')).status, 403);
    assert.equal((await reset('5.5.5.5')).status, 429);
    assert.equal((await reset('5.5.5.6')).status, 403, 'other IPs keep their own budget');
  } finally { s.close(); }
});
test('reset-identity for a phone with no account is forbidden', async () => {
  const m = make();
  const at = await listen(m.server);
  try {
    await post('/id/v1/otp/request', { phone: '11933332222' }, {}, at);
    const r = await post('/id/v1/account/reset-identity', { phone: '11933332222', code: m.codes.get('5511933332222') }, bearer('x'), at);
    assert.equal(r.status, 403);
  } finally { m.server.close(); }
});

const hex = (i: number) => createHash('sha256').update(String(i)).digest('hex');
test('lookup validates hashes over HTTP and fits 1000 hashes in one request', async () => {
  const look = (body: unknown) => post('/id/v1/directory/lookup', body, bearer('validator'));
  assert.equal((await look({ hashes: 'abc' })).status, 400);
  assert.equal((await look({})).status, 400);
  assert.equal((await look({ hashes: Array.from({ length: 1001 }, (_, i) => hex(i)) })).status, 400);
  const r = await look({ hashes: Array.from({ length: 1000 }, (_, i) => hex(i)) });
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { registered: [] });
});
test('other routes keep the 16 KiB body cap', async () => {
  const r = await post('/id/v1/otp/verify', { phone: '11987654321', code: 'x'.repeat(20_000) });
  assert.equal(r.status, 400);
});
test('malformed request target is bad_request, not 500', async () => {
  const { port } = server.address() as AddressInfo;
  const raw = await new Promise<string>((resolve, reject) => {
    let out = '';
    const sock = connect(port, '127.0.0.1', () => sock.end('GET http://[ HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n'));
    sock.on('data', (c) => { out += c; }).on('end', () => resolve(out)).on('error', reject);
  });
  assert.match(raw, /^HTTP\/1\.1 400/);
  assert.match(raw, /"error":"bad_request"/);
});

test('rateKey groups IPv6 by /64 and unwraps IPv4-mapped addresses', () => {
  assert.equal(rateKey('2001:db8:1:2::1'), rateKey('2001:db8:1:2:ffff:1:2:3'));
  assert.equal(rateKey('2001:db8:1:2::1'), rateKey('2001:0DB8:0001:0002::9%eth0'));
  assert.notEqual(rateKey('2001:db8:1:2::1'), rateKey('2001:db8:1:3::1'));
  assert.equal(rateKey('::ffff:1.2.3.4'), '1.2.3.4');
  assert.equal(rateKey('::ffff:102:304'), '1.2.3.4');
  assert.equal(rateKey('1.2.3.4'), '1.2.3.4');
  assert.equal(rateKey('unknown'), 'unknown');
});
test('two IPv6 addresses in one /64 share the lookup budget; IPv4-mapped equals IPv4', async () => {
  const { server: s } = make({ now: () => 1_000_000 });
  const at = await listen(s);
  try {
    let n = 0;
    const look = (ip: string) => post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': ip, ...bearer(`v6u${n++}`) }, at);
    for (let i = 0; i < 30; i++) assert.equal((await look(`2001:db8:a:b::${(i + 1).toString(16)}`)).status, 200);
    assert.equal((await look('2001:db8:a:b:dead:beef:0:1')).status, 429);
    assert.equal((await look('2001:db8:a:c::1')).status, 200, 'other /64 has its own budget');
    for (let i = 0; i < 30; i++) assert.equal((await look(i % 2 ? '9.9.9.9' : '::ffff:9.9.9.9')).status, 200);
    assert.equal((await look('9.9.9.9')).status, 429);
  } finally { s.close(); }
});
test('OTP per-IP limit also groups IPv6 by /64', async () => {
  const { server: s } = make();
  const at = await listen(s);
  try {
    const req = (i: number) => post('/id/v1/otp/request', { phone: `1198765${String(4300 + i)}` }, { 'x-forwarded-for': `2001:db8:5:6::${i + 1}` }, at);
    for (let i = 0; i < 10; i++) assert.equal((await req(i)).status, 200);
    const r = await req(10);
    assert.equal(r.status, 429);
    assert.equal((await r.json()).error, 'rate_limited');
  } finally { s.close(); }
});
test('limiter map never grows past maxKeys and frees keys after the window', () => {
  let t = 1000;
  const l = windowLimiter({ limit: 30, window: 3600, maxKeys: 3, now: () => t });
  for (const k of ['a', 'b', 'c']) l.hit(k);
  assert.throws(() => l.hit('d'), (e: any) => e.code === 'rate_limited' && e.extra.retry_after === 3600);
  l.hit('a');
  assert.equal(l.size(), 3);
  t += 3600;
  l.hit('d');
  assert.equal(l.size(), 1, 'stale keys swept once the window passed');
});

const start = (env: Record<string, string>) => spawnSync(process.execPath, ['src/server.ts'], {
  cwd: new URL('..', import.meta.url), encoding: 'utf8', timeout: 10_000,
  env: { PATH: process.env.PATH ?? '', DB_PATH: ':memory:', PORT: '0', ...env },
});
const secrets = {
  JWT_SECRET: 'j', OTP_PEPPER: 'p', SERVER_NAME: 'chama.test', PUBLIC_BASEURL: 'http://localhost:8080',
  SYNAPSE_INTERNAL_URL: 'http://127.0.0.1:1', REGISTRATION_SHARED_SECRET: 'r', SYNAPSE_AS_TOKEN: 'a',
};
// Starts the real server and resolves with its first stdout line, or rejects if it exits first.
const startsListening = (env: Record<string, string>) => new Promise<string>((resolve, reject) => {
  const p = spawn(process.execPath, ['src/server.ts'], {
    cwd: new URL('..', import.meta.url), env: { PATH: process.env.PATH ?? '', DB_PATH: ':memory:', PORT: '0', ...env },
  });
  let err = '';
  p.stderr.on('data', (c) => { err += c; });
  p.stdout.once('data', (c) => { p.kill(); resolve(String(c)); });
  p.on('exit', (code) => reject(new Error(`exited ${code}: ${err}`)));
});

test('refuses to start without an SMS provider outside dev mode', () => {
  const r = start(secrets);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /no SMS provider configured \(set CHAMA_DEV=1 for development\)/);
});
test('refuses dev mode unless the server name ends in .test or .localhost', () => {
  for (const SERVER_NAME of ['chama.chat', 'chama.test.com', 'localhost.chama.chat', 'test']) {
    const r = start({ ...secrets, CHAMA_DEV: '1', SERVER_NAME });
    assert.equal(r.status, 1, SERVER_NAME);
    assert.match(r.stderr, /CHAMA_DEV=1 is only allowed for \.test or \.localhost server names/);
  }
});
test('starts in dev mode for .test and .localhost server names', async () => {
  for (const SERVER_NAME of ['chama.test', 'chama.localhost']) {
    assert.match(await startsListening({ ...secrets, CHAMA_DEV: '1', SERVER_NAME }), /chama-id listening/);
  }
});
test('refuses to start when a secret is missing or empty', () => {
  for (const k of Object.keys(secrets)) {
    for (const v of [undefined, '']) {
      const env: Record<string, string> = { ...secrets, CHAMA_DEV: '1' };
      if (v === undefined) delete env[k]; else env[k] = v;
      const r = start(env);
      assert.equal(r.status, 1, `${k}=${v}`);
      assert.match(r.stderr, new RegExp(`missing env ${k}`));
    }
  }
});
test('refuses to start with an invalid PORT', () => {
  for (const PORT of ['abc', '70000', '-1', '80.5']) {
    const r = start({ ...secrets, CHAMA_DEV: '1', PORT });
    assert.equal(r.status, 1, PORT);
    assert.match(r.stderr, /invalid PORT/);
  }
});
