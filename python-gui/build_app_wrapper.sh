#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT_DIR/../dist"
APP_NAME="OpenClaw VoiceChat"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
RUN_CMD="$ROOT_DIR/run.command"

mkdir -p "$DIST_DIR"

/usr/bin/osacompile -o "$APP_BUNDLE" <<EOF
on run
  do shell script "${RUN_CMD}"
end run
EOF

echo "Built: $APP_BUNDLE"
