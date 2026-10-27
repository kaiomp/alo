#!/bin/sh
# Renders the static share images from og/modelo.html with headless Chrome, then saves JPEGs.
# Usage (from site/): sh og/gerar.sh      Needs Google Chrome and macOS sips.
set -e
cd "$(dirname "$0")/.."
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TMP="$(mktemp -d)"
for pagina in ${PAGINAS:-inicio como-funciona privacidade ajudar}; do
  for formato in largo quadrado; do
    if [ "$formato" = largo ]; then tam=1200,630; sufixo=""; else tam=600,600; sufixo="-quadrado"; fi
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
      --force-device-scale-factor=1 --window-size="$tam" --virtual-time-budget=3000 \
      --screenshot="$TMP/$pagina$sufixo.png" "file://$PWD/og/modelo.html?pagina=$pagina&formato=$formato" 2>/dev/null
    sips -s format jpeg -s formatOptions 86 "$TMP/$pagina$sufixo.png" --out "public/img/og-$pagina$sufixo.jpg" >/dev/null
    ls -l "public/img/og-$pagina$sufixo.jpg" | awk '{print $5, $9}'
  done
done
rm -rf "$TMP"
