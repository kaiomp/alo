import http, { type IncomingMessage } from 'node:http';
import { openDb } from './db.ts';
import { OtpService } from './otp.ts';
import { Directory, DAILY_HASHES } from './directory.ts';
import { Accounts } from './accounts.ts';
import { Pins } from './pin.ts';
import { Links, box } from './link.ts';
import { HttpSynapseAdmin, type SynapseAdmin, type CrossSigningKeys } from './synapse.ts';
import { ConsoleSms } from './sms.ts';
import { signJwt, verifyJwt } from './jwt.ts';
import { normalizePhone } from './phone.ts';
import { AppError } from './errors.ts';
import { router, clientIp, rateKey, windowLimiter, ttlCache } from './http.ts';

// Shape check of the client's new public cross-signing keys, done before the SMS code is spent.
// Only the Matrix fields of a public key are allowed, so alo-id never accepts private keys.
// Synapse checks the signatures.
const USAGES = { master_key: 'master', self_signing_key: 'self_signing', user_signing_key: 'user_signing' } as const;
const KEY_FIELDS = new Set(['user_id', 'usage', 'keys', 'signatures']);
const isObj = (v: unknown): v is Record<string, any> => typeof v === 'object' && v !== null && !Array.isArray(v);
function crossSigningKeys(v: unknown, userId: string): CrossSigningKeys {
  const bad = () => new AppError('bad_request');
  if (!isObj(v) || Object.keys(v).sort().join() !== Object.keys(USAGES).sort().join()) throw bad();
  for (const [field, usage] of Object.entries(USAGES)) {
    const k = v[field];
    if (!isObj(k) || Object.keys(k).some((f) => !KEY_FIELDS.has(f)) || k.user_id !== userId) throw bad();
    if (!Array.isArray(k.usage) || k.usage.length !== 1 || k.usage[0] !== usage) throw bad();
    if (!isObj(k.keys) || !Object.keys(k.keys).length || Object.values(k.keys).some((x) => typeof x !== 'string')) throw bad();
    if (k.signatures !== undefined && !isObj(k.signatures)) throw bad();
  }
  return v as CrossSigningKeys;
}

// @localpart:server → localpart
const localpartOf = (userId: string) => userId.slice(1, userId.indexOf(':'));

const bearer = (req: IncomingMessage) => {
  const m = req.headers.authorization?.match(/^Bearer +(\S+)$/i);
  if (!m) throw new AppError('invalid_token');
  return m[1];
};

// Audience of the token that carries a sign-in from the SMS code to the PIN step. Synapse accepts
// only the audience `alo`, so this token can never log in to Matrix.
const PIN_AUD = 'alo-pin';

