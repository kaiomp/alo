import type { IncomingMessage, ServerResponse } from 'node:http';
import { isIPv6 } from 'node:net';
import { AppError } from './errors.ts';

export type Handler = (body: any, req: IncomingMessage) => Promise<unknown> | unknown;

// Returns the parsed JSON object; anything else (bad JSON, arrays, null, > maxBytes) is bad_request.
export async function readJson(req: IncomingMessage, maxBytes = 16_384): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = []; let size = 0;
  for await (const c of req) { size += c.length; if (size > maxBytes) throw new AppError('bad_request'); chunks.push(c); }
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

// Rate-limit key for an IP: IPv6 counts per /64 (one customer's block), IPv4-mapped IPv6 counts as IPv4.
export function rateKey(ip: string): string {
  const a = ip.split('%')[0];
  if (!isIPv6(a)) return ip;
  const groups = (s?: string) => !s ? [] : s.split(':').flatMap((g) => {
    if (!g.includes('.')) return [parseInt(g, 16)];
    const [w, x, y, z] = g.split('.').map(Number);
    return [w * 256 + x, y * 256 + z];
  });
  const [head, tail] = a.split('::');
  const h = groups(head), t = groups(tail);
  const g = tail === undefined ? h : [...h, ...Array(8 - h.length - t.length).fill(0), ...t];
  if (g.slice(0, 5).every((x) => x === 0) && g[5] === 0xffff) return [g[6] >> 8, g[6] & 255, g[7] >> 8, g[7] & 255].join('.');
  return `${g.slice(0, 4).map((x) => x.toString(16)).join(':')}::/64`;
}

// Sliding window: at most `limit` hits per key per `window` seconds, at most `maxKeys` keys in memory.
// Stale keys are swept at most once per window; a new key while full is rate_limited, so memory stays bounded.
// Limit: in-memory, single replica only; move to Redis in M7
export function windowLimiter(o: { limit: number; window: number; maxKeys: number; now: () => number }) {
  const hits = new Map<string, number[]>();
  let lastSweep = -Infinity;
  return {
    size: () => hits.size,
    hit(key: string) {
      const t = o.now();
      if (t - lastSweep >= o.window) {
        for (const [k, v] of hits) if (v.at(-1)! <= t - o.window) hits.delete(k);
        lastSweep = t;
      }
      const prev = hits.get(key);
      if (!prev && hits.size >= o.maxKeys) throw new AppError('rate_limited', { retry_after: lastSweep + o.window - t });
      const recent = (prev ?? []).filter((at) => at > t - o.window);
      if (recent.length >= o.limit) throw new AppError('rate_limited', { retry_after: recent[0] + o.window - t });
      recent.push(t);
      hits.set(key, recent);
    },
    // Takes back the newest hit of `key`, for a call that turned out not to count.
    undo(key: string) {
      const v = hits.get(key);
      v?.pop();
      if (v && !v.length) hits.delete(key);
    },
  };
}

// Entries live `ttl` seconds; at most `maxKeys` entries, the oldest is dropped when full.
export function ttlCache<V>(o: { ttl: number; maxKeys: number; now: () => number }) {
  const m = new Map<string, { v: V; exp: number }>();
  return {
    size: () => m.size,
    get(k: string): V | undefined {
      const e = m.get(k);
      if (e && e.exp > o.now()) return e.v;
      m.delete(k);
    },
    set(k: string, v: V) {
      m.delete(k);
      if (m.size >= o.maxKeys) m.delete(m.keys().next().value!);
      m.set(k, { v, exp: o.now() + o.ttl });
    },
  };
}

// `bodyCaps` overrides the 16 KiB body cap per route key.
export function router(routes: Record<string, Handler>, bodyCaps: Record<string, number> = {}) {
  return async (req: IncomingMessage, res: ServerResponse) => {
    try {
      let path: string;
      try { path = new URL(req.url ?? '/', 'http://x').pathname; } catch { throw new AppError('bad_request'); }
      const key = `${req.method} ${path}`;
      const h = routes[key];
      if (!h) throw new AppError('not_found');
      send(res, 200, await h(req.method === 'POST' ? await readJson(req, bodyCaps[key]) : {}, req));
    } catch (e) {
      if (e instanceof AppError && e.status < 500) send(res, e.status, { error: e.code, ...e.extra });
      else { console.error(e); send(res, 500, { error: 'internal' }); }
    }
  };
}
