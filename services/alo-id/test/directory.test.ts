import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { openDb } from '../src/db.ts';
import { Directory } from '../src/directory.ts';

const at = { now: 1_000_000 };

const h = (s: string) => createHash('sha256').update(s).digest('hex');
const dir = () => new Directory(openDb(':memory:'), 'alo.test');
test('lookup returns the Matrix ID of registered hashes only', () => {
  const d = dir();
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa');
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa'); // idempotent
  assert.deepEqual(d.lookup([h('5511987654321'), h('5511900000000')], '@a:alo.test', at),
    [{ hash: h('5511987654321'), user_id: '@uaaaaaaaaaaaaaaaa:alo.test' }]);
});
test('lookup returns the current account after a number is recycled', () => {
  const d = dir();
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa');
  d.markRegistered('5511987654321', 'ubbbbbbbbbbbbbbbb');
  assert.deepEqual(d.lookup([h('5511987654321')], '@a:alo.test', at), [{ hash: h('5511987654321'), user_id: '@ubbbbbbbbbbbbbbbb:alo.test' }]);
});
test('lookup caps input at 1000 hashes', () => {
  assert.throws(() => dir().lookup(Array(1001).fill(h('1')), '@a:alo.test', at), /bad_request/);
});
test('lookup rejects non-string hashes', () => {
  assert.throws(() => dir().lookup([[h('1')]] as unknown as string[], '@a:alo.test', at), /bad_request/);
});
test('lookup de-duplicates input', () => {
  const d = dir();
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa');
  assert.equal(d.lookup([h('5511987654321'), h('5511987654321')], '@a:alo.test', at).length, 1);
});
test('each account may look up 10 000 distinct hashes per day', () => {
  const d = dir();
  const batch = (from: number) => Array.from({ length: 1000 }, (_, i) => h(String(from + i)));
  for (let i = 0; i < 10; i++) d.lookup(batch(i * 1000), '@a:alo.test', { now: 1000 + i });
  assert.throws(() => d.lookup([h('x')], '@a:alo.test', { now: 2000 }),
    (e: any) => e.code === 'rate_limited' && e.extra.retry_after === 1000 + 86400 - 2000);
  d.lookup([h('x')], '@b:alo.test', { now: 2000 }); // other accounts keep their own quota
  d.lookup([h('x')], '@a:alo.test', { now: 1000 + 86400 }); // a day after the first lookup
});
test('a request is charged its distinct hashes only, and not at all when invalid', () => {
  const d = dir();
  d.lookup(Array(1000).fill(h('same')), '@a:alo.test', { now: 0, quota: 2 });
  d.lookup([h('other')], '@a:alo.test', { now: 0, quota: 2 });
  assert.throws(() => d.lookup(['nothex'], '@a:alo.test', { now: 0, quota: 2 }), /bad_request/);
  assert.throws(() => d.lookup([h('third')], '@a:alo.test', { now: 0, quota: 2 }), /rate_limited/);
});
