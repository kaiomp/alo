// Rasterises invite share images (SVG -> PNG) with resvg, cached at the edge per name.
import { initWasm, Resvg } from '@resvg/resvg-wasm';
import wasm from '@resvg/resvg-wasm/index_bg.wasm';
import inter400 from './fontes/inter-400.ttf';
import inter700 from './fontes/inter-700.ttf';
import { nomeConvite, svgConvite } from './convite.ts';

let pronto: Promise<void> | undefined;
const fontes = [new Uint8Array(inter400), new Uint8Array(inter700)];

async function png(svg: string): Promise<Uint8Array> {
  pronto ??= initWasm(wasm).catch((e) => {
    pronto = undefined;
    throw e;
  });
  await pronto;
  const opcoes = { font: { fontBuffers: fontes, defaultFontFamily: 'Inter', loadSystemFonts: false } };
  return new Resvg(svg, opcoes).render().asPng();
}

type Ctx = { waitUntil(p: Promise<unknown>): void };

export async function imagemConvite(url: URL, ctx: Ctx): Promise<Response> {
  const quadrado = url.pathname.endsWith('-quadrado.png');
  const nome = nomeConvite(url.searchParams.get('de'));
  // Anything odd gets the generic home image instead of a personal one.
  if (!nome) return Response.redirect(`${url.origin}/img/og-inicio${quadrado ? '-quadrado' : ''}.jpg`, 302);

  const chave = new Request(`${url.origin}${url.pathname}?de=${encodeURIComponent(nome)}`);
  const cache = (caches as unknown as { default: Cache }).default;
  const salvo = await cache.match(chave);
  if (salvo) return salvo;

  const corpo = await png(svgConvite(nome, quadrado ? 'quadrado' : 'largo'));
  const res = new Response(corpo, {
    headers: { 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=604800, immutable' },
  });
  ctx.waitUntil(cache.put(chave, res.clone()));
  return res;
}
