import { createHmac, timingSafeEqual } from 'node:crypto';
import { AppError } from './errors.ts';

const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
const sig = (data: string, secret: string) => createHmac('sha256', secret).update(data).digest('base64url');

export function signJwt(claims: Record<string, unknown>, secret: string, ttlSeconds: number, now = Math.floor(Date.now() / 1000)): string {
  const data = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ ...claims, iat: now, exp: now + ttlSeconds })}`;
  return `${data}.${sig(data, secret)}`;
}

export function verifyJwt(token: string, secret: string, now = Math.floor(Date.now() / 1000)): Record<string, unknown> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new AppError('invalid_token');
  const [h, p, s] = parts;
  const want = Buffer.from(sig(`${h}.${p}`, secret));
  const got = Buffer.from(s);
  if (want.length !== got.length || !timingSafeEqual(want, got)) throw new AppError('invalid_token');
  let claims: Record<string, unknown>;
  try { claims = JSON.parse(Buffer.from(p, 'base64url').toString()); } catch { throw new AppError('invalid_token'); }
  if (typeof claims?.exp !== 'number' || now > claims.exp) throw new AppError('invalid_token');
  return claims;
}
