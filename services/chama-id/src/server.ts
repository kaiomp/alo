import http, { type IncomingMessage } from 'node:http';
import { openDb } from './db.ts';
import { OtpService } from './otp.ts';
import { Directory } from './directory.ts';
import { Accounts } from './accounts.ts';
import { HttpSynapseAdmin, type SynapseAdmin, type CrossSigningKeys } from './synapse.ts';
import { ConsoleSms } from './sms.ts';
import { signJwt } from './jwt.ts';
import { normalizePhone } from './phone.ts';
import { AppError } from './errors.ts';
import { router, clientIp, rateKey, windowLimiter, ttlCache } from './http.ts';

// Shape check of the client's new public cross-signing keys, done before the SMS code is spent.
// Synapse checks the signatures. Only the three key fields are passed on.
const USAGES = { master_key: 'master', self_signing_key: 'self_signing', user_signing_key: 'user_signing' } as const;
function crossSigningKeys(v: unknown, userId: string): CrossSigningKeys {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw new AppError('bad_request');
  const out = {} as CrossSigningKeys;
  for (const [field, usage] of Object.entries(USAGES) as [keyof CrossSigningKeys, string][]) {
    const k = (v as Record<string, any>)[field];
    if (typeof k !== 'object' || k === null || k.user_id !== userId || !Array.isArray(k.usage) || !k.usage.includes(usage)
      || typeof k.keys !== 'object' || k.keys === null || !Object.keys(k.keys).length) throw new AppError('bad_request');
    out[field] = k;
  }
  return out;
}

const bearer = (req: IncomingMessage) => {
  const m = req.headers.authorization?.match(/^Bearer +(\S+)$/i);
  if (!m) throw new AppError('invalid_token');
  return m[1];
};

export function createServer(d: {
  otp: OtpService; directory: Directory; accounts: Accounts; admin: SynapseAdmin;
  jwtSecret: string; publicBaseUrl: string; dev?: boolean; now?: () => number;
}) {
  const now = d.now ?? (() => Math.floor(Date.now() / 1000));
  const str = (v: unknown) => { if (typeof v !== 'string') throw new AppError('bad_request'); return v; };

  // Unsalted phone hashes are enumerable, so lookups are capped per client IP (or IPv6 /64) and per user.
  // Dev mode raises both 100x so test suites can rerun against one stack.
  const limit = 30 * (d.dev ? 100 : 1);
  const ipLookups = windowLimiter({ limit, window: 3600, maxKeys: 100_000, now });
  const userLookups = windowLimiter({ limit, window: 3600, maxKeys: 100_000, now });
  // Each reset call costs a Synapse whoami, so it is capped per IP before that call.
  const resets = windowLimiter({ limit: 10 * (d.dev ? 100 : 1), window: 3600, maxKeys: 100_000, now });
  const whoamiCache = ttlCache<string>({ ttl: 60, maxKeys: 10_000, now });
  const cachedWhoami = async (token: string) => {
    const hit = whoamiCache.get(token);
    if (hit) return hit;
    const { userId } = await d.admin.whoami(token);
    whoamiCache.set(token, userId);
    return userId;
  };

  return http.createServer(router({
    'GET /id/v1/health': () => ({ ok: true }),
    'POST /id/v1/otp/request': async (b, req) => {
      const phone = normalizePhone(str(b.phone));
      const { retryAfter } = await d.otp.request(phone, rateKey(clientIp(req)));
      return { phone, retry_after: retryAfter };
    },
    'POST /id/v1/otp/verify': async (b) => {
      const phone = normalizePhone(str(b.phone));
      d.otp.verify(phone, str(b.code));
      const account = await d.accounts.resolve(phone);
      d.directory.markRegistered(phone, account.localpart);
      // `homeserver` is the public URL, for production clients. Dev clients use their own configured
      // base URL instead (the Android emulator reaches the host stack at http://10.0.2.2:8080).
      return {
        phone, user_id: account.userId, homeserver: d.publicBaseUrl, new_account: account.created,
        login_token: signJwt({ sub: account.localpart, iss: 'chama-id', aud: 'chama' }, d.jwtSecret, 120),
      };
    },
    'POST /id/v1/directory/lookup': async (b, req) => {
      const token = bearer(req);
      ipLookups.hit(rateKey(clientIp(req)));
      userLookups.hit(await cachedWhoami(token));
      return { registered: d.directory.lookup(b.hashes) };
    },
    // For a new phone without the recovery key (spec §5). The phone made the new keys and sends
    // only the public, signed bundle. Ownership, the bundle shape and the old master key are
    // checked before the code is spent, so those errors do not burn the user's code.
    // A reset logs out every other device, so a SIM-swap attacker cannot stay next to the owner.
    'POST /id/v1/account/reset-identity': async (b, req) => {
      const token = bearer(req);
      resets.hit(rateKey(clientIp(req)));
      const phone = normalizePhone(str(b.phone));
      const code = str(b.code);
      const { userId, deviceId } = await d.admin.whoami(token); // uncached: a logged-out token must fail here
      if (d.accounts.current(phone)?.userId !== userId || !deviceId) throw new AppError('forbidden');
      const keys = crossSigningKeys(b.keys, userId);
      // No master key yet: the client uploads its first keys itself, which needs no UIA.
      if (!await d.admin.hasMasterKey(token, userId)) throw new AppError('no_identity');
      d.otp.verify(phone, code);
      // Logout first: a reset must never leave another device signed in.
      const loggedOut = await d.admin.logoutOtherDevices(userId, deviceId);
      await d.admin.uploadCrossSigningKeys(userId, keys);
      return { logged_out_devices: loggedOut };
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
  const secrets = {
    pepper: env('OTP_PEPPER'), jwtSecret: env('JWT_SECRET'), serverName: env('SERVER_NAME'), publicBaseUrl: env('PUBLIC_BASEURL'),
    synapseUrl: env('SYNAPSE_INTERNAL_URL'), sharedSecret: env('REGISTRATION_SHARED_SECRET'), asToken: env('SYNAPSE_AS_TOKEN'),
  };
  // Dev mode accepts code 000000 for any phone, so it must never run on a real domain.
  if (dev && !/\.(test|localhost)$/.test(secrets.serverName)) {
    console.error('CHAMA_DEV=1 is only allowed for .test or .localhost server names'); process.exit(1);
  }
  // No real SMS provider exists yet; ConsoleSms prints codes, so it is dev only.
  if (!dev) { console.error('no SMS provider configured (set CHAMA_DEV=1 for development)'); process.exit(1); }
  const db = openDb(env('DB_PATH', '/data/chama-id.sqlite'));
  const admin = new HttpSynapseAdmin({ baseUrl: secrets.synapseUrl, sharedSecret: secrets.sharedSecret, asToken: secrets.asToken, db });
  const server = createServer({
    otp: new OtpService(db, { pepper: secrets.pepper, dev, sms: new ConsoleSms() }),
    directory: new Directory(db, secrets.serverName), accounts: new Accounts(db, admin, { serverName: secrets.serverName }), admin,
    jwtSecret: secrets.jwtSecret, publicBaseUrl: secrets.publicBaseUrl, dev,
  });
  server.listen(port, () => console.log(`chama-id listening on :${port}${dev ? ' (dev mode: code 000000 accepted)' : ''}`));
}
