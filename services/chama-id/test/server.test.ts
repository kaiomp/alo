import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import { openDb } from '../src/db.ts';
import { OtpService } from '../src/otp.ts';
import { Directory } from '../src/directory.ts';
import { verifyJwt } from '../src/jwt.ts';
import { createServer } from '../src/server.ts';
import { rateKey, windowLimiter } from '../src/http.ts';
import { connect } from 'node:net';

function make(now?: () => number) {
  const db = openDb(':memory:');
  return createServer({
    otp: new OtpService(db, { pepper: 'p', dev: true, sms: { async send() {} } }),
    directory: new Directory(db), jwtSecret: 'jwt', serverName: 'chama.test', publicBaseUrl: 'http://localhost:8080', now,
  });
}
const listen = async (s: Server) => {
  await new Promise<void>((r) => s.listen(0, r));
  return `http://127.0.0.1:${(s.address() as AddressInfo).port}`;
};

let base = '';
const server = make();
before(async () => { base = await listen(server); });
after(() => server.close());
const post = (path: string, body: unknown, headers: Record<string, string> = {}, at = base) =>
  fetch(at + path, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });

test('health', async () => {
  assert.deepEqual(await (await fetch(`${base}/id/v1/health`)).json(), { ok: true });
});
test('full sign-in flow returns a valid JWT', async () => {
  const r1 = await post('/id/v1/otp/request', { phone: '(11) 98765-4321' });
  assert.equal(r1.status, 200);
  assert.deepEqual(await r1.json(), { phone: '5511987654321', retry_after: 60 });
  const r2 = await post('/id/v1/otp/verify', { phone: '+55 11 98765-4321', code: '000000' });
  const body = await r2.json();
  assert.equal(r2.status, 200);
  assert.equal(body.user_id, '@5511987654321:chama.test');
  assert.equal(body.homeserver, 'http://localhost:8080');
  const claims = verifyJwt(body.login_token, 'jwt');
  assert.equal(claims.sub, '5511987654321');
  assert.equal(claims.iss, 'chama-id');
  assert.equal(claims.aud, 'chama');
  assert.equal(Number(claims.exp) - Number(claims.iat), 120);
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
test('directory lookup after verify', async () => {
  const h = createHash('sha256').update('5511987654321').digest('hex');
  const r = await post('/id/v1/directory/lookup', { hashes: [h] });
  assert.deepEqual(await r.json(), { registered: [h] });
});

test('directory lookup is capped at 30 per IP per rolling hour', async () => {
  let clock = 1_000_000;
  const s = make(() => clock);
  const at = await listen(s);
  try {
    const look = (ip: string) => post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': `${ip}, 10.0.0.1` }, at);
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

const hex = (i: number) => createHash('sha256').update(String(i)).digest('hex');
test('lookup validates hashes over HTTP and fits 1000 hashes in one request', async () => {
  assert.equal((await post('/id/v1/directory/lookup', { hashes: 'abc' })).status, 400);
  assert.equal((await post('/id/v1/directory/lookup', {})).status, 400);
  assert.equal((await post('/id/v1/directory/lookup', { hashes: Array.from({ length: 1001 }, (_, i) => hex(i)) })).status, 400);
  const r = await post('/id/v1/directory/lookup', { hashes: Array.from({ length: 1000 }, (_, i) => hex(i)) });
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
  const s = make(() => 1_000_000);
  const at = await listen(s);
  try {
    const look = (ip: string) => post('/id/v1/directory/lookup', { hashes: [] }, { 'x-forwarded-for': ip }, at);
    for (let i = 0; i < 30; i++) assert.equal((await look(`2001:db8:a:b::${(i + 1).toString(16)}`)).status, 200);
    assert.equal((await look('2001:db8:a:b:dead:beef:0:1')).status, 429);
    assert.equal((await look('2001:db8:a:c::1')).status, 200, 'other /64 has its own budget');
    for (let i = 0; i < 30; i++) assert.equal((await look(i % 2 ? '9.9.9.9' : '::ffff:9.9.9.9')).status, 200);
    assert.equal((await look('9.9.9.9')).status, 429);
  } finally { s.close(); }
});
test('OTP per-IP limit also groups IPv6 by /64', async () => {
  const s = make();
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
const secrets = { JWT_SECRET: 'j', OTP_PEPPER: 'p', SERVER_NAME: 'chama.test', PUBLIC_BASEURL: 'http://localhost:8080' };

test('refuses to start without an SMS provider outside dev mode', () => {
  const r = start(secrets);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /no SMS provider configured \(set CHAMA_DEV=1 for development\)/);
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
