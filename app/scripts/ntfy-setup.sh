#!/usr/bin/env bash
# Installs ntfy, the UnifiedPush distributor, on the emulator and points it at
# the dev stack's ntfy (http://10.0.2.2:8081, server/compose.yaml). Run once per
# emulator; running it again changes nothing.
# The device: the argument, else ANDROID_SERIAL (as in drive.sh), else the
# first emulator.
#   scripts/ntfy-setup.sh [device]
set -euo pipefail
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export PATH="$SDK/platform-tools:$PATH"
DEVICE=${1:-${ANDROID_SERIAL:-$(adb devices | awk '/^emulator-/{print $1; exit}')}}
[ -n "$DEVICE" ] || { echo "No emulator running"; exit 1; }
SERVER=${NTFY_SERVER:-http://10.0.2.2:8081}
# ntfy 1.25.2, F-Droid build (versionCode 63).
APK=$HOME/.cache/alo-ntfy/io.heckel.ntfy_63.apk
SHA256=b4baa6f668bd57ad5df3b4e0e769165dcf25c5ee19fdb04f78077ee819616f2a
a() { adb -s "$DEVICE" "$@"; }

if [ ! -f "$APK" ]; then
  mkdir -p "$(dirname "$APK")"
  curl -fsSLo "$APK.part" https://f-droid.org/repo/io.heckel.ntfy_63.apk
  echo "$SHA256  $APK.part" | shasum -a 256 -c - >/dev/null
  mv "$APK.part" "$APK"
fi
a shell pm path io.heckel.ntfy >/dev/null 2>&1 || a install "$APK" >/dev/null
a shell pm grant io.heckel.ntfy android.permission.POST_NOTIFICATIONS
# What ntfy's "battery optimization" banner asks for. Without it Android does
# not let ntfy start its listening service when a new app registers.
a shell dumpsys deviceidle whitelist +io.heckel.ntfy >/dev/null

screen() { a exec-out uiautomator dump /dev/tty 2>/dev/null; }
# Taps the first view whose resource id (without package), text or
# description is $1; retries while the screen loads.
tap() {
  for _ in $(seq 15); do
    xy=$(screen | node -e '
      const want = process.argv[1];
      for (const [n] of require("fs").readFileSync(0, "utf8").matchAll(/<node [^>]*>/g)) {
        const get = (k) => (n.match(new RegExp(` ${k}="([^"]*)"`)) || [])[1] || "";
        if (![get("resource-id").split("/").pop(), get("text"), get("content-desc")].includes(want)) continue;
        const [x1, y1, x2, y2] = get("bounds").match(/\d+/g).map(Number);
        console.log((x1 + x2) >> 1, (y1 + y2) >> 1);
        break;
      }' "$1")
    if [ -n "$xy" ]; then a shell input tap $xy; sleep 1; return; fi
    sleep 1
  done
  echo "ntfy-setup: \"$1\" not on screen" >&2
  exit 1
}

a shell am force-stop io.heckel.ntfy
a shell am start -W -n io.heckel.ntfy/.ui.MainActivity >/dev/null
tap 'More options'
tap 'Settings'
if screen | grep -q "text=\"$SERVER\""; then
  echo "ntfy already uses $SERVER"
else
  tap 'Default server'
  tap default_server_dialog_url
  a shell input keyevent KEYCODE_MOVE_END $(printf 'KEYCODE_DEL %.0s' $(seq 60))
  a shell input text "$SERVER"
  tap default_server_dialog_action_save
  screen | grep -q "text=\"$SERVER\"" || { echo "ntfy-setup: default server not saved" >&2; exit 1; }
  echo "ntfy now uses $SERVER"
fi
a shell input keyevent KEYCODE_HOME
