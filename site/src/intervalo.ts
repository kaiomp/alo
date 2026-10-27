// Byte-range answers for the video. The assets binding ignores Range, and Safari
// (iPhone included) refuses to play a video without 206 Partial Content replies.
// Limit: reads the whole file into memory on each range request (about 6 MB today).
// Fine for one short video; move videos to R2, which serves ranges natively, if they grow.

const FORMATO = /^bytes=(\d*)-(\d*)$/;

export async function comIntervalo(range: string | null, res: Response): Promise<Response> {
  const m = range ? FORMATO.exec(range.trim()) : null;
  if (!m || res.status !== 200) {
    const saida = new Response(res.body, res);
    if (res.status === 200) saida.headers.set('Accept-Ranges', 'bytes');
    return saida;
  }

  const corpo = await res.arrayBuffer();
  const total = corpo.byteLength;
  let inicio: number;
  let fim: number;
  if (m[1] === '') {
    // "bytes=-500" means the last 500 bytes.
    inicio = m[2] === '' ? total : Math.max(0, total - Number(m[2]));
    fim = total - 1;
  } else {
    inicio = Number(m[1]);
    fim = m[2] === '' ? total - 1 : Math.min(Number(m[2]), total - 1);
  }
  if (inicio > fim || inicio >= total) {
    return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${total}` } });
  }

  const cabecalhos = new Headers(res.headers);
  cabecalhos.set('Accept-Ranges', 'bytes');
  cabecalhos.set('Content-Range', `bytes ${inicio}-${fim}/${total}`);
  cabecalhos.set('Content-Length', String(fim - inicio + 1));
  return new Response(corpo.slice(inicio, fim + 1), { status: 206, headers: cabecalhos });
}
