// Test peer for the app's end-to-end test. Signs in one phone number, sets up
// cross-signing like a real Alô device (spec §5: keys only reach verified
// devices), joins every invite, and answers like a real person would:
//   - says "oi, entrei" after joining a chat,
//   - acks each message with Olm-encrypted to-device app.usealo.delivered (grey ✓✓),
//   - sends a read receipt 3 s later (blue ✓✓),
//   - replies "eco: <text>" to text (not to edits), "recebi: foto criptografada" to an
//     encrypted image and "recebi: voz criptografada" to an encrypted voice note,
//   - answers a text that starts with "demora" 30 s later instead of 3 s (time
//     to close the app and receive the answer as a push).
// Env: PEER_PHONE (E.164 digits, required), ALO_BASE_URL (default
// http://localhost:8080), PEER_NAME (default "Peer").
import * as sdk from 'matrix-js-sdk';

const baseUrl = process.env.ALO_BASE_URL ?? 'http://localhost:8080';
const phone = process.env.PEER_PHONE;
if (!phone) {
  console.error('PEER_PHONE is required');
  process.exit(1);
}

async function post(path: string, body: unknown): Promise<any> {
  const res = await fetch(baseUrl + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${path}: ${res.status} ${JSON.stringify(json)}`);
  return json;
}

await post('/id/v1/otp/request', { phone });
const { login_token } = await post('/id/v1/otp/verify', { phone, code: '000000' });
const login = await sdk.createClient({ baseUrl }).loginRequest({ type: 'org.matrix.login.jwt', token: login_token });
const me = login.user_id;
const client = sdk.createClient({ baseUrl, userId: me, accessToken: login.access_token, deviceId: login.device_id });
await client.initRustCrypto({ useIndexedDB: false });
// First upload of cross-signing keys needs no auth on Synapse (MSC3967).
await client.getCrypto()!.bootstrapCrossSigning({ authUploadDeviceSigningKeys: (makeRequest) => makeRequest(null) });
await client.setDisplayName(process.env.PEER_NAME ?? 'Peer');

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const joined = new Set<string>();

// Logs a failed step instead of letting one bad call kill the peer mid-test.
const step = (what: string, fn: () => Promise<void>) => () =>
  fn().catch((e) => console.error(`${what} failed:`, e));

client.on(sdk.RoomMemberEvent.Membership, (_ev, member) => {
  if (member.userId !== me || member.membership !== 'invite' || joined.has(member.roomId)) return;
  joined.add(member.roomId);
  void step(`join ${member.roomId}`, async () => {
    await client.joinRoom(member.roomId);
    await sleep(1000);
    await client.sendTextMessage(member.roomId, 'oi, entrei');
    console.log(`joined ${member.roomId}`);
  })();
});

const answered = new Set<string>();

async function answer(ev: sdk.MatrixEvent, roomId: string): Promise<void> {
  // The room key can arrive after the message: wait for the next decryption
  // attempt instead of answering an m.bad.encrypted placeholder.
  if (ev.isDecryptionFailure()) {
    console.log(`waiting for key of ${ev.getId()}`);
    ev.once(sdk.MatrixEventEvent.Decrypted, step(`answer ${ev.getId()}`, () => answer(ev, roomId)));
    return;
  }
  if (ev.getType() !== 'm.room.message' || !ev.isEncrypted() || answered.has(ev.getId()!)) return;
  answered.add(ev.getId()!);
  const sender = ev.getSender()!;
  const content = ev.getContent();
  // Olm-encrypted, as the app sends them: it ignores plaintext acks.
  const devices = [...((await client.getCrypto()!.getUserDeviceInfo([sender])).get(sender)?.keys() ?? [])];
  await client.queueToDevice(
    await client.getCrypto()!.encryptToDeviceMessages(
      'app.usealo.delivered',
      devices.map((deviceId) => ({ userId: sender, deviceId })),
      { room_id: roomId, event_ids: [ev.getId()], ts: ev.getTs() },
    ),
  );
  await sleep(3000);
  await client.sendReadReceipt(ev, sdk.ReceiptType.Read, true);
  if (typeof content.body === 'string' && content.body.startsWith('demora')) await sleep(30_000);
  const encryptedFile = typeof content.file?.url === 'string' && content.url === undefined;
  let reply: string | undefined;
  // Replies carry the quoted message as "> " lines first (reply fallback): echo only the new text.
  if (content.msgtype === 'm.text') reply = `eco: ${content.body.replace(/^(> .*\n)+\n/, '')}`;
  if (content.msgtype === 'm.image' && encryptedFile) reply = 'recebi: foto criptografada';
  if (content.msgtype === 'm.audio' && encryptedFile && content['org.matrix.msc3245.voice'] &&
    Array.isArray(content['org.matrix.msc1767.audio']?.waveform)) reply = 'recebi: voz criptografada';
  const isEdit = content['m.relates_to']?.rel_type === 'm.replace';
  if (reply && !isEdit && !content.body?.startsWith('eco: ')) await client.sendTextMessage(roomId, reply);
  console.log(`answered ${content.msgtype} from ${sender}`);
}

client.on(sdk.RoomEvent.Timeline, (ev, room, toStart) => {
  if (toStart || !room || ev.getSender() === me) return;
  void step(`answer ${ev.getId()}`, async () => {
    await client.decryptEventIfNeeded(ev);
    await answer(ev, room.roomId);
  })();
});

client.once(sdk.ClientEvent.Sync, (state) => {
  if (state === 'PREPARED') console.log(`peer ready ${me}`);
});
await client.startClient({ initialSyncLimit: 10 });
process.on('SIGTERM', () => {
  client.stopClient();
  process.exit(0);
});
