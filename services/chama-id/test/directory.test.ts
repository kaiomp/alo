import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { openDb } from '../src/db.ts';
import { Directory } from '../src/directory.ts';

const h = (s: string) => createHash('sha256').update(s).digest('hex');
test('lookup returns only registered hashes', () => {
  const d = new Directory(openDb(':memory:'));
  d.markRegistered('5511987654321');
  d.markRegistered('5511987654321'); // idempotent
  assert.deepEqual(d.lookup([h('5511987654321'), h('5511900000000')]), [h('5511987654321')]);
});
test('lookup caps input at 1000 hashes', () => {
  const d = new Directory(openDb(':memory:'));
  assert.throws(() => d.lookup(Array(1001).fill(h('1'))), /bad_request/);
});
test('lookup rejects non-string hashes', () => {
  const d = new Directory(openDb(':memory:'));
  assert.throws(() => d.lookup([[h('1')]] as unknown as string[]), /bad_request/);
});
test('lookup de-duplicates input', () => {
  const d = new Directory(openDb(':memory:'));
  d.markRegistered('5511987654321');
  assert.deepEqual(d.lookup([h('5511987654321'), h('5511987654321')]), [h('5511987654321')]);
});
