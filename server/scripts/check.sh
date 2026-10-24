#!/usr/bin/env bash
# Acceptance checks for the running dev stack. Stops at the first failure.
# Each run requests a code for a new random phone, because chama-id allows one code
# request per phone per minute. In dev mode chama-id allows 1000 code requests per IP per hour.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE=${BASE:-http://localhost:8080}
# Dev ntfy as the host reaches it, and as the emulator does (push endpoints use that one).
NTFY=${NTFY:-http://localhost:8081}
NTFY_EMU=${NTFY_EMU:-http://10.0.2.2:8081}
PHONE=${PHONE:-119$(printf '%04d%04d' $((RANDOM % 10000)) $((RANDOM % 10000)))}
MARK=check$RANDOM$RANDOM
dc() { docker compose -f compose.yaml --env-file data/.env "$@"; }
# Prints one top-level JSON field; exits 1 when it is missing or null.
json() { node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8"))[process.argv[1]]; if (v == null) process.exit(1); console.log(v)' "$1"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }
# Lines a service logged for this run's marker.
served_by() { dc logs --no-log-prefix "$1" 2>/dev/null | grep -c "$2" || true; }

out=$(curl -fs "$BASE/_matrix/client/versions") || fail "client/versions"
grep -q '"versions"' <<<"$out" || fail "client/versions body: $out"
ok "client/versions: ${out:0:80}"

# Only caddy publishes ports, and only on localhost (8081 is the dev ntfy).
pub=$(dc ps --format json | node -e '
  const t = require("fs").readFileSync(0, "utf8").trim();
  const rows = t.startsWith("[") ? JSON.parse(t) : t.split("\n").map((l) => JSON.parse(l));
  const out = new Set();
  for (const r of rows) for (const p of r.Publishers || []) if (p.PublishedPort) out.add(r.Service + " " + p.URL + ":" + p.PublishedPort);
  console.log([...out].sort().join(", "));')
[[ $pub == "caddy 127.0.0.1:8080, caddy 127.0.0.1:8081" ]] || fail "published ports: '$pub', want 'caddy 127.0.0.1:8080, caddy 127.0.0.1:8081'"
ok "published ports: $pub"

out=$(curl -fs "$BASE/id/v1/health") || fail "id health"
[[ $out == '{"ok":true}' ]] || fail "id health body: $out"
ok "id health: $out"

curl -fs -XPOST "$BASE/id/v1/otp/request" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\"}" >/dev/null || fail "otp request for $PHONE"
VERIFY=$(curl -fs -XPOST "$BASE/id/v1/otp/verify" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"code\":\"000000\"}") || fail "otp verify"
TOKEN=$(json login_token <<<"$VERIFY") || fail "otp verify: no login_token"
MXID=$(json user_id <<<"$VERIFY") || fail "otp verify: no user_id"
E164=$(json phone <<<"$VERIFY") || fail "otp verify: no phone"
[[ $MXID =~ ^@u[a-z2-7]{16}:chama\.test$ ]] || fail "user_id not opaque: $MXID"
[[ $MXID != *"${E164: -8}"* ]] || fail "user_id contains phone digits: $MXID"
[[ $(json new_account <<<"$VERIFY") == true ]] || fail "new phone: new_account not true"
ok "otp verify: opaque user_id $MXID for +$E164"

# Full sign-in: the chama-id JWT logs in to Synapse and yields an access token.
ACCESS=$(curl -fs -XPOST "$BASE/_matrix/client/v3/login" -H 'content-type: application/json' \
  -d "{\"type\":\"org.matrix.login.jwt\",\"token\":\"$TOKEN\"}" | json access_token) || fail "jwt login"
AUTH="Authorization: Bearer $ACCESS"
got=$(curl -fs -H "$AUTH" "$BASE/_matrix/client/v3/account/whoami" | json user_id) || fail "whoami"
[[ $got == "$MXID" ]] || fail "whoami: got $got, want $MXID"
ok "jwt login + whoami: $got"

HASH=$(printf %s "$E164" | openssl sha256 | awk '{print $NF}')
code=$(curl -s -o /dev/null -w '%{http_code}' -XPOST "$BASE/id/v1/directory/lookup" -H 'content-type: application/json' \
  -d "{\"hashes\":[\"$HASH\"]}")
[[ $code == 401 ]] || fail "lookup without token: $code, want 401"
ok "lookup without token: $code"
out=$(curl -fs -XPOST "$BASE/id/v1/directory/lookup" -H "$AUTH" -H 'content-type: application/json' \
  -d "{\"hashes\":[\"$HASH\"]}") || fail "lookup with token"
[[ $out == "{\"registered\":[{\"hash\":\"$HASH\",\"user_id\":\"$MXID\"}]}" ]] || fail "lookup body: $out"
ok "lookup with token: $out"

out=$(curl -fs -H "$AUTH" "$BASE/_matrix/client/v3/sync?timeout=0&$MARK=1") || fail "sync"
grep -q '"next_batch"' <<<"$out" || fail "sync body: ${out:0:100}"
sleep 1
[[ $(served_by sync1 "$MARK") -ge 1 ]] || fail "sync not in sync1 logs"
[[ $(served_by synapse "$MARK") -eq 0 ]] || fail "sync reached the main process"
ok "sync served by sync1: ${out:0:60}"

MXC=$(echo hello | curl -fs -XPOST -H "$AUTH" -H 'content-type: text/plain' --data-binary @- \
  "$BASE/_matrix/media/v3/upload?filename=$MARK.txt" | json content_uri) || fail "media upload"
out=$(curl -fs -H "$AUTH" "$BASE/_matrix/client/v1/media/download/${MXC#mxc://}?$MARK=1") || fail "media download"
[[ $out == hello ]] || fail "media download body: $out"
sleep 1
[[ $(served_by media1 "$MARK") -ge 2 ]] || fail "upload and download not both in media1 logs"
[[ $(served_by synapse "$MARK") -eq 0 ]] || fail "media reached the main process"
ok "media round trip via media1: $MXC -> $out"

# chama-id's own admin client against the real Synapse admin API (internal network only).
# After logout the device is gone, but the user-level last_seen still marks the account active.
curl -fs -XPOST -H "$AUTH" "$BASE/_matrix/client/v3/logout" -d '{}' >/dev/null || fail "logout"
admin_check() { dc exec -T -e MXID="$MXID" chama-id node --input-type=module -e "
  import { openDb } from './src/db.ts'; import { HttpSynapseAdmin } from './src/synapse.ts';
  const e = process.env;
  const a = new HttpSynapseAdmin({ baseUrl: e.SYNAPSE_INTERNAL_URL, sharedSecret: e.REGISTRATION_SHARED_SECRET, asToken: e.SYNAPSE_AS_TOKEN, db: openDb(e.DB_PATH) });
  const age = Date.now() - (await a.activity(e.MXID)).lastActiveMs;
  console.log(age >= 0 && age < 600_000, await a.activity('@uzzzzzzzzzzzzzzzz:chama.test'));" | tail -1; }
# Synapse writes client IPs in batches every few seconds.
for _ in 1 2 3 4 5 6 7 8 9 10; do out=$(admin_check) || fail "admin client"; [[ $out == 'true null' ]] && break; sleep 2; done
[[ $out == 'true null' ]] || fail "admin client after logout: want 'true null' (recently active, unknown user), got '$out'"
ok "admin client: $MXID still recently active after logout, unknown user is null"

# Recycled-number path: chama-id's admin client deactivates an account, and its token stops working.
PHONE2=119$(printf '%04d%04d' $((RANDOM % 10000)) $((RANDOM % 10000)))
curl -fs -XPOST "$BASE/id/v1/otp/request" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE2\"}" >/dev/null || fail "otp request for $PHONE2"
V2=$(curl -fs -XPOST "$BASE/id/v1/otp/verify" -H 'content-type: application/json' -d "{\"phone\":\"$PHONE2\",\"code\":\"000000\"}") || fail "otp verify $PHONE2"
MXID2=$(json user_id <<<"$V2") || fail "otp verify $PHONE2: no user_id"
ACCESS2=$(curl -fs -XPOST "$BASE/_matrix/client/v3/login" -H 'content-type: application/json' \
  -d "{\"type\":\"org.matrix.login.jwt\",\"token\":\"$(json login_token <<<"$V2")\"}" | json access_token) || fail "jwt login $MXID2"
curl -fs -H "Authorization: Bearer $ACCESS2" "$BASE/_matrix/client/v3/account/whoami" >/dev/null || fail "whoami $MXID2 before deactivate"
dc exec -T -e MXID="$MXID2" chama-id node --input-type=module -e "
  import { openDb } from './src/db.ts'; import { HttpSynapseAdmin } from './src/synapse.ts';
  const e = process.env;
  await new HttpSynapseAdmin({ baseUrl: e.SYNAPSE_INTERNAL_URL, sharedSecret: e.REGISTRATION_SHARED_SECRET, asToken: e.SYNAPSE_AS_TOKEN, db: openDb(e.DB_PATH) }).deactivate(e.MXID);" \
  || fail "admin deactivate $MXID2"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $ACCESS2" "$BASE/_matrix/client/v3/account/whoami")
[[ $code == 401 ]] || fail "token after deactivate: $code, want 401"
ok "admin deactivate: $MXID2 token now $code"

# Identity reset (spec §5): bootstrap cross-signing, second device, reset, other device logged out.
BASE=$BASE node ../tools/smoke/identity.ts || fail "identity reset"

# M4 (spec §4, §5): the login token for linking, the link rendezvous, device removal, the account PIN.
BASE=$BASE node ../tools/smoke/safety.ts || fail "account safety"
# Recycled numbers over HTTP against the real Synapse, with a PIN and after a deactivation (issue #3).
dc exec -T chama-id node --input-type=module - <../tools/smoke/recycled.ts || fail "recycled numbers"
# No Chama account holds an access token without a device: deleting devices would not end it (issue #3).
n=$(dc exec -T postgres psql -U synapse -tAc \
  "SELECT count(*) FROM access_tokens WHERE device_id IS NULL AND user_id ~ '^@u[a-z2-7]{16}:'") || fail "token query"
[[ $n == 0 ]] || fail "$n access tokens without a device"
ok "no account has an access token without a device"

# The application service token works from the internal network and is refused from a public address.
out=$(dc exec -T chama-id node -e "
  const w = (xff) => fetch(process.env.SYNAPSE_INTERNAL_URL + '/_matrix/client/v3/account/whoami', { headers:
    { authorization: 'Bearer ' + process.env.SYNAPSE_AS_TOKEN, ...(xff ? { 'x-forwarded-for': xff } : {}) } }).then((r) => r.status);
  Promise.all([w(), w('8.8.8.8')]).then((s) => console.log(s.join(' ')));") || fail "app service token check"
[[ $out == '200 401' ]] || fail "app service token: internal and public got '$out', want '200 401'"
ok "app service token: internal 200, public address 401"

flows=$(curl -fs "$BASE/_matrix/client/v3/login") || fail "login flows"
[[ $flows != *m.login.password* ]] || fail "login flows offer password: $flows"
ok "login flows: $flows"

# The real password of a real user must still be refused. chama-id accounts have no
# password, so make one by shared-secret registration on the internal network.
MXUSER=check$RANDOM$RANDOM
MXPASS=$(dc exec -T -e MXUSER="$MXUSER" synapse python - <<'PY'
import hashlib, hmac, json, os, secrets, urllib.request, yaml
key = yaml.safe_load(open('/data/homeserver.yaml'))['registration_shared_secret'].encode()
url = 'http://localhost:8008/_synapse/admin/v1/register'
nonce = json.load(urllib.request.urlopen(url))['nonce']
user, pw = os.environ['MXUSER'], secrets.token_hex(16)
mac = hmac.new(key, b'\0'.join([nonce.encode(), user.encode(), pw.encode(), b'notadmin']), hashlib.sha1).hexdigest()
body = json.dumps({'nonce': nonce, 'username': user, 'password': pw, 'admin': False, 'mac': mac}).encode()
urllib.request.urlopen(urllib.request.Request(url, body, {'content-type': 'application/json'}))
print(pw)
PY
) || fail "shared-secret registration"
out=$(curl -s -w ' %{http_code}' -XPOST "$BASE/_matrix/client/v3/login" -H 'content-type: application/json' \
  -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"$MXUSER\"},\"password\":\"$MXPASS\"}")
[[ $out == *'Password login has been disabled'*' 400' ]] || fail "password login not disabled: $out"
ok "password login refused for $MXUSER with its real password: $out"

out=$(curl -s -w ' %{http_code}' -XPOST "$BASE/_matrix/client/v3/register" -H 'content-type: application/json' \
  -d '{"username":"x","password":"y","auth":{"type":"m.login.dummy"}}')
[[ $out == *M_FORBIDDEN*' 403' ]] || fail "registration not refused: $out"
ok "registration refused: $out"

code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/_synapse/admin/v1/server_version")
[[ $code == 403 ]] || fail "admin API at edge: $code"
ok "admin API blocked at edge: $code"

code=$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS "$BASE/_matrix/client/v3/sync")
[[ $code == 204 ]] || fail "OPTIONS: $code"
ok "OPTIONS preflight: $code"

code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/not-a-route")
[[ $code == 404 ]] || fail "unknown path: $code"
ok "unknown path: $code"

# Push (spec §6): Synapse's pusher worker -> Sygnal (Web Push) -> ntfy, as for a phone.
signin() {
  local phone=119$(printf '%04d%04d' $((RANDOM % 10000)) $((RANDOM % 10000)))
  curl -fs -XPOST "$BASE/id/v1/otp/request" -H 'content-type: application/json' -d "{\"phone\":\"$phone\"}" >/dev/null
  local jwt; jwt=$(curl -fs -XPOST "$BASE/id/v1/otp/verify" -H 'content-type: application/json' \
    -d "{\"phone\":\"$phone\",\"code\":\"000000\"}" | json login_token)
  curl -fs -XPOST "$BASE/_matrix/client/v3/login" -H 'content-type: application/json' \
    -d "{\"type\":\"org.matrix.login.jwt\",\"token\":\"$jwt\"}"
}
A=$(signin) || fail "push: sign in A"; B=$(signin) || fail "push: sign in B"
TA=$(json access_token <<<"$A"); TB=$(json access_token <<<"$B"); UB=$(json user_id <<<"$B")
CFG=$(curl -fs "$BASE/push/v1/config") || fail "push config"
GATEWAY=$(json gateway <<<"$CFG"); [[ $(json vapid <<<"$CFG") =~ ^B[A-Za-z0-9_-]{86}$ ]] || fail "push config vapid: $CFG"
ok "push config: $GATEWAY"
# A Web Push subscription like the phone's: P-256 key pair + 16-byte auth secret.
read -r P256DH UA_KEY < <(node -e 'const k = require("crypto").generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  console.log(k.publicKey.export({ type: "spki", format: "der" }).subarray(-65).toString("base64url"),
    k.privateKey.export({ type: "pkcs8", format: "der" }).toString("base64"))')
WP_AUTH=$(node -e 'console.log(require("crypto").randomBytes(16).toString("base64url"))')
TOPIC=up$(openssl rand -hex 6)
curl -fs -XPOST "$BASE/_matrix/client/v3/pushers/set" -H "Authorization: Bearer $TA" -H 'content-type: application/json' -d "{
  \"kind\":\"http\",\"app_id\":\"chat.chama.app\",\"pushkey\":\"$P256DH\",\"app_display_name\":\"Chama\",
  \"device_display_name\":\"check\",\"lang\":\"pt-BR\",\"data\":{\"url\":\"$GATEWAY\",\"format\":\"event_id_only\",
  \"endpoint\":\"$NTFY_EMU/$TOPIC?up=1\",\"auth\":\"$WP_AUTH\",\"events_only\":true}}" >/dev/null || fail "pushers/set"
ROOM=$(curl -fs -XPOST "$BASE/_matrix/client/v3/createRoom" -H "Authorization: Bearer $TA" -H 'content-type: application/json' \
  -d "{\"invite\":[\"$UB\"],\"is_direct\":true,\"preset\":\"trusted_private_chat\"}" | json room_id) || fail "createRoom"
curl -fs -XPOST "$BASE/_matrix/client/v3/join/$ROOM" -H "Authorization: Bearer $TB" -d '{}' >/dev/null || fail "B join"
curl -fs -XPUT "$BASE/_matrix/client/v3/rooms/$ROOM/send/m.room.message/t$RANDOM" -H "Authorization: Bearer $TB" \
  -H 'content-type: application/json' -d '{"msgtype":"m.text","body":"push check"}' >/dev/null || fail "B send"
for _ in $(seq 20); do
  got=$(curl -fs "$NTFY/$TOPIC/json?poll=1" || true)
  [[ $got == *'"encoding":"base64"'* ]] && break
  sleep 1
done
[[ $got == *'"encoding":"base64"'* ]] || fail "no encrypted push on ntfy topic $TOPIC: '$got'"
ok "push: B's message reached A's ntfy topic as encrypted Web Push"
# Decrypt it as the phone does (RFC 8291, aes128gcm): IDs and counts only, no content, no sender.
body=$(grep -m1 '"encoding":"base64"' <<<"$got" | P256DH=$P256DH UA_KEY=$UA_KEY WP_AUTH=$WP_AUTH node -e '
  const c = require("crypto"), e = process.env;
  const m = Buffer.from(JSON.parse(require("fs").readFileSync(0, "utf8")).message, "base64");
  const salt = m.subarray(0, 16), as = m.subarray(21, 21 + m[20]), ct = m.subarray(21 + m[20]);
  const ua = Buffer.from(e.P256DH, "base64url");
  const jwk = { kty: "EC", crv: "P-256", x: as.subarray(1, 33).toString("base64url"), y: as.subarray(33).toString("base64url") };
  const ecdh = c.diffieHellman({ publicKey: c.createPublicKey({ key: jwk, format: "jwk" }),
    privateKey: c.createPrivateKey({ key: Buffer.from(e.UA_KEY, "base64"), format: "der", type: "pkcs8" }) });
  const hkdf = (ikm, s, info, n) => Buffer.from(c.hkdfSync("sha256", ikm, s, info, n));
  const ikm = hkdf(ecdh, Buffer.from(e.WP_AUTH, "base64url"), Buffer.concat([Buffer.from("WebPush: info\0"), ua, as]), 32);
  const d = c.createDecipheriv("aes-128-gcm", hkdf(ikm, salt, "Content-Encoding: aes128gcm\0", 16),
    hkdf(ikm, salt, "Content-Encoding: nonce\0", 12));
  d.setAuthTag(ct.subarray(-16));
  const p = Buffer.concat([d.update(ct.subarray(0, -16)), d.final()]);
  console.log(p.subarray(0, p.lastIndexOf(2)).toString());') || fail "push decrypt"
[[ $(json room_id <<<"$body") == "$ROOM" ]] && json event_id <<<"$body" >/dev/null || fail "push body: $body"
[[ $body != *'"content"'* && $body != *'"sender'* && $body != *'push check'* ]] || fail "push carries content: $body"
ok "push: decrypted body has IDs only: $body"
# Muted chat: the rule the app's "Silenciar" sets (matrix SDK Room.setPushRuleState(dontNotify)).
curl -fs -XPUT "$BASE/_matrix/client/v3/pushrules/global/override/$ROOM" -H "Authorization: Bearer $TA" \
  -H 'content-type: application/json' \
  -d "{\"actions\":[],\"conditions\":[{\"kind\":\"event_match\",\"key\":\"room_id\",\"pattern\":\"$ROOM\"}]}" \
  >/dev/null || fail "mute room"
curl -fs -XPUT "$BASE/_matrix/client/v3/rooms/$ROOM/send/m.room.message/t$RANDOM" -H "Authorization: Bearer $TB" \
  -H 'content-type: application/json' -d '{"msgtype":"m.text","body":"muted"}' >/dev/null || fail "B send muted"
sleep 5
n=$(curl -fs "$NTFY/$TOPIC/json?poll=1" | grep -c '"event":"message"')
[[ $n == 1 ]] || fail "muted chat still pushed: $n messages on $TOPIC"
ok "push: a muted chat sends no push"

# Sygnal sits on the push network only: Synapse, chama-id, Postgres and Redis are out of its reach.
out=$(dc exec -T sygnal python -c "
import socket
for h, p in [('synapse', 8008), ('synapse', 9093), ('chama-id', 8090), ('postgres', 5432), ('redis', 6379)]:
    try: socket.create_connection((h, p), 2).close(); print(h, p, 'reachable')
    except OSError: pass") || fail "sygnal reach check"
[[ -z $out ]] || fail "sygnal reaches internal services: $out"
ok "sygnal cannot reach synapse, chama-id, postgres or redis"

echo "all checks passed"
