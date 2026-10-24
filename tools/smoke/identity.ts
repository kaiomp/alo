// Identity reset against the real stack (spec §4, §5): a user bootstraps cross-signing, a second
// device signs in, then reset-identity logs that device out and uploads the new public keys
// that this "phone" made. Needs the dev stack (make up). Run by server/scripts/check.sh.
import { generateKeyPairSync, randomInt, sign, type KeyObject } from 'node:crypto';

const BASE = process.env.BASE ?? 'http://localhost:8080';

async function call(method: string, path: string, body?: unknown, token?: string) {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: res.status, body: await res.json().catch(() => ({})) as any };
}
async function ok(method: string, path: string, body?: unknown, token?: string) {
  const r = await call(method, path, body, token);
  if (r.status !== 200) throw new Error(`${method} ${path}: ${r.status} ${JSON.stringify(r.body)}`);
  return r.body;
}

// Matrix canonical JSON: sorted keys, no whitespace. Our values hold no floats.
const canonical = (v: unknown): string => Array.isArray(v) ? `[${v.map(canonical).join(',')}]`
  : v && typeof v === 'object' ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical((v as any)[k])}`).join(',')}}`
  : JSON.stringify(v);
const b64 = (buf: Buffer) => buf.toString('base64').replace(/=+$/, ''); // unpadded base64
const keyPair = () => {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  return { pub: b64(Buffer.from(publicKey.export({ format: 'jwk' }).x!, 'base64url')), priv: privateKey };
};
const signed = (obj: Record<string, unknown>, userId: string, by: { pub: string; priv: KeyObject }) => ({
  ...obj, signatures: { [userId]: { [`ed25519:${by.pub}`]: b64(sign(null, Buffer.from(canonical(obj)), by.priv)) } },
});
// A fresh master key, and self-signing and user-signing keys signed by it.
function crossSigningKeys(userId: string) {
  const [master, ssk, usk] = [keyPair(), keyPair(), keyPair()];
  const key = (usage: string, k: { pub: string }) => ({ user_id: userId, usage: [usage], keys: { [`ed25519:${k.pub}`]: k.pub } });
  return {
    masterPub: master.pub,
    body: {
      master_key: key('master', master),
      self_signing_key: signed(key('self_signing', ssk), userId, master),
      user_signing_key: signed(key('user_signing', usk), userId, master),
    },
  };
}
const expect = (cond: boolean, what: string) => { if (!cond) throw new Error(what); console.log(`ok: ${what}`); };

try {
  const phone = `55119${String(randomInt(1e8)).padStart(8, '0')}`;
  await ok('POST', '/id/v1/otp/request', { phone });
  const v = await ok('POST', '/id/v1/otp/verify', { phone, code: '000000' });
  const userId = v.user_id as string;
  const login = () => ok('POST', '/_matrix/client/v3/login', { type: 'org.matrix.login.jwt', token: v.login_token });
  const d1 = await login(), d2 = await login();
  expect(d1.device_id !== d2.device_id, `${userId} has two devices (${d1.device_id}, ${d2.device_id})`);

  // A second SMS code, as a new phone without the recovery key would request.
  await ok('POST', '/id/v1/otp/request', { phone });
  const reset = (keys: ReturnType<typeof crossSigningKeys>) =>
    call('POST', '/id/v1/account/reset-identity', { phone, code: '000000', keys: keys.body }, d1.access_token);
  let r = await reset(crossSigningKeys(userId));
  expect(r.status === 409 && r.body.error === 'no_identity', `reset before any keys is no_identity: ${r.status} ${JSON.stringify(r.body)}`);

  const upload = (keys: ReturnType<typeof crossSigningKeys>) => call('POST', '/_matrix/client/v3/keys/device_signing/upload', keys.body, d1.access_token);
  r = await upload(crossSigningKeys(userId));
  expect(r.status === 200, `first cross-signing upload needs no UIA: ${r.status}`);
  const next = crossSigningKeys(userId);
  r = await upload(next);
  expect(r.status === 401 && Array.isArray(r.body.flows), `replacing keys from the client needs UIA: ${r.status}`);

  r = await reset(next); // the code was not spent by the no_identity call
  expect(r.status === 200 && r.body.logged_out_devices === 1, `reset-identity: ${JSON.stringify(r.body)}`);
  r = await call('GET', '/_matrix/client/v3/account/whoami', undefined, d2.access_token);
  expect(r.status === 401, `other device's token is dead after reset: ${r.status}`);
  r = await call('GET', '/_matrix/client/v3/account/whoami', undefined, d1.access_token);
  expect(r.status === 200 && r.body.device_id === d1.device_id, `caller's device still works: ${r.status}`);

  const q = await ok('POST', '/_matrix/client/v3/keys/query', { device_keys: { [userId]: [] } }, d1.access_token);
  expect(!!q.master_keys?.[userId]?.keys?.[`ed25519:${next.masterPub}`], 'server now holds the new master key');
  console.log('identity: OK');
} catch (err) {
  console.error(`identity: FAIL: ${(err as Error).message}`);
  process.exit(1);
}
