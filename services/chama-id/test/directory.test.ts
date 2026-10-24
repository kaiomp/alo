import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { openDb } from '../src/db.ts';
import { Directory } from '../src/directory.ts';

const h = (s: string) => createHash('sha256').update(s).digest('hex');
const dir = () => new Directory(openDb(':memory:'), 'chama.test');
test('lookup returns the Matrix ID of registered hashes only', () => {
  const d = dir();
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa');
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa'); // idempotent
  assert.deepEqual(d.lookup([h('5511987654321'), h('5511900000000')]),
    [{ hash: h('5511987654321'), user_id: '@uaaaaaaaaaaaaaaaa:chama.test' }]);
});
test('lookup returns the current account after a number is recycled', () => {
  const d = dir();
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa');
  d.markRegistered('5511987654321', 'ubbbbbbbbbbbbbbbb');
  assert.deepEqual(d.lookup([h('5511987654321')]), [{ hash: h('5511987654321'), user_id: '@ubbbbbbbbbbbbbbbb:chama.test' }]);
});
test('lookup caps input at 1000 hashes', () => {
  assert.throws(() => dir().lookup(Array(1001).fill(h('1'))), /bad_request/);
});
test('lookup rejects non-string hashes', () => {
  assert.throws(() => dir().lookup([[h('1')]] as unknown as string[]), /bad_request/);
});
test('lookup de-duplicates input', () => {
  const d = dir();
  d.markRegistered('5511987654321', 'uaaaaaaaaaaaaaaaa');
  assert.equal(d.lookup([h('5511987654321'), h('5511987654321')]).length, 1);
});
