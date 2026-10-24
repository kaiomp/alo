#!/usr/bin/env bash
# Acceptance checks for the running dev stack. Stops at the first failure.
# Each run requests a code for a new random phone, because chama-id allows one code
# request per phone per minute. chama-id also allows 10 requests per IP per hour.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE=${BASE:-http://localhost:8080}
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

# Only caddy publishes a port, and only on localhost.
pub=$(dc ps --format json | node -e '
  const t = require("fs").readFileSync(0, "utf8").trim();
  const rows = t.startsWith("[") ? JSON.parse(t) : t.split("\n").map((l) => JSON.parse(l));
  const out = new Set();
  for (const r of rows) for (const p of r.Publishers || []) if (p.PublishedPort) out.add(r.Service + " " + p.URL + ":" + p.PublishedPort);
  console.log([...out].sort().join(", "));')
[[ $pub == "caddy 127.0.0.1:8080" ]] || fail "published ports: '$pub', want 'caddy 127.0.0.1:8080'"
ok "published ports: $pub"

out=$(curl -fs "$BASE/id/v1/health") || fail "id health"
[[ $out == '{"ok":true}' ]] || fail "id health body: $out"
ok "id health: $out"

curl -fs -XPOST "$BASE/id/v1/otp/request" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\"}" >/dev/null || fail "otp request for $PHONE"
TOKEN=$(curl -fs -XPOST "$BASE/id/v1/otp/verify" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"code\":\"000000\"}" | json login_token) || fail "otp verify"
ok "otp verify: got login token"

# Synapse reserves all-digit localparts for guests, so the phone-number IDs that
# chama-id issues today cannot log in. Task 5 (opaque u... IDs) changes this
# step into a full sign-in that ends in an access token.
out=$(curl -s -XPOST "$BASE/_matrix/client/v3/login" -H 'content-type: application/json' \
  -d "{\"type\":\"org.matrix.login.jwt\",\"token\":\"$TOKEN\"}")
[[ $out == *'"M_INVALID_USERNAME"'*'Numeric user IDs are reserved for guest users'* ]] \
  || fail "jwt login: expected numeric-ID refusal, got: $out"
ok "jwt login: token accepted, numeric ID refused as expected until Task 5: $out"

# Until then, the worker checks use a user made by shared-secret registration on
# the internal network (the admin API is blocked at the edge).
MXUSER=check$RANDOM$RANDOM
ACCESS=$(dc exec -T -e MXUSER="$MXUSER" synapse python - <<'PY'
import hashlib, hmac, json, os, secrets, urllib.request, yaml
key = yaml.safe_load(open('/data/homeserver.yaml'))['registration_shared_secret'].encode()
url = 'http://localhost:8008/_synapse/admin/v1/register'
nonce = json.load(urllib.request.urlopen(url))['nonce']
user, pw = os.environ['MXUSER'], secrets.token_hex(16)
mac = hmac.new(key, b'\0'.join([nonce.encode(), user.encode(), pw.encode(), b'notadmin']), hashlib.sha1).hexdigest()
body = json.dumps({'nonce': nonce, 'username': user, 'password': pw, 'admin': False, 'mac': mac}).encode()
req = urllib.request.Request(url, body, {'content-type': 'application/json'})
print(json.load(urllib.request.urlopen(req))['access_token'], pw)
PY
) || fail "shared-secret registration"
read -r ACCESS MXPASS <<<"$ACCESS"
AUTH="Authorization: Bearer $ACCESS"

want="@$MXUSER:chama.test"
got=$(curl -fs -H "$AUTH" "$BASE/_matrix/client/v3/account/whoami" | json user_id) || fail "whoami"
[[ $got == "$want" ]] || fail "whoami: got $got, want $want"
ok "whoami: $got"

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

flows=$(curl -fs "$BASE/_matrix/client/v3/login") || fail "login flows"
[[ $flows != *m.login.password* ]] || fail "login flows offer password: $flows"
ok "login flows: $flows"

# The real password of a real user must still be refused.
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

echo "all checks passed"
