import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDb } from '../src/db.ts';
import { Links, box, LINK_TTL } from '../src/link.ts';

function setup() {
  let clock = 1_000_000;
  const db = openDb(':memory:');
  return { db, links: new Links(db, { now: () => clock }), tick: (s: number) => { clock += s; } };
}
const B = { ciphertext: 'Y2lwaGVy', mac: 'bWFj', ephemeral: 'ZXBo+/' };
const code = (e: any) => e.code;

test('offer, then answer by the same account, each once; poll sees both', () => {
  const { links } = setup();
  const { id, expires_in } = links.create();
  assert.match(id, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(expires_in, LINK_TTL);
  assert.deepEqual(links.poll(id), { offer: null, answer: null });
  assert.throws(() => links.answer(id, '@ua:chama.test', B), (e) => code(e) === 'conflict', 'no offer yet');
  links.offer(id, '@ua:chama.test', B);
  assert.throws(() => links.offer(id, '@ub:chama.test', B), (e) => code(e) === 'conflict', 'first offer wins');
  assert.deepEqual(links.poll(id), { offer: B, answer: null });
  assert.throws(() => links.answer(id, '@ub:chama.test', B), (e) => code(e) === 'forbidden', 'another account');
  links.answer(id, '@ua:chama.test', { ...B, mac: 'b3RoZXI=' });
  assert.throws(() => links.answer(id, '@ua:chama.test', B), (e) => code(e) === 'conflict');
  assert.deepEqual(links.poll(id), { offer: B, answer: { ...B, mac: 'b3RoZXI=' } });
});
test('an entry lives 2 minutes, and 2 more after the offer; then it is gone', () => {
  const { db, links, tick } = setup();
  const a = links.create();
  tick(LINK_TTL);
  assert.throws(() => links.poll(a.id), (e) => code(e) === 'not_found');
  assert.throws(() => links.offer(a.id, '@ua:chama.test', B), (e) => code(e) === 'not_found');
  const b = links.create();
  assert.equal((db.prepare('SELECT COUNT(*) AS n FROM links').get() as { n: number }).n, 1, 'expired rows swept');
  tick(LINK_TTL - 1);
  links.offer(b.id, '@ua:chama.test', B);
  tick(LINK_TTL - 1);
  links.answer(b.id, '@ua:chama.test', B);
  tick(1);
  assert.throws(() => links.poll(b.id), (e) => code(e) === 'not_found');
  for (const id of [undefined, 5, 'nope']) assert.throws(() => links.poll(id), (e) => code(e) === 'not_found');
});
test('polls are capped per entry', () => {
  const { links } = setup();
  const { id } = links.create();
  for (let i = 0; i < 200; i++) links.poll(id);
  assert.throws(() => links.poll(id), (e) => code(e) === 'rate_limited');
});
test('a box is exactly three base64 strings, at most 4096 characters together', () => {
  assert.deepEqual(box(B), B);
  for (const bad of [null, [], 'x', { ...B, extra: 'eA==' }, { ciphertext: 'a', mac: 'b' }, { ...B, mac: 'not base64!' },
    { ...B, mac: 5 }, { ...B, ciphertext: 'A'.repeat(4090) }]) {
    assert.throws(() => box(bad), (e) => code(e) === 'bad_request', JSON.stringify(bad)?.slice(0, 40));
  }
});