export function createServer(d: {
  otp: OtpService; directory: Directory; accounts: Accounts; admin: SynapseAdmin; pins: Pins; links: Links;
  jwtSecret: string; publicBaseUrl: string; dev?: boolean; now?: () => number;
}) {
  const now = d.now ?? (() => Math.floor(Date.now() / 1000));
  const str = (v: unknown) => { if (typeof v !== 'string') throw new AppError('bad_request'); return v; };

  // Unsalted phone hashes are enumerable (issue #7), so each account gets 30 lookups per hour and
  // DAILY_HASHES hashes per day. There is no per-IP cap: Brazilian mobile carriers put many phones
  // behind one IP (CGNAT), and every lookup already needs an SMS-verified account.
  // Dev mode raises both 100x so test suites can rerun against one stack.
  const scale = d.dev ? 100 : 1;
  const userLookups = windowLimiter({ limit: 30 * scale, window: 3600, maxKeys: 100_000, now });
  // Each web page that shows a QR code opens a link; the app stops after 5 codes.
  // Limit: per IP, so a large office behind one address may wait; per-browser keys need state there.
  const linkStarts = windowLimiter({ limit: 60 * scale, window: 3600, maxKeys: 100_000, now });
  // Each reset call costs a Synapse whoami, so it is capped per IP before that call.
  const resets = windowLimiter({ limit: 10 * (d.dev ? 100 : 1), window: 3600, maxKeys: 100_000, now });
  // Each uncached token costs a Synapse whoami, and failures are not cached, so an IP may send
  // 100 bad tokens per hour; past that, its uncached tokens are refused before whoami. A token is
  // counted while its whoami runs (so a burst of parallel calls cannot slip past) and taken back
  // when it turns out valid, so many valid users behind one carrier IP (CGNAT) are never blocked.
  const badTokens = windowLimiter({ limit: 100 * scale, window: 3600, maxKeys: 100_000, now });
  const whoamiCache = ttlCache<{ userId: string; deviceId?: string }>({ ttl: 60, maxKeys: 10_000, now });
  // `fresh` skips the cache, so a token logged out a moment ago fails at once.
  const whoami = async (req: IncomingMessage, o: { fresh?: boolean } = {}) => {
    const token = bearer(req);
    const hit = o.fresh ? undefined : whoamiCache.get(token);
    if (hit) return hit;
    const ip = rateKey(clientIp(req));
    badTokens.hit(ip);
    let me: { userId: string; deviceId?: string };
    try {
      me = await d.admin.whoami(token);
    } catch (e) {
      if (!(e instanceof AppError && e.code === 'invalid_token')) badTokens.undo(ip); // Synapse down: not the client's fault
      throw e;
    }
    badTokens.undo(ip);
    whoamiCache.set(token, me);
    return me;
  };
  // Changes to the account come from a fresh token of a real device (an admin "log in as" token has
  // none), at most 20 per account per hour. Counted per account, not per IP (CGNAT).
  const accountActions = windowLimiter({ limit: 20 * scale, window: 3600, maxKeys: 100_000, now });
  const owner = async (req: IncomingMessage) => {
    const me = await whoami(req, { fresh: true });
    if (!me.deviceId) throw new AppError('forbidden');
    accountActions.hit(me.userId);
    return { userId: me.userId, deviceId: me.deviceId, localpart: localpartOf(me.userId) };
  };
  // Second factor on a signed-in device: the PIN when the account has one, or a fresh SMS code.
  const proof = async (localpart: string, b: Record<string, unknown>) => {
    if (b.pin !== undefined && d.pins.state(localpart) !== 'none') return d.pins.check(localpart, b.pin);
    const phone = d.accounts.phoneOf(localpart);
    if (!phone) throw new AppError('forbidden'); // the number now belongs to another account
    d.otp.verify(phone, str(b.code));
  };
  // Their tokens stop working here at once, not when the whoami cache entry expires.
  // Limit: a device that logs itself out stays cached up to 60 s (only lookups use the cache).
  const dropCached = (userId: string) => whoamiCache.deleteWhere((me) => me.userId === userId);
  const login = (phone: string, account: { localpart: string; userId: string; created: boolean }) => ({
    // `homeserver` is the public URL, for production clients. Dev clients use their own configured
    // base URL instead (the Android emulator reaches the host stack at http://10.0.2.2:8080).
    phone, user_id: account.userId, homeserver: d.publicBaseUrl, new_account: account.created,
    login_token: signJwt({ sub: account.localpart, iss: 'alo-id', aud: 'alo' }, d.jwtSecret, 120),
  });
  const pinClaims = (token: unknown) => {
    const c = verifyJwt(str(token), d.jwtSecret, now());
    if (c.aud !== PIN_AUD || c.iss !== 'alo-id' || typeof c.sub !== 'string' || typeof c.phone !== 'string') throw new AppError('invalid_token');
    return { localpart: c.sub, phone: c.phone };
  };

  return http.createServer(router({
    'GET /id/v1/health': () => ({ ok: true }),
    'POST /id/v1/otp/request': async (b, req) => {
      const phone = normalizePhone(str(b.phone));
      const { retryAfter } = await d.otp.request(phone, rateKey(clientIp(req)));
      return { phone, retry_after: retryAfter };
    },
    // With a PIN set, the SMS code alone gets a 5-minute pin_token, not a login: POST /id/v1/pin/login.
    'POST /id/v1/otp/verify': async (b) => {
      const phone = normalizePhone(str(b.phone));
      d.otp.verify(phone, str(b.code));
      const cur = d.accounts.current(phone);
      const pin = cur ? d.pins.state(cur.localpart) : 'none';
      // A forgotten PIN whose 7-day wait is over: the sign-in goes on as if there never was one.
      if (pin === 'reset_due') d.pins.remove(cur!.localpart);
      const account = await d.accounts.resolve(phone, { keep: pin === 'set' });
      d.directory.markRegistered(phone, account.localpart);
      if (pin !== 'set' || account.created) return login(phone, account);
      return {
        phone, pin_required: true, reset_at: d.pins.status(account.localpart).reset_at,
        pin_token: signJwt({ sub: account.localpart, phone, iss: 'alo-id', aud: PIN_AUD }, d.jwtSecret, 300, now()),
      };
    },
    'POST /id/v1/pin/login': async (b) => {
      const { localpart, phone } = pinClaims(b.pin_token);
      await d.pins.check(localpart, b.pin);
      const account = d.accounts.current(phone);
      if (account?.localpart !== localpart) throw new AppError('forbidden');
      d.accounts.touch(phone);
      return login(phone, { ...account, created: false });
    },
    // "Esqueci meu PIN": after 7 days a sign-in with the SMS code alone goes on. The account's
    // devices see the date (pin/status) and can cancel it.
    'POST /id/v1/pin/forgot': (b) => ({ reset_at: d.pins.requestReset(pinClaims(b.pin_token).localpart) }),
    'POST /id/v1/pin/status': async (_b, req) => {
      const { userId } = await whoami(req);
      return d.pins.status(localpartOf(userId));
    },
    // A new PIN; changing one needs the current PIN or a fresh SMS code.
    'POST /id/v1/pin/set': async (b, req) => {
      const me = await owner(req);
      if (d.pins.state(me.localpart) !== 'none') await proof(me.localpart, { pin: b.current_pin, code: b.code });
      await d.pins.set(me.localpart, str(b.pin));
      return {};
    },
    'POST /id/v1/pin/remove': async (b, req) => {
      const me = await owner(req);
      await proof(me.localpart, b);
      d.pins.remove(me.localpart);
      return {};
    },
    // The app's periodic reminder; wrong tries count toward the lock like any other.
    'POST /id/v1/pin/check': async (b, req) => {
      const me = await owner(req);
      if (d.pins.state(me.localpart) === 'none') throw new AppError('bad_request');
      await d.pins.check(me.localpart, b.pin);
      return {};
    },
    'POST /id/v1/pin/cancel-reset': async (_b, req) => {
      d.pins.cancelReset((await owner(req)).localpart);
      return {};
    },
    // "Aparelhos conectados": Matrix asks user-interactive auth to delete a device, which Alô
    // accounts cannot do (spec §4), so alo-id deletes it through the admin API after proof.
    'POST /id/v1/devices/remove': async (b, req) => {
      const me = await owner(req);
      // Both forms at once is ambiguous: refuse rather than guess which one was meant.
      if (b.all_others === true && b.device_ids !== undefined) throw new AppError('bad_request');
      const ids = b.all_others === true ? null : b.device_ids;
      if (ids !== null && (!Array.isArray(ids) || !ids.length || ids.length > 100 ||
        ids.some((x) => typeof x !== 'string' || !x || x.length > 255 || x === me.deviceId))) throw new AppError('bad_request');
      await proof(me.localpart, b);
      const removed = ids === null ? await d.admin.logoutOtherDevices(me.userId, me.deviceId) : await d.admin.deleteDevices(me.userId, ids);
      dropCached(me.userId);
      return { removed };
    },
    // Linking a web client by QR code (spec §5). The boxes are opaque here.
    'POST /id/v1/link': (_b, req) => {
      linkStarts.hit(rateKey(clientIp(req)));
      return d.links.create();
    },
    'POST /id/v1/link/offer': async (b, req) => {
      const me = await owner(req);
      d.links.offer(b.id, me.userId, box(b.box));
      return {};
    },
    'POST /id/v1/link/answer': async (b, req) => {
      const me = await owner(req);
      d.links.answer(b.id, me.userId, box(b.box));
      return {};
    },
    'POST /id/v1/link/poll': (b) => d.links.poll(b.id),
    'POST /id/v1/directory/lookup': async (b, req) => {
      const { userId } = await whoami(req);
      userLookups.hit(userId);
      return { registered: d.directory.lookup(b.hashes, userId, { now: now(), quota: DAILY_HASHES * scale }) };
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
      await d.pins.check(localpartOf(userId), b.pin); // spec §5: the PIN also gates resets
      d.otp.verify(phone, code);
      // Logout first: a reset must never leave another device signed in.
      const loggedOut = await d.admin.logoutOtherDevices(userId, deviceId);
      dropCached(userId);
      await d.admin.uploadCrossSigningKeys(userId, keys);
      return { logged_out_devices: loggedOut };
    },
  }, {
    'POST /id/v1/directory/lookup': 96 * 1024, // room for 1000 hashes (about 67 KB)
    'POST /id/v1/account/reset-identity': 8 * 1024, // a public key bundle is about 1.5 KB
  }));
}

