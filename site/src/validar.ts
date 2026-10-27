// Server-side checks for the two public forms. Pure functions, so they run under node:test.

export const AJUDAS = [
  'Desenvolvimento',
  'Design',
  'Comunicação',
  'Jurídico',
  'Políticas públicas',
  'Testar o app',
  'Outro',
];

// Bump when the text of privacidade.html changes; each row records the version accepted.
export const POLITICA = '2026-10-27';

export const LIMITES = { nome: 100, email: 200, cidade: 100, mensagem: 2000, contato: 200, pedido: 500 };

export class ErroValidacao extends Error {}

export type Inscricao = {
  nome: string;
  email: string | null;
  whatsapp: string | null;
  ajuda: string[];
  cidade: string | null;
  mensagem: string | null;
  politica: string;
};

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function texto(valor: unknown, campo: string, max: number, obrigatorio = false): string | null {
  if (valor === undefined || valor === null || valor === '') {
    if (obrigatorio) throw new ErroValidacao(campo);
    return null;
  }
  if (typeof valor !== 'string') throw new ErroValidacao(campo);
  // Drop control characters except line breaks and tabs.
  const limpo = valor.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '').trim();
  if (limpo.length > max) throw new ErroValidacao(campo);
  if (!limpo) {
    if (obrigatorio) throw new ErroValidacao(campo);
    return null;
  }
  return limpo;
}

function whatsapp(valor: unknown): string | null {
  const bruto = texto(valor, 'whatsapp', 40);
  if (!bruto) return null;
  const digitos = bruto.replace(/\D/g, '');
  // 10-11 digits with area code, up to 13 with the 55 country code; 15 is the E.164 maximum.
  if (digitos.length < 10 || digitos.length > 15) throw new ErroValidacao('whatsapp');
  return digitos;
}

export function validarInscricao(d: Record<string, unknown>): Inscricao {
  const nome = texto(d.nome, 'nome', LIMITES.nome, true) as string;
  if (nome.length < 2) throw new ErroValidacao('nome');

  const email = texto(d.email, 'email', LIMITES.email);
  if (email && !EMAIL.test(email)) throw new ErroValidacao('email');
  const zap = whatsapp(d.whatsapp);
  if (!email && !zap) throw new ErroValidacao('contato');

  const ajuda = d.ajuda ?? [];
  if (!Array.isArray(ajuda) || ajuda.length > AJUDAS.length) throw new ErroValidacao('ajuda');
  if (!ajuda.every((a) => AJUDAS.includes(a))) throw new ErroValidacao('ajuda');

  if (d.consentimento !== true) throw new ErroValidacao('consentimento');

  return {
    nome,
    email: email ? email.toLowerCase() : null,
    whatsapp: zap,
    ajuda: [...new Set(ajuda as string[])],
    cidade: texto(d.cidade, 'cidade', LIMITES.cidade),
    mensagem: texto(d.mensagem, 'mensagem', LIMITES.mensagem),
    politica: POLITICA,
  };
}

export function validarPedido(d: Record<string, unknown>): { contato: string; mensagem: string | null } {
  const contato = texto(d.contato, 'contato', LIMITES.contato, true) as string;
  if (contato.length < 5) throw new ErroValidacao('contato');
  return { contato, mensagem: texto(d.mensagem, 'mensagem', LIMITES.pedido) };
}
