// End-to-end smoke test: two users sign in by phone, A finds B by phone hash,
// A sends an encrypted message, B decrypts it, and the server database holds only
// ciphertext. Needs the dev stack (make up).
import { execFileSync } from 'node:child_process';
import { createHash, randomInt } from 'node:crypto';
import { join } from 'node:path';
import * as sdk from 'matrix-js-sdk';
import { logger } from 'matrix-js-sdk/lib/logger.js';

// The SDK logs every sync and crypto step, and its child loggers reset themselves to
// debug level. Child loggers copy the root's method factory, so filter there: errors only.
// These are loglevel internals; if a new SDK drops them, the run is just noisier.
const root = logger as any;
if (typeof root.methodFactory === 'function' && typeof root.rebuild === 'function') {
  root.methodFactory = (method: string) => (method === 'error' ? console.error : () => {});
  root.rebuild();
} else console.warn('smoke: matrix-js-sdk logger internals changed; SDK logs not filtered');

const BASE = process.env.BASE ?? 'http://localhost:8080';
const TEXT = 'Olá do Chama 🔥';
let step = 'start';

const timer = setTimeout(() => {
  console.error(`smoke: FAIL (timed out after 60 s at step: ${step})`);
  process.exit(1);
}, 60_000);

async function post(path: string, body: unknown, token?: string): Promise<any> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  const res = await fetch(BASE + path, { method: 'POST', headers, body: JSON.stringify(body) });
  const text = await res.text();
  if (!res.ok) throw new Error(`POST ${path}: ${res.status} ${text}`);
  return JSON.parse(text);
}

async function signIn(name: string) {
  const phone = `55119${String(randomInt(1e8)).padStart(8, '0')}`;
  step = `${name}: sign in`;
  await post('/id/v1/otp/request', { phone });
  const v = await post('/id/v1/otp/verify', { phone, code: '000000' });
  if (v.phone !== phone) throw new Error(`${name}: chama-id normalised ${phone} to ${v.phone}`);
  if (!/^@u[a-z2-7]{16}:chama\.test$/.test(v.user_id)) throw new Error(`${name}: user_id not opaque: ${v.user_id}`);
  if (v.user_id.includes(phone.slice(-8))) throw new Error(`${name}: user_id contains phone digits: ${v.user_id}`);
  const login = await sdk.createClient({ baseUrl: BASE }).loginRequest({ type: 'org.matrix.login.jwt', token: v.login_token });
  if (login.user_id !== v.user_id) throw new Error(`${name}: login user ${login.user_id} != chama-id user ${v.user_id}`);
  const client = sdk.createClient({ baseUrl: BASE, userId: login.user_id, accessToken: login.access_token, deviceId: login.device_id });

  step = `${name}: start crypto and sync`;
  await client.initRustCrypto({ useIndexedDB: false });
  const prepared = new Promise<void>((resolve) => {
    const onSync = (state: sdk.SyncState) => {
      if (state === sdk.SyncState.Prepared) {
        client.off(sdk.ClientEvent.Sync, onSync);
        resolve();
      }
    };
    client.on(sdk.ClientEvent.Sync, onSync);
  });
  await client.startClient({ initialSyncLimit: 10 });
  await prepared;
  console.log(`ok: ${name} signed in as ${v.user_id}`);
  return { client, userId: v.user_id as string, phone, token: login.access_token };
}

// Resolves when user `userId` has membership `want` in room `roomId`, as seen by `client`.
function membership(client: sdk.MatrixClient, userId: string, want: string, roomId?: string) {
  return new Promise<string>((resolve) => {
    const check = (_ev: sdk.MatrixEvent, m: sdk.RoomMember) => {
      if (m.userId === userId && m.membership === want && (!roomId || m.roomId === roomId)) {
        client.off(sdk.RoomMemberEvent.Membership, check);
        resolve(m.roomId);
      }
    };
    client.on(sdk.RoomMemberEvent.Membership, check);
    if (roomId && client.getRoom(roomId)?.getMember(userId)?.membership === want) resolve(roomId);
  });
}

