#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
GUI_DIR="$ROOT_DIR/client-macos-gui"
BUILD_DIR="$GUI_DIR/.build/release"
BIN_NAME="openclaw-voicechat-gui"
APP_NAME="OpenClaw VoiceChat"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
PLIST="$APP_DIR/Contents/Info.plist"

mkdir -p "$ROOT_DIR/dist"

pushd "$GUI_DIR" >/dev/null
swift build -c release
popd >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BUILD_DIR/$BIN_NAME" "$MACOS_DIR/$BIN_NAME"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>ai.openclaw.voicechat.gui</string>
  <key>CFBundleVersion</key>
  <string>0.2.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleExecutable</key>
  <string>${BIN_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
</dict>
</plist>
EOF

echo "Built: $APP_DIR"