if (import.meta.main) {
  const env = (k: string, def?: string) => {
    const v = process.env[k] ?? def;
    if (v === undefined || v === '') { console.error(`missing env ${k}`); process.exit(1); }
    return v;
  };
  const dev = process.env.ALO_DEV === '1';
  const port = Number(env('PORT', '8090'));
  if (!Number.isInteger(port) || port < 0 || port > 65535) { console.error(`invalid PORT ${process.env.PORT}`); process.exit(1); }
  const secrets = {
    pepper: env('OTP_PEPPER'), jwtSecret: env('JWT_SECRET'), serverName: env('SERVER_NAME'), publicBaseUrl: env('PUBLIC_BASEURL'),
    synapseUrl: env('SYNAPSE_INTERNAL_URL'), sharedSecret: env('REGISTRATION_SHARED_SECRET'), asToken: env('SYNAPSE_AS_TOKEN'),
  };
  // Dev mode accepts code 000000 for any phone, so it must never run on a real domain.
  if (dev && !/\.(test|localhost)$/.test(secrets.serverName)) {
    console.error('ALO_DEV=1 is only allowed for .test or .localhost server names'); process.exit(1);
  }
  // No real SMS provider exists yet; ConsoleSms prints codes, so it is dev only.
  if (!dev) { console.error('no SMS provider configured (set ALO_DEV=1 for development)'); process.exit(1); }
  const db = openDb(env('DB_PATH', '/data/alo-id.sqlite'));
  const admin = new HttpSynapseAdmin({ baseUrl: secrets.synapseUrl, sharedSecret: secrets.sharedSecret, asToken: secrets.asToken, db });
  const server = createServer({
    otp: new OtpService(db, { pepper: secrets.pepper, dev, sms: new ConsoleSms() }), pins: new Pins(db, { pepper: secrets.pepper }),
    links: new Links(db),
    directory: new Directory(db, secrets.serverName), accounts: new Accounts(db, admin, { serverName: secrets.serverName }), admin,
    jwtSecret: secrets.jwtSecret, publicBaseUrl: secrets.publicBaseUrl, dev,
  });
  server.listen(port, () => console.log(`alo-id listening on :${port}${dev ? ' (dev mode: code 000000 accepted)' : ''}`));
}
