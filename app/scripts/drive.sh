#!/usr/bin/env bash
# Runs one integration test file on a target, with the browser or emulator
# set up for you. Extra arguments go to flutter (e.g. --dart-define=...).
# TEST_DRIVER=<file> runs through that flutter drive driver on both targets;
# WEB_SIZE=<w>x<h>[@<pixel ratio>] sets the browser size (default 1280x900).
# CHAMA_AVD=<name> picks the emulator (default: the first AVD). CHROME=<path>
# points at the Chrome binary (default: the macOS app path).
#   scripts/drive.sh chrome  integration_test/boot_test.dart
#   scripts/drive.sh android integration_test/boot_test.dart
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET=${1:?usage: scripts/drive.sh chrome|android <test file> [flutter args]}
TEST=${2:?test file}
shift 2
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

case $TARGET in
  chrome)
    CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
    [ -x "$CHROME" ] || { echo "Chrome not found at $CHROME. Set CHROME=<path to the chrome binary>."; exit 1; }
    ./scripts/build-vodozemac-web.sh
    CHROME_VERSION=$("$CHROME" --version | awk '{print $3}')
    DRIVER=$(npx --yes @puppeteer/browsers@3.2.6 install "chromedriver@$CHROME_VERSION" \
      --path "$HOME/.cache/chama-chromedriver" | awk '{print $2}')
    "$DRIVER" --port=4444 >/dev/null 2>&1 &
    PIDS+=($!)
    sleep 1
    # web-server + chromedriver: chromedriver starts headless Chrome itself
    # (`-d chrome` waits forever for its own browser when run from a script).
    # Synthetic taps are no user gesture: let voice notes play without one.
    flutter drive --driver="${TEST_DRIVER:-test_driver/integration_test.dart}" --target="$TEST" \
      -d web-server --browser-name=chrome --browser-dimension="${WEB_SIZE:-1280x900}" \
      --web-browser-flag=--autoplay-policy=no-user-gesture-required "$@"
    ;;
  android)
    if ! adb devices | grep -q '^emulator-'; then
      AVD=${CHAMA_AVD:-$(emulator -list-avds | head -1)}
      emulator -list-avds | grep -qxF "$AVD" ||
        { echo "No AVD '${AVD}'. Create one in Android Studio or set CHAMA_AVD (emulator -list-avds)."; exit 1; }
      EMU_LOG=$(mktemp)
      emulator -avd "$AVD" -no-snapshot -no-audio -no-boot-anim >"$EMU_LOG" 2>&1 &
      EMU=$!
      # Boot in at most 5 minutes; stop at once if the emulator exits.
      for _ in $(seq 150); do
        kill -0 "$EMU" 2>/dev/null || { echo "Emulator exited:"; tail -20 "$EMU_LOG"; exit 1; }
        [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
        sleep 2
      done
      [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] ||
        { echo "Emulator did not boot in 5 minutes:"; tail -20 "$EMU_LOG"; exit 1; }
    fi
    DEVICE=$(adb devices | awk '/^emulator-/{print $1; exit}')
    adb -s "$DEVICE" uninstall chat.chama.app >/dev/null 2>&1 || true # fresh app data every run
    if [ -n "${TEST_DRIVER:-}" ]; then
      flutter drive --driver="$TEST_DRIVER" --target="$TEST" -d "$DEVICE" "$@"
    else
      flutter test "$TEST" -d "$DEVICE" "$@"
    fi
    ;;
  *) echo "unknown target $TARGET"; exit 2 ;;
esac
