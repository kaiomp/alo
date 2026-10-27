// usealo.app: static pages from ./public, the two form endpoints and personal invite links.
import { nomeConvite, textosConvite } from './convite.ts';
import { imagemConvite } from './imagem.ts';
import { comIntervalo } from './intervalo.ts';
import { ErroValidacao, validarInscricao, validarPedido } from './validar.ts';

type Env = {
  ASSETS: { fetch(req: Request): Promise<Response> };
  DB: {
    prepare(sql: string): { bind(...v: unknown[]): { run(): Promise<unknown> } };
  };
  LIMITE: { limit(o: { key: string }): Promise<{ success: boolean }> };
  TURNSTILE_SECRET?: string;
};

type Ctx = { waitUntil(p: Promise<unknown>): void };

const MAX_CORPO = 10_000;

const SEGURANCA: Record<string, string> = {
  'Content-Security-Policy': [
    "default-src 'self'",
    "script-src 'self' https://challenges.cloudflare.com",
    'frame-src https://challenges.cloudflare.com',
    "img-src 'self' data:",
    "style-src 'self'",
    "base-uri 'none'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join('; '),
  'Strict-Transport-Security': 'max-age=31536000',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), interest-cohort=()',
};

function cache(caminho: string): string | null {
  if (caminho.startsWith('/fonts/') || caminho.startsWith('/img/')) return 'public, max-age=604800';
  // Short, so a new video file shows up within the hour.
  if (caminho.startsWith('/video/')) return 'public, max-age=3600';
  return null;
}

function json(corpo: unknown, status = 200): Response {
  return Response.json(corpo, { status, headers: { 'Cache-Control': 'no-store' } });
}

async function sha256(texto: string): Promise<string> {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function humano(token: unknown, ip: string, env: Env): Promise<boolean> {
  if (typeof token !== 'string' || !token || !env.TURNSTILE_SECRET) return false;
  const corpo = new FormData();
  corpo.append('secret', env.TURNSTILE_SECRET);
  corpo.append('response', token);
  if (ip) corpo.append('remoteip', ip);
  const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    body: corpo,
  });
  const dados = (await res.json()) as { success?: boolean };
  return dados.success === true;
}

async function formulario(req: Request, env: Env, rota: string): Promise<Response> {
  if (req.method !== 'POST') return json({ erro: 'metodo' }, 405);

  // The IP is only used, hashed, as the rate-limit key; it is never stored.
  const ip = req.headers.get('CF-Connecting-IP') ?? '';
  const { success } = await env.LIMITE.limit({ key: await sha256(ip) });
  if (!success) return json({ erro: 'muitas_tentativas' }, 429);

  if (Number(req.headers.get('Content-Length') ?? 0) > MAX_CORPO) return json({ erro: 'grande' }, 413);
  const bruto = await req.text();
  if (bruto.length > MAX_CORPO) return json({ erro: 'grande' }, 413);

  let dados: Record<string, unknown>;
  try {
    dados = JSON.parse(bruto);
    if (!dados || typeof dados !== 'object' || Array.isArray(dados)) throw new Error();
  } catch {
    return json({ erro: 'json' }, 400);
  }

  if (!(await humano(dados.token, ip, env))) return json({ erro: 'verificacao' }, 403);

  try {
    if (rota === '/api/inscricao') {
      const i = validarInscricao(dados);
      await env.DB.prepare(
        'INSERT INTO inscricoes (nome, email, whatsapp, ajuda, cidade, mensagem, politica) VALUES (?, ?, ?, ?, ?, ?, ?)',
      )
        .bind(i.nome, i.email, i.whatsapp, JSON.stringify(i.ajuda), i.cidade, i.mensagem, i.politica)
        .run();
    } else {
      const p = validarPedido(dados);
      await env.DB.prepare('INSERT INTO pedidos (contato, mensagem) VALUES (?, ?)').bind(p.contato, p.mensagem).run();
    }
  } catch (e) {
    if (e instanceof ErroValidacao) return json({ erro: 'campo', campo: e.message }, 422);
    throw e;
  }
  return json({ ok: true }, 201);
}

// /convite?de=Ana: the static page with its share tags rewritten for that name.
function paginaConvite(url: URL, res: Response): Response {
  const nome = nomeConvite(url.searchParams.get('de'));
  if (!nome || !res.ok) return res;
  const t = textosConvite(nome);
  const de = encodeURIComponent(nome);
  const base = `https://${url.host}`;
  const conteudo = (valor: string) => ({ element: (e: Element) => void e.setAttribute('content', valor) });
  return new HTMLRewriter()
    .on('title', { element: (e) => void e.setInnerContent(t.titulo) })
    .on('[data-titulo]', conteudo(t.titulo))
    .on('[data-descricao]', conteudo(t.descricao))
    .on('[data-url]', conteudo(`${base}/convite?de=${de}`))
    .on('[data-imagem]', conteudo(`${base}/og/convite.png?de=${de}`))
    .on('[data-imagem-quadrada]', conteudo(`${base}/og/convite-quadrado.png?de=${de}`))
    .on('[data-imagem-tipo]', conteudo('image/png'))
    .on('[data-imagem-alt]', conteudo(t.alt))
    .on('[data-nome]', { element: (e) => void e.setInnerContent(nome) })
    .transform(res);
}

async function responder(req: Request, env: Env, ctx: Ctx, url: URL): Promise<Response> {
  const p = url.pathname;
  if (p === '/api/inscricao' || p === '/api/pedido') return formulario(req, env, p);
  if (p === '/og/convite.png' || p === '/og/convite-quadrado.png') return imagemConvite(url, ctx);
  const res = await env.ASSETS.fetch(req);
  if (p === '/convite') return paginaConvite(url, res);
  if (p.startsWith('/video/')) return comIntervalo(req.headers.get('Range'), res);
  return res;
}

export default {
  async fetch(req: Request, env: Env, ctx: Ctx): Promise<Response> {
    const url = new URL(req.url);
    // CF-Visitor carries the visitor's real scheme; local dev rewrites req.url, so it is not trusted here.
    const http = req.headers.get('CF-Visitor')?.includes('"http"') ?? false;
    if (url.hostname.startsWith('www.') || http) {
      url.hostname = url.hostname.replace(/^www\./, '');
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 301);
    }

    // Short aliases for the sign-up form link.
    if (url.pathname === '/quero-ajudar' || url.pathname === '/form') {
      url.pathname = '/ajudar';
      return Response.redirect(url.toString(), 301);
    }

    const res = await responder(req, env, ctx, url);
    const saida = new Response(res.body, res);
    for (const [k, v] of Object.entries(SEGURANCA)) saida.headers.set(k, v);
    const cc = cache(url.pathname);
    if (cc && res.ok) saida.headers.set('Cache-Control', cc);
    return saida;
  },
};
