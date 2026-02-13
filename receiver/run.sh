#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
PYTHON_BIN="$VENV_DIR/bin/python"
PIP_BIN="$VENV_DIR/bin/pip"

if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv "$VENV_DIR"
fi

"$PIP_BIN" install --upgrade pip setuptools wheel
"$PIP_BIN" install -r "$ROOT_DIR/requirements.txt"

exec "$VENV_DIR/bin/uvicorn" app:app --host 0.0.0.0 --port 8787
