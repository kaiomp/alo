// Recycled numbers over HTTP against the real Synapse (spec §4, issue #3). server/scripts/check.sh
// pipes this file to node inside the alo-id container, so imports are relative to its /app/services/alo-id.
// A second alo-id on 127.0.0.1:8099, sharing the real database, counts every account as inactive
// (inactiveDays 0), as if 45 days had passed. Plain JavaScript: node reads it from stdin.
import { randomInt } from 'node:crypto';
import { openDb } from './src/db.ts';
import { HttpSynapseAdmin } from './src/synapse.ts';
import { OtpService } from './src/otp.ts';
import { Directory } from './src/directory.ts';
import { Accounts } from './src/accounts.ts';
import { Pins } from './src/pin.ts';
import { Links } from './src/link.ts';
import { createServer } from './src/server.ts';

const e = process.env;
const db = openDb(e.DB_PATH);
const admin = new HttpSynapseAdmin({ baseUrl: e.SYNAPSE_INTERNAL_URL, sharedSecret: e.REGISTRATION_SHARED_SECRET, asToken: e.SYNAPSE_AS_TOKEN, db });
const server = createServer({
  otp: new OtpService(db, { pepper: e.OTP_PEPPER, dev: true, sms: { async send() {} } }),
  directory: new Directory(db, e.SERVER_NAME), accounts: new Accounts(db, admin, { serverName: e.SERVER_NAME, inactiveDays: 0 }), admin,
  pins: new Pins(db, { pepper: e.OTP_PEPPER }), links: new Links(db), jwtSecret: e.JWT_SECRET, publicBaseUrl: e.PUBLIC_BASEURL, dev: true,
});
await new Promise((r) => server.listen(8099, '127.0.0.1', r));
const OLD = 'http://127.0.0.1:8099', NOW = `http://127.0.0.1:${e.PORT || 8090}`;

const post = async (base, path, body, token) => {
  const r = await fetch(base + path, { method: 'POST', body: JSON.stringify(body),
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) } });
  return { status: r.status, body: await r.json().catch(() => ({})) };
};
const expect = (cond, what) => { if (!cond) throw new Error(what); console.log(`ok: ${what}`); };
const newPhone = () => `55119${String(randomInt(1e8)).padStart(8, '0')}`;
const signIn = async (base, phone) => {
  await post(base, '/id/v1/otp/request', { phone });
  return (await post(base, '/id/v1/otp/verify', { phone, code: '000000' })).body;
};
const matrix = async (jwt) => (await post(e.SYNAPSE_INTERNAL_URL, '/_matrix/client/v3/login', { type: 'org.matrix.login.jwt', token: jwt })).body;
const alive = async (token) => (await fetch(`${e.SYNAPSE_INTERNAL_URL}/_matrix/client/v3/account/whoami`, { headers: { authorization: `Bearer ${token}` } })).status === 200;

try {
  // An inactive account is retired and the number gets a fresh one.
  let phone = newPhone();
  const a = await signIn(NOW, phone);
  const ta = (await matrix(a.login_token)).access_token;
  expect(a.new_account === true && a.login_token && ta, 'setup: a fresh account signed in on Matrix');
  const b = await signIn(OLD, phone);
  expect(b.new_account === true && b.user_id !== a.user_id, 'inactive account: the number gets a fresh account');
  expect(!(await alive(ta)), "the old account's token is dead (deactivated)");

  // With a PIN it is never retired: the sign-in waits for the PIN, on the same account.
  phone = newPhone();
  const c = await signIn(NOW, phone);
  const tc = (await matrix(c.login_token)).access_token;
  expect(c.new_account === true && c.login_token && tc, 'setup: a fresh account signed in on Matrix');
  expect((await post(NOW, '/id/v1/pin/set', { pin: '246802' }, tc)).status === 200, 'PIN set');
  const d = await signIn(OLD, phone);
  expect(d.pin_required === true, 'inactive account with a PIN: the PIN is asked, nothing retired');
  const dl = (await post(OLD, '/id/v1/pin/login', { pin_token: d.pin_token, pin: '246802' })).body;
  expect(dl.user_id === c.user_id && dl.new_account === false, 'the right PIN signs in the same account');
  expect(await alive(tc), 'and its device still works');

  // Deactivated another way (an operator): the next sign-in gets a fresh account, even on the normal server.
  phone = newPhone();
  const f = await signIn(NOW, phone);
  const tf = (await matrix(f.login_token)).access_token;
  expect(f.new_account === true && f.login_token && tf, 'setup: a fresh account signed in on Matrix');
  await admin.deactivate(f.user_id);
  expect(!(await alive(tf)), "the deactivated account's token is dead");
  const g = await signIn(NOW, phone);
  expect(g.new_account === true && g.user_id !== f.user_id, 'deactivated account: the number gets a fresh account');
  console.log('recycled: OK');
} catch (err) {
  console.error(`recycled: FAIL: ${err.message}`);
  process.exitCode = 1;
} finally {
  server.close();
}
