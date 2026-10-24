// M4 account safety against the real stack (spec §4, §5): a one-time login token without
// user-interactive auth, the link rendezvous, device removal through chama-id, and the account PIN.
// Needs the dev stack (make up). Run by server/scripts/check.sh.
import { randomInt } from 'node:crypto';

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
const expect = (cond: boolean, what: string) => { if (!cond) throw new Error(what); console.log(`ok: ${what}`); };
const newPhone = () => `55119${String(randomInt(1e8)).padStart(8, '0')}`;
const verify = async (phone: string) => {
  await ok('POST', '/id/v1/otp/request', { phone });
  return ok('POST', '/id/v1/otp/verify', { phone, code: '000000' });
};
const jwtLogin = (token: string) => ok('POST', '/_matrix/client/v3/login', { type: 'org.matrix.login.jwt', token });
const whoami = (token: string) => call('GET', '/_matrix/client/v3/account/whoami', undefined, token);

try {
  const phone = newPhone();
  const v = await verify(phone);
  const d1 = await jwtLogin(v.login_token);

  // Linking (spec §5): a signed-in device gets a one-time token with no password prompt.
  const flows = (await ok('GET', '/_matrix/client/v3/login')).flows as { type: string; get_login_token?: boolean }[];
  expect(flows.some((f) => f.type === 'm.login.token' && f.get_login_token === true), 'login flows offer m.login.token with get_login_token');
  const t = await ok('POST', '/_matrix/client/v1/login/get_token', {}, d1.access_token);
  expect(typeof t.login_token === 'string' && t.expires_in_ms === 120_000, `get_token without UIA: expires in ${t.expires_in_ms} ms`);
  const again = await call('POST', '/_matrix/client/v1/login/get_token', {}, d1.access_token);
  expect(again.status === 429, `a second token within a minute is refused: ${again.status}`);
  const d2 = await ok('POST', '/_matrix/client/v3/login', { type: 'm.login.token', token: t.login_token, initial_device_display_name: 'Chama Web' });
  expect(d2.user_id === v.user_id && d2.device_id !== d1.device_id, `m.login.token signs in a new device ${d2.device_id}`);
  const reuse = await call('POST', '/_matrix/client/v3/login', { type: 'm.login.token', token: t.login_token });
  expect(reuse.status === 403, `the login token is single use: ${reuse.status}`);

  // The rendezvous relays boxes only.
  const box = { ciphertext: 'Y2lwaGVy', mac: 'bWFj', ephemeral: 'ZXBo' };
  const { id } = await ok('POST', '/id/v1/link', {});
  await ok('POST', '/id/v1/link/offer', { id, box }, d1.access_token);
  expect((await ok('POST', '/id/v1/link/poll', { id })).offer?.mac === 'bWFj', 'link: the web sees the offer');
  await ok('POST', '/id/v1/link/answer', { id, box }, d2.access_token);
  expect((await ok('POST', '/id/v1/link/poll', { id })).answer?.mac === 'bWFj', 'link: the phone sees the answer');

  // "Aparelhos conectados": the phone removes the web device with a fresh SMS code.
  const devices = (await ok('GET', '/_matrix/client/v3/devices', undefined, d1.access_token)).devices as { device_id: string }[];
  expect(devices.length === 2, `the account lists 2 devices`);
  await ok('POST', '/id/v1/otp/request', { phone });
  const removed = await ok('POST', '/id/v1/devices/remove', { device_ids: [d2.device_id], code: '000000' }, d1.access_token);
  expect(removed.removed === 1, 'devices/remove deleted the web device');
  expect((await whoami(d2.access_token)).status === 401, 'its token is dead at once');
  expect((await whoami(d1.access_token)).status === 200, "the caller's device still works");

  // Account PIN: a new sign-in needs it, and the PIN step's token is no Matrix login.
  await ok('POST', '/id/v1/pin/set', { pin: '135790' }, d1.access_token);
  const p = await verify(phone);
  expect(p.pin_required === true && !p.login_token, 'with a PIN the SMS code alone gives no login');
  const asLogin = await call('POST', '/_matrix/client/v3/login', { type: 'org.matrix.login.jwt', token: p.pin_token });
  expect(asLogin.status === 403, `Synapse refuses the pin_token as a login: ${asLogin.status}`);
  const wrong = await call('POST', '/id/v1/pin/login', { pin_token: p.pin_token, pin: '000000' });
  expect(wrong.status === 400 && wrong.body.error === 'invalid_pin', 'a wrong PIN is refused');
  const right = await ok('POST', '/id/v1/pin/login', { pin_token: p.pin_token, pin: '135790' });
  const d3 = await jwtLogin(right.login_token);
  expect(d3.user_id === v.user_id, 'the right PIN signs in the same account');
  await ok('POST', '/id/v1/pin/remove', { pin: '135790' }, d3.access_token);
  expect(!!(await verify(phone)).login_token, 'PIN removed: the SMS code signs in again');
  console.log('safety: OK');
} catch (err) {
  console.error(`safety: FAIL: ${(err as Error).message}`);
  process.exit(1);
}
