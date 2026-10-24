import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.ts';
import { Accounts } from '../src/accounts.ts';
import type { SynapseAdmin } from '../src/synapse.ts';

const DAY = 86400;
class FakeAdmin implements SynapseAdmin {
  active = new Map<string, number | null>();
  deactivated: string[] = [];
  failDeactivate = false;
  async whoami(): Promise<string> { throw new Error('unused'); }
  async lastActiveMs(u: string) { return this.active.get(u) ?? null; }
  async deactivate(u: string) { if (this.failDeactivate) throw new Error('synapse down'); this.deactivated.push(u); }
  async allowCrossSigningReset() { return 0; }
}
function setup() {
  let clock = 1_000_000_000;
  const db = openDb(':memory:');
  const admin = new FakeAdmin();
  const accounts = new Accounts(db, admin, { serverName: 'chama.test', now: () => clock });
  return { db, admin, accounts, tick: (s: number) => { clock += s; }, nowMs: () => clock * 1000 };
}
const PHONE = '5511987654321';

test('new phone gets an opaque localpart', async () => {
  const { accounts } = setup();
  const a = await accounts.resolve(PHONE);
  assert.match(a.localpart, /^u[a-z2-7]{16}$/);
  assert.equal(a.userId, `@${a.localpart}:chama.test`);
  assert.equal(a.created, true);
  assert.ok(!a.userId.includes('987654321'));
  assert.deepEqual(accounts.current(PHONE), { localpart: a.localpart, userId: a.userId });
  assert.equal(accounts.current('5511900000000'), null);
});
test('localparts differ per phone', async () => {
  const { accounts } = setup();
  assert.notEqual((await accounts.resolve(PHONE)).localpart, (await accounts.resolve('5511900000000')).localpart);
});
test('account active 1 day ago is reused', async () => {
  const { accounts, admin, tick, nowMs } = setup();
  const a = await accounts.resolve(PHONE);
  tick(30 * DAY);
  admin.active.set(a.userId, nowMs() - DAY * 1000);
  const b = await accounts.resolve(PHONE);
  assert.deepEqual(b, { ...a, created: false });
  assert.deepEqual(admin.deactivated, []);
});
test('account never logged in (unknown to Synapse) is reused', async () => {
  const { accounts, tick } = setup();
  const a = await accounts.resolve(PHONE);
  tick(100 * DAY);
  assert.deepEqual(await accounts.resolve(PHONE), { ...a, created: false });
});
test('account inactive for 46 days is deactivated and replaced (recycled number)', async () => {
  const { db, accounts, admin, tick, nowMs } = setup();
  const a = await accounts.resolve(PHONE);
  tick(200 * DAY);
  admin.active.set(a.userId, nowMs() - 46 * DAY * 1000);
  const b = await accounts.resolve(PHONE);
  assert.deepEqual(admin.deactivated, [a.userId]);
  assert.equal(b.created, true);
  assert.notEqual(b.localpart, a.localpart);
  assert.match(b.localpart, /^u[a-z2-7]{16}$/);
  assert.deepEqual(accounts.current(PHONE), { localpart: b.localpart, userId: b.userId });
  assert.deepEqual(db.prepare('SELECT phone, localpart FROM retired_accounts').all().map((r) => ({ ...r })),
    [{ phone: PHONE, localpart: a.localpart }]);
});
test('a recent sign-in keeps the account even with no devices (logout, then sign in again)', async () => {
  const { accounts, admin, tick } = setup();
  const a = await accounts.resolve(PHONE);
  tick(10 * DAY);
  admin.active.set(a.userId, 0); // logged out: Synapse has no devices
  assert.deepEqual(await accounts.resolve(PHONE), { ...a, created: false });
  assert.deepEqual(admin.deactivated, []);
});
test('failed deactivation keeps the old mapping', async () => {
  const { accounts, admin, tick } = setup();
  const a = await accounts.resolve(PHONE);
  tick(100 * DAY);
  admin.active.set(a.userId, 0);
  admin.failDeactivate = true;
  await assert.rejects(accounts.resolve(PHONE), /synapse down/);
  assert.deepEqual(accounts.current(PHONE), { localpart: a.localpart, userId: a.userId });
});
test('concurrent sign-ins for a recycled number agree on one new account', async () => {
  const { db, accounts, admin, tick } = setup();
  const a = await accounts.resolve(PHONE);
  tick(100 * DAY);
  admin.active.set(a.userId, 0);
  const [b, c] = await Promise.all([accounts.resolve(PHONE), accounts.resolve(PHONE)]);
  assert.equal(b.localpart, c.localpart);
  assert.notEqual(b.localpart, a.localpart);
  assert.equal([b.created, c.created].filter(Boolean).length, 1);
  assert.equal((db.prepare('SELECT COUNT(*) AS n FROM retired_accounts').get() as { n: number }).n, 1);
});
