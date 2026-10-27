import assert from 'node:assert/strict';
import { test } from 'node:test';
import { avisoInscricao, avisoPedido, mime } from '../src/aviso.ts';
import { validarInscricao } from '../src/validar.ts';

const data = new Date('2026-10-27T20:52:00Z');
const decodificar = (raw: string) => {
  const [cab, corpo] = raw.split('\r\n\r\n');
  return { cab, corpo: Buffer.from(corpo.replace(/\r\n/g, ''), 'base64').toString('utf8') };
};

test('sign-up notice lists every field, time in Brasília', () => {
  const i = validarInscricao({ nome: 'João Pé', whatsapp: '(81) 99999-1234', ajuda: ['Design', 'Jurídico'], consentimento: true });
  const a = avisoInscricao(i, data);
  assert.equal(a.assunto, 'Nova inscrição no Alô: João Pé');
  assert.match(a.texto, /WhatsApp: 81999991234 \(https:\/\/wa\.me\/81999991234\)/);
  assert.match(a.texto, /Como quer ajudar: Design, Jurídico/);
  assert.match(a.texto, /E-mail: —/);
  assert.match(a.texto, /27\/10\/2026.*17:52 \(horário de Brasília\)/);
});

test('raw message has safe headers and a base64 UTF-8 body', () => {
  const i = validarInscricao({ nome: 'Ana\r\nBcc: x@y.z', email: 'ana@exemplo.com', consentimento: true });
  const raw = mime({ ...avisoInscricao(i, data), data, id: 'abc' });
  const { cab, corpo } = decodificar(raw);
  assert.ok(!/^Bcc:/m.test(cab), 'no header injection from the name');
  assert.match(cab, /^Subject: =\?UTF-8\?B\?/m);
  assert.match(cab, /^Reply-To: ana@exemplo\.com$/m);
  assert.match(cab, /^Message-ID: <abc@usealo\.app>$/m);
  assert.ok(cab.split('\r\n').every((l) => l.length <= 78), 'header lines stay short');
  assert.match(corpo, /Nome: Ana/);
});

test('odd e-mail addresses never reach the Reply-To header', () => {
  const raw = mime({ assunto: 'x', texto: 'y', responderPara: 'a,"b"<c>@d.co', data, id: 'z' });
  assert.ok(!raw.includes('Reply-To'));
});

test('privacy notice explains a blank request', () => {
  assert.match(avisoPedido({ contato: 'ana@exemplo.com', mensagem: null }, data).texto, /apagar todos os dados/);
  assert.equal(avisoPedido({ contato: 'x', mensagem: 'ver' }, data).assunto, 'Pedido de privacidade');
});
