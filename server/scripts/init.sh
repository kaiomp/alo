#!/usr/bin/env bash
# Prepares server/data. Runs on every `make up`:
# - secrets in server/data/.env are generated once (missing ones are added),
# - Synapse config is re-rendered from the templates every time,
# - the signing key is generated once.
set -euo pipefail
cd "$(dirname "$0")/../.."

SYNAPSE_IMAGE=ghcr.io/element-hq/synapse:v1.163.2
DATA=server/data
ENV=$DATA/.env
SECRETS="POSTGRES_PASSWORD JWT_SECRET OTP_PEPPER REGISTRATION_SHARED_SECRET MACAROON_SECRET FORM_SECRET WORKER_REPLICATION_SECRET"

mkdir -p "$DATA"/{synapse/workers,media,chama-id}
# Containers write here as their own users (Synapse uid 991, chama-id user node), and a host user
# without root cannot chown to them, so these dirs are world-writable. The config files below are
# world-readable for the same reason. $DATA itself is 700, so other host users cannot reach any of it.
# Dev only. Files Synapse creates are owned by 991; `make reset` removes them through a container.
chmod 700 "$DATA"
chmod 777 "$DATA/synapse" "$DATA/media" "$DATA/chama-id"

umask 077
touch "$ENV"
chmod 600 "$ENV"
has() { grep -q "^$1=" "$ENV"; }
has SERVER_NAME || echo "SERVER_NAME=chama.test" >> "$ENV"
has PUBLIC_BASEURL || echo "PUBLIC_BASEURL=http://localhost:8080" >> "$ENV"
for v in $SECRETS; do
  has "$v" || echo "$v=$(openssl rand -hex 32)" >> "$ENV"
done

# Render ${VAR} tokens from .env. Fails on any unknown or empty token.
node -e '
  const fs = require("fs");
  const [envFile, src, dst] = process.argv.slice(1);
  const env = Object.fromEntries(fs.readFileSync(envFile, "utf8").split("\n")
    .filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
  const out = fs.readFileSync(src, "utf8").replace(/\$\{(\w+)\}/g, (_, k) => {
    if (!env[k]) throw new Error("unknown or empty variable " + k);
    return env[k];
  });
  fs.writeFileSync(dst, out);
' "$ENV" server/synapse/homeserver.yaml.tmpl "$DATA/synapse/homeserver.yaml"
cp server/synapse/log.yaml "$DATA/synapse/"
cp server/synapse/workers/*.yaml "$DATA/synapse/workers/"
chmod 755 "$DATA/synapse/workers"
chmod 644 "$DATA/synapse/homeserver.yaml" "$DATA/synapse/log.yaml" "$DATA"/synapse/workers/*.yaml

if [[ ! -f $DATA/synapse/signing.key ]]; then
  docker run --rm --user 991:991 -v "$PWD/$DATA/synapse:/data" --entrypoint python "$SYNAPSE_IMAGE" \
    -m synapse.app.homeserver --config-path /data/homeserver.yaml --generate-keys
fi

# Containers read config at start. A new CONFIG_REV makes `docker compose up`
# recreate them, so template edits reach the stack on the next `make up`.
rev=$(cat "$DATA/synapse/homeserver.yaml" "$DATA/synapse/log.yaml" "$DATA"/synapse/workers/*.yaml \
  server/caddy/Caddyfile | openssl sha256 | awk '{print $NF}')
grep -v '^CONFIG_REV=' "$ENV" > "$ENV.tmp" || true
echo "CONFIG_REV=$rev" >> "$ENV.tmp"
mv "$ENV.tmp" "$ENV"
echo "server/data ready (config rev ${rev:0:12})"
