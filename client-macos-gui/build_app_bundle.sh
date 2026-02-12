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

# Build bundled whisper.cpp tiny (if missing)
WHISPER_DIR="$ROOT_DIR/dist/whisper"
mkdir -p "$WHISPER_DIR"
WHISPER_BIN="$WHISPER_DIR/whisper"
WHISPER_MODEL="$WHISPER_DIR/ggml-tiny.bin"
if [ ! -f "$WHISPER_BIN" ]; then
  WHISPER_SRC="$ROOT_DIR/dist/whisper-src"
  rm -rf "$WHISPER_SRC"
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$WHISPER_SRC"

  pushd "$WHISPER_SRC" >/dev/null
  # x86_64 (disable Metal)
  cmake -S . -B build-x86 -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=OFF -DWHISPER_METAL=OFF -DCMAKE_OSX_ARCHITECTURES=x86_64 -DGGML_CPU_ALL_VARIANTS=OFF -DGGML_NATIVE=OFF
  cmake --build build-x86 --config Release
  if [ -f build-x86/bin/whisper-cli ]; then
    cp build-x86/bin/whisper-cli "$WHISPER_DIR/whisper-x86_64"
  elif [ -f build-x86/bin/main ]; then
    cp build-x86/bin/main "$WHISPER_DIR/whisper-x86_64"
  elif [ -f build-x86/main ]; then
    cp build-x86/main "$WHISPER_DIR/whisper-x86_64"
  else
    echo "whisper binary not found (x86_64)" >&2
    exit 1
  fi

  # arm64
  cmake -S . -B build-arm -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=OFF -DWHISPER_METAL=OFF -DCMAKE_OSX_ARCHITECTURES=arm64 -DGGML_CPU_ALL_VARIANTS=OFF -DGGML_NATIVE=OFF
  cmake --build build-arm --config Release
  if [ -f build-arm/bin/whisper-cli ]; then
    cp build-arm/bin/whisper-cli "$WHISPER_DIR/whisper-arm64"
  elif [ -f build-arm/bin/main ]; then
    cp build-arm/bin/main "$WHISPER_DIR/whisper-arm64"
  elif [ -f build-arm/main ]; then
    cp build-arm/main "$WHISPER_DIR/whisper-arm64"
  else
    echo "whisper binary not found (arm64)" >&2
    exit 1
  fi
  popd >/dev/null

  /usr/bin/lipo -create "$WHISPER_DIR/whisper-x86_64" "$WHISPER_DIR/whisper-arm64" -output "$WHISPER_BIN"
  chmod +x "$WHISPER_BIN"
fi
if [ ! -f "$WHISPER_MODEL" ]; then
  curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin" -o "$WHISPER_MODEL"
fi

pushd "$GUI_DIR" >/dev/null
# Build universal binary (intel + apple silicon)
swift build -c release --arch x86_64 --arch arm64
popd >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
# Combine binaries (Swift may emit a universal binary directly)
UNIVERSAL_BIN="$MACOS_DIR/$BIN_NAME"
APPLE_UNIVERSAL="$GUI_DIR/.build/apple/Products/Release/$BIN_NAME"
ARM_BIN="$GUI_DIR/.build/arm64-apple-macosx/release/$BIN_NAME"
X86_BIN="$GUI_DIR/.build/x86_64-apple-macosx/release/$BIN_NAME"

if [ -f "$APPLE_UNIVERSAL" ]; then
  cp "$APPLE_UNIVERSAL" "$UNIVERSAL_BIN"
elif [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
  /usr/bin/lipo -create "$ARM_BIN" "$X86_BIN" -output "$UNIVERSAL_BIN"
else
  echo "Universal binary not found" >&2
  exit 1
fi

# Bundle whisper assets
mkdir -p "$RES_DIR/whisper"
cp "$WHISPER_BIN" "$RES_DIR/whisper/whisper"
cp "$WHISPER_MODEL" "$RES_DIR/whisper/ggml-tiny.bin"
chmod +x "$RES_DIR/whisper/whisper"

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
  <key>NSMicrophoneUsageDescription</key>
  <string>OpenClaw VoiceChat needs microphone access to record and upload your voice clips.</string>
</dict>
</plist>
EOF

echo "Built: $APP_DIR"
