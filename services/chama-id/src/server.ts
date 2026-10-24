import http from 'node:http';
import { openDb } from './db.ts';
import { OtpService } from './otp.ts';
import { Directory } from './directory.ts';
import { ConsoleSms } from './sms.ts';
import { signJwt } from './jwt.ts';
import { normalizePhone } from './phone.ts';
import { AppError } from './errors.ts';
import { router, clientIp, rateKey, windowLimiter } from './http.ts';

export function createServer(d: {
  otp: OtpService; directory: Directory; jwtSecret: string; serverName: string; publicBaseUrl: string; now?: () => number;
}) {
  const now = d.now ?? (() => Math.floor(Date.now() / 1000));
  const str = (v: unknown) => { if (typeof v !== 'string') throw new AppError('bad_request'); return v; };

  // Unsalted phone hashes are enumerable, so lookups are capped per client IP (or IPv6 /64).
  const lookups = windowLimiter({ limit: 30, window: 3600, maxKeys: 100_000, now });

  return http.createServer(router({
    'GET /id/v1/health': () => ({ ok: true }),
    'POST /id/v1/otp/request': async (b, req) => {
      const phone = normalizePhone(str(b.phone));
      const { retryAfter } = await d.otp.request(phone, rateKey(clientIp(req)));
      return { phone, retry_after: retryAfter };
    },
    'POST /id/v1/otp/verify': (b) => {
      const phone = normalizePhone(str(b.phone));
      d.otp.verify(phone, str(b.code));
      d.directory.markRegistered(phone);
      return {
        phone, user_id: `@${phone}:${d.serverName}`, homeserver: d.publicBaseUrl,
        login_token: signJwt({ sub: phone, iss: 'chama-id', aud: 'chama' }, d.jwtSecret, 120),
      };
    },
    'POST /id/v1/directory/lookup': (b, req) => {
      lookups.hit(rateKey(clientIp(req)));
      return { registered: d.directory.lookup(b.hashes) };
    },
  }, { 'POST /id/v1/directory/lookup': 96 * 1024 })); // room for 1000 hashes (about 67 KB)
}

if (import.meta.main) {
  const env = (k: string, def?: string) => {
    const v = process.env[k] ?? def;
    if (v === undefined || v === '') { console.error(`missing env ${k}`); process.exit(1); }
    return v;
  };
  const dev = process.env.CHAMA_DEV === '1';
  const port = Number(env('PORT', '8090'));
  if (!Number.isInteger(port) || port < 0 || port > 65535) { console.error(`invalid PORT ${process.env.PORT}`); process.exit(1); }
  const secrets = { pepper: env('OTP_PEPPER'), jwtSecret: env('JWT_SECRET'), serverName: env('SERVER_NAME'), publicBaseUrl: env('PUBLIC_BASEURL') };
  // No real SMS provider exists yet; ConsoleSms prints codes, so it is dev only.
  if (!dev) { console.error('no SMS provider configured (set CHAMA_DEV=1 for development)'); process.exit(1); }
  const db = openDb(env('DB_PATH', '/data/chama-id.sqlite'));
  const server = createServer({
    otp: new OtpService(db, { pepper: secrets.pepper, dev, sms: new ConsoleSms() }),
    directory: new Directory(db), jwtSecret: secrets.jwtSecret,
    serverName: secrets.serverName, publicBaseUrl: secrets.publicBaseUrl,
  });
  server.listen(port, () => console.log(`chama-id listening on :${port}${dev ? ' (dev mode: code 000000 accepted)' : ''}`));
}
