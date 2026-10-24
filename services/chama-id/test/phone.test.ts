import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizePhone } from '../src/phone.ts';

test('normalises Brazilian mobile formats', () => {
  assert.equal(normalizePhone('(11) 98765-4321'), '5511987654321');
  assert.equal(normalizePhone('+55 11 98765 4321'), '5511987654321');
  assert.equal(normalizePhone('5511987654321'), '5511987654321');
});
test('accepts foreign numbers with +', () => {
  assert.equal(normalizePhone('+49 176 62096183'), '4917662096183');
});
test('rejects garbage', () => {
  assert.throws(() => normalizePhone('123'), /invalid_phone/);
  assert.throws(() => normalizePhone('abc'), /invalid_phone/);
});
test('accepts bare national numbers with trunk 0', () => {
  assert.equal(normalizePhone('011987654321'), '5511987654321');
});
