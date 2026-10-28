import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { signJwt, verifyJwt } from '../src/jwt.ts';

test('round-trips claims and sets iat/exp', () => {
  const t = signJwt({ sub: '5511987654321', iss: 'alo-id', aud: 'alo' }, 's3cret', 120, 1_000_000);
  const c = verifyJwt(t, 's3cret', 1_000_010);
  assert.equal(c.sub, '5511987654321');
  assert.equal(c.iat, 1_000_000);
  assert.equal(c.exp, 1_000_120);
});
test('rejects wrong secret, tampering and expiry', () => {
  const t = signJwt({ sub: 'x' }, 'a', 120, 1_000_000);
  assert.throws(() => verifyJwt(t, 'b', 1_000_000), /invalid_token/);
  const [h, , s] = t.split('.');
  const forged = `${h}.${Buffer.from('{"sub":"y"}').toString('base64url')}.${s}`;
  assert.throws(() => verifyJwt(forged, 'a', 1_000_000), /invalid_token/);
  assert.throws(() => verifyJwt(t, 'a', 1_000_121), /invalid_token/);
});
test('signed null payload is invalid_token, not a crash', () => {
  const data = `${Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url')}.${Buffer.from('null').toString('base64url')}`;
  const t = `${data}.${createHmac('sha256', 'a').update(data).digest('base64url')}`;
  assert.throws(() => verifyJwt(t, 'a', 1_000_000), /invalid_token/);
});
