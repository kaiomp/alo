// Personal invite links (/convite?de=Ana): name cleaning and the share-image template.
// Pure functions; the Worker rasterises the SVG with resvg (see imagem.ts).

const LETRA = "A-Za-zÀ-ÖØ-öø-ÿ";
// Letters the bundled Inter subset can draw, single spaces, apostrophes and hyphens between them.
const NOME = new RegExp(`^[${LETRA}]+(?:[ '-][${LETRA}]+)*$`);
export const MAX_NOME = 24;

export function nomeConvite(bruto: string | null): string | null {
  if (!bruto) return null;
  const nome = bruto.normalize('NFC').trim().replace(/\s+/g, ' ');
  if (nome.length < 2 || nome.length > MAX_NOME || !NOME.test(nome)) return null;
  return nome[0].toLocaleUpperCase('pt-BR') + nome.slice(1);
}

export function textosConvite(nome: string | null) {
  return nome
    ? {
        titulo: `${nome} te chamou para o Alô`,
        descricao: `${nome} quer você no Alô: conversas, fotos e participação num app só. Livre, aberto, sem dono. Feito no Brasil.`,
        alt: `${nome} te chamou para o Alô. Livre, aberto, sem dono. Feito no Brasil.`,
      }
    : {
        titulo: 'Te chamaram para o Alô',
        descricao: 'Conversas, fotos e participação num app só. Livre, aberto, sem dono. Feito no Brasil.',
        alt: 'Alô: livre, aberto, sem dono. Feito no Brasil.',
      };
}

function xml(texto: string): string {
  return texto.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

const LOGO = 'M22 86L30 68C14 56 13 38 24 29Q37 13 50 28Q63 13 76 29C87 38 86 57 72 66Q52 77 30 68';
const traco = (cor: string, largura: number, extra = '') =>
  `fill="none" stroke="${cor}" stroke-width="${largura}" stroke-linecap="round" stroke-linejoin="round" ${extra}`;

// Inter Bold averages about 0.6 em per character; shrink long names to fit the width.
function tamanho(texto: string, largura: number, maximo: number): number {
  return Math.floor(Math.min(maximo, largura / (0.6 * texto.length)));
}

export function svgConvite(nome: string, formato: 'largo' | 'quadrado'): string {
  const n = xml(nome);
  const largo = formato === 'largo';
  const [w, h] = largo ? [1200, 630] : [600, 600];
  const m = largo ? 72 : 48;
  const fonteNome = largo ? tamanho(nome, 1000, 128) : tamanho(nome, 504, 96);
  const yNome = largo ? 316 : 290;
  const linha2 = largo ? 64 : 40;
  const fundo = `<defs><radialGradient id="g" cx="0.9" cy="0" r="1"><stop offset="0" stop-color="#7B3AAD"/><stop offset="0.7" stop-color="#4A1D6E"/></radialGradient></defs>
  <rect width="${w}" height="${h}" fill="url(#g)"/>
  <path d="${LOGO}" transform="translate(${largo ? 690 : 250} ${largo ? 30 : 250}) scale(${largo ? 6.4 : 4.6})" ${traco('#F5B700', 6, 'stroke-opacity="0.13"')}/>`;
  const marca = `<path d="${LOGO}" transform="translate(${m - 8} ${m - 14}) scale(0.62)" ${traco('#F5B700', 8)}/>
  <text x="${m + 62}" y="${m + 34}" font-family="Inter" font-weight="700" font-size="40" fill="#FFFFFF" letter-spacing="-1">Alô</text>`;
  const pilula = largo
    ? `<rect x="${m}" y="${h - 112}" width="232" height="60" rx="30" fill="#F5B700"/>
  <text x="${m + 116}" y="${h - 72}" text-anchor="middle" font-family="Inter" font-weight="700" font-size="27" fill="#2B0F42">usealo.app</text>`
    : `<text x="${m}" y="${h - 52}" font-family="Inter" font-weight="700" font-size="26" fill="#F5B700">usealo.app</text>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
  ${fundo}
  ${marca}
  <text x="${m}" y="${yNome}" font-family="Inter" font-weight="700" font-size="${fonteNome}" fill="#FFFFFF" letter-spacing="${-fonteNome * 0.03}">${n}</text>
  <text x="${m}" y="${yNome + linha2 * 1.35}" font-family="Inter" font-weight="700" font-size="${linha2}" fill="#FFFFFF" letter-spacing="${-linha2 * 0.02}">te chamou para o <tspan fill="#F5B700">Alô</tspan>.</text>
  ${largo ? `<text x="${m}" y="${yNome + linha2 * 1.35 + 76}" font-family="Inter" font-weight="400" font-size="30" fill="#FFE9A8">Livre, aberto, sem dono. Feito no Brasil.</text>` : ''}
  ${pilula}
</svg>`;
}
