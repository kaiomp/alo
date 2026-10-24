#!/usr/bin/env bash
# Builds vodozemac (the Matrix encryption library) to WebAssembly for the web
# app. Output: web/pkg/vodozemac_bindings_dart.js + _bg.wasm, loaded by
# flutter_vodozemac's init() from ./pkg/. Native builds do not need this.
# Same steps as FluffyChat scripts/prepare-web.sh. Needs rustup.
set -euo pipefail
cd "$(dirname "$0")/.."

VODOZEMAC=0.9.0   # must equal flutter_vodozemac in pubspec.yaml
FRB=2.13.0        # must equal flutter_rust_bridge in pubspec.lock
WASM_PACK=0.15.0
WASM_BINDGEN=0.2.100  # must equal wasm-bindgen in dart-vodozemac rust/Cargo.lock
OUT=web/pkg

if [ -f "$OUT/vodozemac_bindings_dart_bg.wasm" ] && [ "$(cat "$OUT/VERSION" 2>/dev/null)" = "$VODOZEMAC" ]; then
  echo "vodozemac $VODOZEMAC for web is already built"
  exit 0
fi

rustup toolchain install nightly --profile minimal --component rust-src --target wasm32-unknown-unknown
wasm-pack --version 2>/dev/null | grep -q "$WASM_PACK" || cargo install wasm-pack --version "$WASM_PACK" --locked
# Install wasm-bindgen ourselves: if wasm-pack does it, the threaded-wasm
# RUSTFLAGS leak into the host build and linking fails.
wasm-bindgen --version 2>/dev/null | grep -q "$WASM_BINDGEN" ||
  cargo install wasm-bindgen-cli --version "$WASM_BINDGEN" --locked
flutter_rust_bridge_codegen --version 2>/dev/null | grep -q "$FRB" ||
  cargo install flutter_rust_bridge_codegen --version "$FRB" --locked

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --depth 1 -b "$VODOZEMAC" https://github.com/famedly/dart-vodozemac.git "$TMP/dv"
(cd "$TMP/dv" && flutter_rust_bridge_codegen build-web --dart-root dart --rust-root "$TMP/dv/rust" --release)

mkdir -p "$OUT"
cp "$TMP"/dv/dart/web/pkg/vodozemac_bindings_dart* "$OUT/"
echo "$VODOZEMAC" > "$OUT/VERSION"
ls -la "$OUT"
