import type { IncomingMessage, ServerResponse } from 'node:http';
import { AppError } from './errors.ts';

export type Handler = (body: any, req: IncomingMessage) => Promise<unknown> | unknown;

// Returns the parsed JSON object; anything else (bad JSON, arrays, null, > 16 KiB) is bad_request.
export async function readJson(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = []; let size = 0;
  for await (const c of req) { size += c.length; if (size > 16_384) throw new AppError('bad_request'); chunks.push(c); }
  if (!size) return {};
  let v: unknown;
  try { v = JSON.parse(Buffer.concat(chunks).toString()); } catch { throw new AppError('bad_request'); }
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw new AppError('bad_request');
  return v as Record<string, unknown>;
}

export function send(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
}

// Caddy sets X-Forwarded-For; only trust it while chama-id is reachable through Caddy alone.
export function clientIp(req: IncomingMessage): string {
  const xff = req.headers['x-forwarded-for'];
  const first = (Array.isArray(xff) ? xff[0] : xff)?.split(',')[0]?.trim();
  return first || req.socket.remoteAddress || 'unknown';
}

export function router(routes: Record<string, Handler>) {
  return async (req: IncomingMessage, res: ServerResponse) => {
    try {
      const path = new URL(req.url ?? '/', 'http://x').pathname;
      const h = routes[`${req.method} ${path}`];
      if (!h) throw new AppError('not_found');
      send(res, 200, await h(req.method === 'POST' ? await readJson(req) : {}, req));
    } catch (e) {
      if (e instanceof AppError && e.status < 500) send(res, e.status, { error: e.code, ...e.extra });
      else { console.error(e); send(res, 500, { error: 'internal' }); }
    }
  };
}
