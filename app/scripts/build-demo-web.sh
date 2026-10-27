#!/usr/bin/env bash
# Builds the demo mode for the web so it runs fully offline: CanvasKit
# comes from the build (--no-web-resources-cdn) and the emoji font from
# web/demo/fonts instead of fonts.gstatic.com.
#   app/scripts/build-demo-web.sh   (extra flags go to flutter build)
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web -t lib/main_demo.dart --no-web-resources-cdn "$@"
# The engine fetches fallback fonts (emoji) from Google's CDN unless the
# loader names another base.
perl -0pi -e 's|_flutter\.loader\.load\(\{|_flutter.loader.load({\n  config: { fontFallbackBaseUrl: "demo/fonts/" },|' build/web/flutter_bootstrap.js
grep -q 'fontFallbackBaseUrl: "demo/fonts/"' build/web/flutter_bootstrap.js
echo "demo built in app/build/web (offline)"
