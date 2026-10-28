#!/usr/bin/env bash
# Design-review screenshots against the local stack (`make up`): the app signs
# in a fresh number, chats with tools/peer and makes a group
# (integration_test/screenshots_test.dart). Saves <platform>-<size>-<theme>-<screen>.png.
#   scripts/screenshots.sh [out dir] [web-phone] [web-wide] [android]
# Default: build/screenshots, all three targets, each in light and dark.
set -euo pipefail
OUT=${1:-build/screenshots}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
shift $(($# < 1 ? 0 : 1))
TARGETS=${*:-web-phone web-wide android}
cd "$(dirname "$0")/.."
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export PATH="$SDK/platform-tools:$PATH"

# Stop the emulator afterwards if drive.sh had to start it.
EMU_RUNNING=$(adb devices 2>/dev/null | grep -c '^emulator-' || true)
stop_emulator() { [ "$EMU_RUNNING" != 0 ] || adb emu kill >/dev/null 2>&1 || true; }
trap stop_emulator EXIT

export SCREENSHOT_DIR=$OUT TEST_DRIVER=test_driver/screenshots.dart PEER_NAME="Bruno Lima"
for target in $TARGETS; do
  for theme in light dark; do
    case $target in
      web-phone) T=chrome WEB_SIZE=412x915@2 NAME=web-phone ;;
      # Headless Chrome keeps 143 px of the window for its UI: 1440x900 viewport.
      web-wide) T=chrome WEB_SIZE=1440x1043 NAME=web-wide ;;
      android) T=android WEB_SIZE= NAME=android-phone ;;
      *) echo "unknown target $target"; exit 2 ;;
    esac
    echo "== $NAME-$theme"
    WEB_SIZE=$WEB_SIZE ./scripts/e2e.sh "$T" integration_test/screenshots_test.dart --dart-define=ALO_SHOT="$NAME-$theme"
  done
done
ls "$OUT"
