import assert from 'node:assert/strict';
import { test } from 'node:test';
import { LIMITES, POLITICA, validarInscricao, validarPedido } from '../src/validar.ts';

const base = { nome: 'Ana Souza', email: 'Ana@Exemplo.com', ajuda: ['Design'], consentimento: true };

function campo(d: Record<string, unknown>): string {
  try {
    validarInscricao(d);
  } catch (e) {
    return (e as Error).message;
  }
  return 'ok';
}

test('accepts a minimal valid sign-up and normalises it', () => {
  const i = validarInscricao({ ...base, whatsapp: '+55 (81) 99999-1234', cidade: '  Recife/PE ' });
  assert.equal(i.email, 'ana@exemplo.com');
  assert.equal(i.whatsapp, '5581999991234');
  assert.equal(i.cidade, 'Recife/PE');
  assert.equal(i.mensagem, null);
  assert.equal(i.politica, POLITICA);
});

test('name is required, 2 to 100 characters', () => {
  assert.equal(campo({ ...base, nome: '' }), 'nome');
  assert.equal(campo({ ...base, nome: ' a ' }), 'nome');
  assert.equal(campo({ ...base, nome: 'x'.repeat(LIMITES.nome + 1) }), 'nome');
  assert.equal(campo({ ...base, nome: 42 }), 'nome');
});

test('needs an e-mail or a WhatsApp number, and checks both', () => {
  assert.equal(campo({ ...base, email: '' }), 'contato');
  assert.equal(campo({ ...base, email: '', whatsapp: '81 99999-1234' }), 'ok');
  assert.equal(campo({ ...base, email: 'sem-arroba' }), 'email');
  assert.equal(campo({ ...base, email: `${'a'.repeat(200)}@x.com` }), 'email');
  assert.equal(campo({ ...base, whatsapp: '12345' }), 'whatsapp');
  assert.equal(campo({ ...base, whatsapp: '1'.repeat(16) }), 'whatsapp');
});

test('help areas must come from the fixed list', () => {
  assert.equal(campo({ ...base, ajuda: [] }), 'ok');
  assert.equal(campo({ ...base, ajuda: ['Hacker'] }), 'ajuda');
  assert.equal(campo({ ...base, ajuda: 'Design' }), 'ajuda');
  assert.equal(campo({ ...base, ajuda: Array(8).fill('Design') }), 'ajuda');
});

test('consent must be exactly true', () => {
  assert.equal(campo({ ...base, consentimento: 'true' }), 'consentimento');
  assert.equal(campo({ ...base, consentimento: undefined }), 'consentimento');
});

test('optional texts have size limits', () => {
  assert.equal(campo({ ...base, cidade: 'x'.repeat(LIMITES.cidade + 1) }), 'cidade');
  assert.equal(campo({ ...base, mensagem: 'x'.repeat(LIMITES.mensagem + 1) }), 'mensagem');
  assert.equal(campo({ ...base, mensagem: 'x'.repeat(LIMITES.mensagem) }), 'ok');
});

test('data request needs a contact of 5 to 200 characters and a short optional message', () => {
  assert.deepEqual(validarPedido({ contato: ' ana@exemplo.com ' }), { contato: 'ana@exemplo.com', mensagem: null });
  assert.throws(() => validarPedido({ contato: 'abc' }));
  assert.throws(() => validarPedido({ contato: 'x'.repeat(LIMITES.contato + 1) }));
  assert.throws(() => validarPedido({}));
  assert.throws(() => validarPedido({ contato: 'ana@exemplo.com', mensagem: 'x'.repeat(LIMITES.pedido + 1) }));
});
