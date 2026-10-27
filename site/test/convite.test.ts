import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MAX_NOME, nomeConvite, svgConvite, textosConvite } from '../src/convite.ts';

test('keeps real first names, accents included, and capitalises them', () => {
  assert.equal(nomeConvite('João'), 'João');
  assert.equal(nomeConvite('  antônia  '), 'Antônia');
  assert.equal(nomeConvite('Zoë-Ann'), 'Zoë-Ann');
  assert.equal(nomeConvite("d'Ávila"), "D'Ávila");
  assert.equal(nomeConvite('Ana   Maria'), 'Ana Maria');
  assert.equal(nomeConvite('João'), 'João'); // decomposed accent is normalised
});

test('rejects anything that is not a short name', () => {
  for (const ruim of [null, '', 'a', '<script>', 'https://x.co', 'www.site.com', 'Ana1', '😀😀', 'Ana 😀', 'Иван', '李雷', 'x'.repeat(MAX_NOME + 1), 'Ana--Maria']) {
    assert.equal(nomeConvite(ruim), null, String(ruim));
  }
});

test('share texts name the person, or stay generic', () => {
  assert.equal(textosConvite('Ana').titulo, 'Ana te chamou para o Alô');
  assert.equal(textosConvite(null).titulo, 'Te chamaram para o Alô');
});

test('image template has the right size and escapes text', () => {
  assert.match(svgConvite('Ana', 'largo'), /width="1200" height="630"/);
  assert.match(svgConvite('Ana', 'quadrado'), /width="600" height="600"/);
  assert.ok(!svgConvite('A<b>&', 'largo').includes('<b>'));
});