try {
  const a = await signIn('A');
  const b = await signIn('B');

  step = 'A: look up B by phone hash';
  const hash = createHash('sha256').update(b.phone).digest('hex');
  const found = await post('/id/v1/directory/lookup', { hashes: [hash] }, a.token);
  const bId = found.registered?.find((r: any) => r.hash === hash)?.user_id;
  if (bId !== b.userId) throw new Error(`lookup returned ${bId}, want ${b.userId}`);
  console.log(`ok: A found B by phone hash: ${bId}`);

  step = 'A: create room and invite B';
  const invited = membership(b.client, b.userId, 'invite');
  const { room_id: roomId } = await a.client.createRoom({ is_direct: true, invite: [bId], preset: sdk.Preset.TrustedPrivateChat });
  // Only a 404 means "no encryption state"; any other error fails with its own cause.
  const enc = await a.client.getStateEvent(roomId, 'm.room.encryption', '')
    .catch((e) => { if (e?.httpStatus === 404) return null; throw e; });
  if (enc?.algorithm !== 'm.megolm.v1.aes-sha2') throw new Error(`room ${roomId} has no m.room.encryption: server default is broken`);
  console.log(`ok: room ${roomId} encrypted by default (${enc.algorithm})`);

  step = 'B: receive invite and join';
  const joined = membership(a.client, b.userId, 'join', roomId);
  if ((await invited) !== roomId) throw new Error('B got an invite to another room');
  await b.client.joinRoom(roomId);
  step = 'A: see B joined';
  await joined;
  console.log('ok: B joined');

  step = 'B: receive and decrypt message';
  const received = new Promise<sdk.MatrixEvent>((resolve) => {
    b.client.on(sdk.MatrixEventEvent.Decrypted, (ev) => {
      if (ev.getRoomId() !== roomId) return;
      // A failure may be retried when the key arrives; keep the reason in case it never does.
      if (ev.isDecryptionFailure()) step = `B: decrypt message (last failure: ${ev.decryptionFailureReason})`;
      else if (ev.getType() === 'm.room.message') resolve(ev);
    });
  });
  const { event_id: eventId } = await a.client.sendTextMessage(roomId, TEXT);
  const ev = await received;
  if (ev.getId() !== eventId) throw new Error(`B decrypted ${ev.getId()}, want the sent event ${eventId}`);
  if (ev.getSender() !== a.userId) throw new Error(`sender ${ev.getSender()}, want ${a.userId}`);
  if (!ev.isEncrypted()) throw new Error('message was not encrypted');
  if (ev.getContent().body !== TEXT) throw new Error(`decrypted body ${JSON.stringify(ev.getContent().body)}, want ${JSON.stringify(TEXT)}`);
  if (ev.getWireType() !== 'm.room.encrypted') throw new Error(`wire type ${ev.getWireType()}`);
  console.log('ok: B decrypted the message');

  // The stored event must be m.room.encrypted with ciphertext, and no stored event may
  // contain the plaintext. "do Chama" is the ASCII part of TEXT, so JSON escaping cannot hide it.
  step = 'server DB: check the stored event';
  if (!/^\$[\w-]+$/.test(eventId)) throw new Error(`unexpected event id ${eventId}`);
  const sql = `select e.type, j.json like '%"ciphertext"%', (select count(*) from event_json where json like '%do Chama%')
    from events e join event_json j using (event_id) where e.event_id = '${eventId}'`;
  const server = join(import.meta.dirname, '../../server');
  const row = execFileSync('docker', ['compose', '-f', join(server, 'compose.yaml'), '--env-file', join(server, 'data/.env'),
    'exec', '-T', 'postgres', 'psql', '-U', 'synapse', '-tA', '-c', sql], { encoding: 'utf8', timeout: 20_000 }).trim();
  if (row !== 'm.room.encrypted|t|0') throw new Error(`got '${row}', want 'm.room.encrypted|t|0' (encrypted type, ciphertext stored, plaintext in 0 events)`);
  console.log(`ok: server DB stores ${eventId} as m.room.encrypted ciphertext; plaintext in 0 events`);

  console.log('smoke: OK (encrypted message delivered and decrypted)');
  a.client.stopClient();
  b.client.stopClient();
  clearTimeout(timer);
  process.exit(0);
} catch (err) {
  console.error(`smoke: FAIL at step: ${step}: ${(err as Error).message}`);
  process.exit(1);
}
