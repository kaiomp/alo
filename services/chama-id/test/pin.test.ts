import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.ts';
import { Pins, RESET_WAIT } from '../src/pin.ts';

function setup() {
  let clock = 1_000_000;
  const db = openDb(':memory:');
  return { db, pins: new Pins(db, { pepper: 'p', now: () => clock }), tick: (s: number) => { clock += s; } };
}
const LP = 'uaaaaaaaaaaaaaaaa';
const code = (e: any) => e.code + (e.extra?.retry_after !== undefined ? `:${e.extra.retry_after}` : '');

test('a set PIN checks; a wrong one is invalid_pin; no PIN always passes', async () => {
  const { pins } = setup();
  assert.equal(pins.state(LP), 'none');
  await pins.check(LP, undefined);
  await pins.set(LP, '123456');
  assert.equal(pins.state(LP), 'set');
  assert.deepEqual(pins.status(LP), { set: true, reset_at: null });
  await pins.check(LP, '123456');
  await assert.rejects(pins.check(LP, '654321'), (e: any) => code(e) === 'invalid_pin');
  await assert.rejects(pins.check(LP, undefined), (e: any) => code(e) === 'pin_required');
  await assert.rejects(pins.check(LP, 'abc'), (e: any) => code(e) === 'invalid_pin');
});
test('only six digits can be set', async () => {
  const { pins } = setup();
  for (const pin of ['12345', '1234567', 'abcdef', '12 456', '']) {
    await assert.rejects(pins.set(LP, pin), (e: any) => e.code === 'bad_request', pin);
  }
});
test('the hash is salted, peppered argon2id: never the PIN, different per account', async () => {
  const { db, pins } = setup();
  await pins.set(LP, '123456');
  await pins.set('ubbbbbbbbbbbbbbbb', '123456');
  const rows = db.prepare('SELECT hash, salt FROM pins').all() as { hash: string; salt: string }[];
  assert.equal(rows.length, 2);
  assert.notEqual(rows[0].hash, rows[1].hash);
  assert.ok(rows.every((r) => r.hash.length === 64 && !r.hash.includes('123456')));
  const other = new Pins(db, { pepper: 'other' });
  await assert.rejects(other.check(LP, '123456'), (e: any) => e.code === 'invalid_pin', 'the pepper is part of the hash');
});
test('four free wrong tries, then 1 min, 5 min, 1 h and 24 h locks; a right PIN clears them', async () => {
  const { pins, tick } = setup();
  await pins.set(LP, '123456');
  for (let i = 0; i < 4; i++) await assert.rejects(pins.check(LP, '000000'), (e: any) => code(e) === 'invalid_pin');
  for (const wait of [60, 300, 3600, 86400, 86400]) {
    await assert.rejects(pins.check(LP, '000000'), (e: any) => code(e) === `invalid_pin:${wait}`);
    await assert.rejects(pins.check(LP, '123456'), (e: any) => code(e) === `pin_locked:${wait}`, 'even the right PIN waits');
    tick(wait);
  }
  await pins.check(LP, '123456');
  await assert.rejects(pins.check(LP, '000000'), (e: any) => code(e) === 'invalid_pin', 'counter back to zero');
});
test('parallel guesses cannot get past the lock', async () => {
  const { pins } = setup();
  await pins.set(LP, '123456');
  const results = await Promise.allSettled(Array.from({ length: 20 }, (_, i) => pins.check(LP, String(100000 + i))));
  const codes = results.map((r) => r.status === 'rejected' ? (r.reason as any).code : 'ok');
  assert.equal(codes.filter((c) => c === 'invalid_pin').length, 5, 'four free tries and the one that set the lock');
  assert.equal(codes.filter((c) => c === 'pin_locked').length, 15);
});
test('a forgotten PIN: the reset is due after 7 days; asking again keeps the date; cancel and set clear it', async () => {
  const { pins, tick } = setup();
  assert.throws(() => pins.requestReset(LP), (e: any) => e.code === 'bad_request', 'nothing to reset');
  await pins.set(LP, '123456');
  const at = pins.requestReset(LP);
  assert.equal(at, 1_000_000 + RESET_WAIT);
  tick(86400);
  assert.equal(pins.requestReset(LP), at);
  assert.deepEqual(pins.status(LP), { set: true, reset_at: at });
  tick(RESET_WAIT - 86400 - 1);
  assert.equal(pins.state(LP), 'set');
  tick(1);
  assert.equal(pins.state(LP), 'reset_due');
  pins.cancelReset(LP);
  assert.equal(pins.state(LP), 'set');
  pins.requestReset(LP);
  await pins.set(LP, '654321');
  assert.deepEqual(pins.status(LP), { set: true, reset_at: null }, 'a new PIN ends the wait');
  pins.remove(LP);
  assert.equal(pins.state(LP), 'none');
});
