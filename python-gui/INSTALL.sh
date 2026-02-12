#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="$ROOT_DIR/whisper"
mkdir -p "$WHISPER_DIR"

# Build whisper.cpp (macOS) and download tiny model
if [ ! -x "$WHISPER_DIR/whisper" ]; then
  echo "Building whisper.cpp..."
  SRC="$ROOT_DIR/.whisper-src"
  rm -rf "$SRC"
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$SRC"
  pushd "$SRC" >/dev/null
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=OFF -DWHISPER_METAL=OFF
  cmake --build build --config Release
  if [ -f build/bin/whisper-cli ]; then
    cp build/bin/whisper-cli "$WHISPER_DIR/whisper"
  elif [ -f build/bin/main ]; then
    cp build/bin/main "$WHISPER_DIR/whisper"
  elif [ -f build/main ]; then
    cp build/main "$WHISPER_DIR/whisper"
  else
    echo "whisper binary not found" >&2
    exit 1
  fi
  popd >/dev/null
fi

if [ ! -f "$WHISPER_DIR/ggml-tiny.bin" ]; then
  echo "Downloading ggml-tiny.bin..."
  curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin" -o "$WHISPER_DIR/ggml-tiny.bin"
fi

echo "Done."
