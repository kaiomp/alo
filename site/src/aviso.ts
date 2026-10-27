// E-mail notices to the project owner about new sign-ups and privacy requests.
// Pure functions: the Worker sends the raw message with its send_email binding.
import type { Inscricao } from './validar.ts';

export const REMETENTE = 'inscricoes@usealo.app';
export const DESTINO = 'hi@kaio.mp';

const FALTA = '—';

function horaBrasilia(data: Date): string {
  const f = new Intl.DateTimeFormat('pt-BR', { timeZone: 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' });
  return `${f.format(data)} (horário de Brasília)`;
}

const umaLinha = (texto: string) => texto.replace(/\s+/g, ' ').trim();

export function avisoInscricao(i: Inscricao, data: Date) {
  const zap = i.whatsapp ? `${i.whatsapp} (https://wa.me/${i.whatsapp})` : FALTA;
  const texto = [
    'Nova inscrição no formulário "Quero ajudar" do Alô.',
    '',
    `Nome: ${i.nome}`,
    `E-mail: ${i.email ?? FALTA}`,
    `WhatsApp: ${zap}`,
    `Como quer ajudar: ${i.ajuda.length ? i.ajuda.join(', ') : FALTA}`,
    `Cidade e estado: ${i.cidade ?? FALTA}`,
    'Mensagem:',
    i.mensagem ?? FALTA,
    '',
    `Recebida em ${horaBrasilia(data)}.`,
  ].join('\n');
  return { assunto: `Nova inscrição no Alô: ${umaLinha(i.nome)}`, texto, responderPara: i.email };
}

export function avisoPedido(p: { contato: string; mensagem: string | null }, data: Date) {
  const texto = [
    'Novo pedido na página de Privacidade do Alô.',
    '',
    `Contato informado: ${p.contato}`,
    'Pedido:',
    p.mensagem ?? 'Mensagem em branco: apagar todos os dados dessa pessoa.',
    '',
    `Recebido em ${horaBrasilia(data)}.`,
    'A página promete resposta em até 15 dias.',
  ].join('\n');
  return { assunto: 'Pedido de privacidade', texto, responderPara: null };
}

function base64(texto: string): string {
  const bytes = new TextEncoder().encode(texto);
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

// RFC 2047 encoded words of at most 45 UTF-8 bytes each (75 characters once encoded).
function cabecalhoUtf8(texto: string): string {
  const partes: string[] = [];
  let atual = '';
  for (const ch of texto) {
    if (new TextEncoder().encode(atual + ch).length > 45) {
      partes.push(atual);
      atual = '';
    }
    atual += ch;
  }
  if (atual) partes.push(atual);
  return partes.map((p) => `=?UTF-8?B?${base64(p)}?=`).join('\r\n ');
}

// Only plain addresses go into a header as-is; anything else is left out.
const SIMPLES = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;

export function mime(o: { assunto: string; texto: string; responderPara: string | null; data: Date; id: string }): string {
  const corpo = base64(o.texto).replace(/.{76}/g, '$&\r\n');
  return [
    `From: ${cabecalhoUtf8('Alô')} <${REMETENTE}>`,
    `To: ${DESTINO}`,
    ...(o.responderPara && SIMPLES.test(o.responderPara) ? [`Reply-To: ${o.responderPara}`] : []),
    `Subject: ${cabecalhoUtf8(o.assunto)}`,
    `Date: ${o.data.toUTCString().replace('GMT', '+0000')}`,
    `Message-ID: <${o.id}@usealo.app>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    corpo,
  ].join('\r\n');
}
