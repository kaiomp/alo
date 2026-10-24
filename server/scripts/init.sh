#!/usr/bin/env bash
# Creates server/data: secrets in .env, rendered Synapse config, signing key.
# Safe to re-run: does nothing once server/data/.env exists.
set -euo pipefail
cd "$(dirname "$0")/../.."

SYNAPSE_IMAGE=ghcr.io/element-hq/synapse:v1.163.2
DATA=server/data

if [[ -f $DATA/.env ]]; then
  echo "$DATA/.env exists, nothing to do"
  exit 0
fi

mkdir -p "$DATA"/{synapse/workers,media,chama-id}
# chama-id runs as user node; dev only.
chmod 777 "$DATA/chama-id"

export SERVER_NAME=chama.test
export PUBLIC_BASEURL=http://localhost:8080
for v in POSTGRES_PASSWORD JWT_SECRET OTP_PEPPER REGISTRATION_SHARED_SECRET MACAROON_SECRET FORM_SECRET; do
  export "$v=$(openssl rand -hex 32)"
done

# Render ${VAR} tokens from a fixed list. Fails on any unknown token.
node -e '
  const fs = require("fs");
  const allowed = ["SERVER_NAME", "PUBLIC_BASEURL", "POSTGRES_PASSWORD", "JWT_SECRET",
    "REGISTRATION_SHARED_SECRET", "MACAROON_SECRET", "FORM_SECRET"];
  const out = fs.readFileSync(process.argv[1], "utf8").replace(/\$\{(\w+)\}/g, (_, k) => {
    if (!allowed.includes(k) || !process.env[k]) throw new Error("unknown or empty variable " + k);
    return process.env[k];
  });
  fs.writeFileSync(process.argv[2], out, { mode: 0o600 });
' server/synapse/homeserver.yaml.tmpl "$DATA/synapse/homeserver.yaml"

cp server/synapse/log.yaml "$DATA/synapse/"
cp server/synapse/workers/*.yaml "$DATA/synapse/workers/"

docker run --rm -v "$PWD/$DATA/synapse:/data" --entrypoint python "$SYNAPSE_IMAGE" \
  -m synapse.app.homeserver --config-path /data/homeserver.yaml --generate-keys

# Written last, so a failed run is retried instead of skipped.
umask 077
{
  echo "SERVER_NAME=$SERVER_NAME"
  echo "PUBLIC_BASEURL=$PUBLIC_BASEURL"
  for v in POSTGRES_PASSWORD JWT_SECRET OTP_PEPPER REGISTRATION_SHARED_SECRET MACAROON_SECRET FORM_SECRET; do
    echo "$v=${!v}"
  done
} > "$DATA/.env"
chmod 600 "$DATA/.env"
echo "wrote $DATA/.env"
