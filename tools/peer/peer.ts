// Test peer for the app's end-to-end test. Signs in one phone number, sets up
// cross-signing like a real Chama device (spec §5: keys only reach verified
// devices), joins every invite, and answers like a real person would:
//   - says "oi, entrei" after joining a chat,
//   - acks each message with to-device chat.chama.delivered (grey ✓✓),
//   - sends a read receipt 3 s later (blue ✓✓),
//   - replies "eco: <text>" to text, "recebi: foto criptografada" to an
//     encrypted image and "recebi: voz criptografada" to an encrypted voice note.
// Env: PEER_PHONE (E.164 digits, required), CHAMA_BASE_URL (default
// http://localhost:8080), PEER_NAME (default "Peer").
import * as sdk from 'matrix-js-sdk';

const baseUrl = process.env.CHAMA_BASE_URL ?? 'http://localhost:8080';
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

client.on(sdk.RoomMemberEvent.Membership, async (_ev, member) => {
  if (member.userId !== me || member.membership !== 'invite' || joined.has(member.roomId)) return;
  joined.add(member.roomId);
  await client.joinRoom(member.roomId);
  await sleep(1000);
  await client.sendTextMessage(member.roomId, 'oi, entrei');
  console.log(`joined ${member.roomId}`);
});

client.on(sdk.RoomEvent.Timeline, async (ev, room, toStart) => {
  if (toStart || !room || ev.getSender() === me) return;
  await client.decryptEventIfNeeded(ev);
  if (ev.getType() !== 'm.room.message' || !ev.isEncrypted()) return;
  const sender = ev.getSender()!;
  const content = ev.getContent();
  await client.sendToDevice(
    'chat.chama.delivered',
    new Map([[sender, new Map([['*', { room_id: room.roomId, event_ids: [ev.getId()], ts: ev.getTs() }]])]]),
  );
  await sleep(3000);
  await client.sendReadReceipt(ev, sdk.ReceiptType.Read, true);
  const encryptedFile = typeof content.file?.url === 'string' && content.url === undefined;
  let reply: string | undefined;
  if (content.msgtype === 'm.text') reply = `eco: ${content.body}`;
  if (content.msgtype === 'm.image' && encryptedFile) reply = 'recebi: foto criptografada';
  if (content.msgtype === 'm.audio' && encryptedFile && content['org.matrix.msc3245.voice'] &&
    Array.isArray(content['org.matrix.msc1767.audio']?.waveform)) reply = 'recebi: voz criptografada';
  if (reply && !content.body?.startsWith('eco: ')) await client.sendTextMessage(room.roomId, reply);
  console.log(`answered ${content.msgtype} from ${sender}`);
});

client.once(sdk.ClientEvent.Sync, (state) => {
  if (state === 'PREPARED') console.log(`peer ready ${me}`);
});
await client.startClient({ initialSyncLimit: 10 });
process.on('SIGTERM', () => {
  client.stopClient();
  process.exit(0);
});
