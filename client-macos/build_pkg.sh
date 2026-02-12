#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
CLIENT_DIR="$ROOT_DIR/client-macos"
BUILD_DIR="$CLIENT_DIR/.build/release"
BIN_NAME="openclaw-voicechat"
VERSION="0.1.0"
IDENTIFIER="ai.openclaw.voicechat"
PKG_OUT="$ROOT_DIR/dist/OpenClawVoiceChat-${VERSION}.pkg"
STAGE_DIR="$ROOT_DIR/dist/pkgroot"

mkdir -p "$ROOT_DIR/dist"
rm -rf "$STAGE_DIR"

pushd "$CLIENT_DIR" >/dev/null
swift build -c release
popd >/dev/null

mkdir -p "$STAGE_DIR/usr/local/bin"
cp "$BUILD_DIR/$BIN_NAME" "$STAGE_DIR/usr/local/bin/$BIN_NAME"

# Build a simple unsigned installer package
pkgbuild \
  --root "$STAGE_DIR" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG_OUT"

echo "Built: $PKG_OUT"
