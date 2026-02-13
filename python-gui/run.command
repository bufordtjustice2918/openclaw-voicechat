#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$ROOT_DIR/.venv"

if [ ! -d "$VENV" ]; then
  python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"
python3 -m pip install --upgrade pip
python3 -m pip install -r "$ROOT_DIR/requirements.txt"
# ensure Vosk model
MODEL_DIR="$HOME/.openclaw-voicechat"
if [ ! -d "$MODEL_DIR/vosk-model" ]; then
  mkdir -p "$MODEL_DIR"
  curl -L -o "$MODEL_DIR/vosk.zip" https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip
  unzip -q "$MODEL_DIR/vosk.zip" -d "$MODEL_DIR"
  rm -f "$MODEL_DIR/vosk.zip"
  mv "$MODEL_DIR/vosk-model-small-en-us-0.15" "$MODEL_DIR/vosk-model"
fi
python3 "$ROOT_DIR/app.py"
