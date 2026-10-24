#!/usr/bin/env bash
# End-to-end test against the local stack (`make up`): the app signs in a
# fresh number and chats with the test peer (tools/peer).
#   scripts/e2e.sh chrome  [test file]   headless Chrome, wide two-pane layout
#   scripts/e2e.sh android [test file]   emulator, phone layout
# Default test file: integration_test/app_test.dart.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:?usage: scripts/e2e.sh chrome|android [test file]}
TEST=${2:-integration_test/app_test.dart}
BASE=http://localhost:8080

curl -fs "$BASE/id/v1/health" >/dev/null || { echo "Stack is down. Run: make up"; exit 1; }

rand_phone() { printf '55119%04d%04d' $((RANDOM % 10000)) $((RANDOM % 10000)); }
APP_PHONE=$(rand_phone)
PEER_PHONE=$(rand_phone)
PEER_LOG=$(mktemp)
(cd ../tools/peer && PEER_PHONE=$PEER_PHONE CHAMA_BASE_URL=$BASE exec node peer.ts) >"$PEER_LOG" 2>&1 &
PEER=$!
trap 'kill $PEER 2>/dev/null || true' EXIT
for _ in $(seq 60); do grep -q 'peer ready' "$PEER_LOG" && break; sleep 1; done
grep -q 'peer ready' "$PEER_LOG" || { echo "Peer did not start:"; tail -30 "$PEER_LOG"; exit 1; }
echo "app +$APP_PHONE  peer +$PEER_PHONE  peer log: $PEER_LOG"

./scripts/drive.sh "$TARGET" "$TEST" \
  --dart-define=CHAMA_TEST_PHONE="$APP_PHONE" --dart-define=CHAMA_PEER_PHONE="$PEER_PHONE"
