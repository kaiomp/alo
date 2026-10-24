import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.ts';
import { OtpService } from '../src/otp.ts';
import type { SmsProvider } from '../src/sms.ts';

function setup(dev = false) {
  let clock = 1_000_000;
  const sent: string[] = [];
  const sms: SmsProvider = { async send(_p, text) { sent.push(text); } };
  const svc = new OtpService(openDb(':memory:'), { pepper: 'p', dev, sms, now: () => clock });
  return { svc, sent, tick: (s: number) => { clock += s; } };
}
const code = (text: string) => text.match(/\d{6}/)![0];
const wrong = (c: string) => String((Number(c) + 1) % 1_000_000).padStart(6, '0');
const retryAfter = (n: number) => (e: any) => e.code === 'rate_limited' && e.extra?.retry_after === n;

test('request sends a 6-digit code that verifies once', async () => {
  const { svc, sent } = setup();
  await svc.request('5511987654321', '1.1.1.1');
  svc.verify('5511987654321', code(sent[0]));
  assert.throws(() => svc.verify('5511987654321', code(sent[0])), /invalid_code/);
});
test('code expires after 300 s', async () => {
  const { svc, sent, tick } = setup();
  await svc.request('5511987654321', '1.1.1.1');
  tick(301);
  assert.throws(() => svc.verify('5511987654321', code(sent[0])), /expired/);
});
test('5 wrong tries lock the code', async () => {
  const { svc, sent } = setup();
  await svc.request('5511987654321', '1.1.1.1');
  for (let i = 0; i < 5; i++) assert.throws(() => svc.verify('5511987654321', wrong(code(sent[0]))), /invalid_code/);
  assert.throws(() => svc.verify('5511987654321', code(sent[0])), /too_many_attempts/);
});
test('one request per 60 s per phone', async () => {
  const { svc, tick } = setup();
  await svc.request('5511987654321', '1.1.1.1');
  await assert.rejects(svc.request('5511987654321', '1.1.1.1'), /rate_limited/);
  tick(61);
  await svc.request('5511987654321', '1.1.1.1');
});
test('10 requests per hour per IP', async () => {
  const { svc } = setup();
  for (let i = 0; i < 10; i++) await svc.request(`55119876543${String(i).padStart(2, '0')}`, '2.2.2.2');
  await assert.rejects(svc.request('5511987654399', '2.2.2.2'), /rate_limited/);
});
test('dev mode accepts 000000', async () => {
  const { svc } = setup(true);
  await svc.request('5511987654321', '1.1.1.1');
  svc.verify('5511987654321', '000000');
});
test('codes are not stored in plain text', async () => {
  const db = openDb(':memory:');
  const sent: string[] = [];
  const svc = new OtpService(db, { pepper: 'p', dev: false, sms: { async send(_p, t) { sent.push(t); } } });
  await svc.request('5511987654321', '1.1.1.1');
  const rows = JSON.stringify(db.prepare('SELECT * FROM otp').all());
  assert.ok(!rows.includes(code(sent[0])));
});
test('IP limit reports the real retry_after', async () => {
  const { svc, tick } = setup();
  for (let i = 0; i < 10; i++) await svc.request(`55119876543${String(i).padStart(2, '0')}`, '2.2.2.2');
  tick(100);
  await assert.rejects(svc.request('5511987654399', '2.2.2.2'), retryAfter(3500));
});
test('max 5 code requests per phone per rolling 24 h', async () => {
  const { svc, tick } = setup();
  for (let i = 0; i < 5; i++) { await svc.request('5511987654321', '1.1.1.1'); tick(61); }
  await assert.rejects(svc.request('5511987654321', '1.1.1.1'), retryAfter(86400 - 305));
  tick(86400 - 305);
  await svc.request('5511987654321', '1.1.1.1');
});
test('11th failed verify in 24 h is rate_limited across new codes, even with the right code', async () => {
  const { svc, sent, tick } = setup();
  for (let r = 0; r < 2; r++) {
    await svc.request('5511987654321', '1.1.1.1');
    for (let i = 0; i < 5; i++) assert.throws(() => svc.verify('5511987654321', wrong(code(sent[r]))), /invalid_code/);
    tick(61);
  }
  await svc.request('5511987654321', '1.1.1.1');
  assert.throws(() => svc.verify('5511987654321', code(sent[2])), retryAfter(86400 - 122));
});
test('dev code 000000 bypasses the daily failure cap', async () => {
  const { svc, sent, tick } = setup(true);
  for (let r = 0; r < 2; r++) {
    await svc.request('5511987654321', '1.1.1.1');
    for (let i = 0; i < 5; i++) assert.throws(() => svc.verify('5511987654321', wrong(code(sent[r]))), /invalid_code/);
    tick(61);
  }
  await svc.request('5511987654321', '1.1.1.1');
  svc.verify('5511987654321', '000000');
});
