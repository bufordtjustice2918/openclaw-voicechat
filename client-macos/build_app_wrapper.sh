#!/usr/bin/env bash
set -euo pipefail

APP_NAME="OpenClaw VoiceChat"
APP_BUNDLE="${APP_NAME}.app"
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DIST_DIR="$ROOT_DIR/dist"
SCRIPT_PATH="$DIST_DIR/run-openclaw-voicechat.sh"

mkdir -p "$DIST_DIR"

cat > "$SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash
# Launches openclaw-voicechat with env vars from ~/.openclaw-voicechat.env if present
ENV_FILE="$HOME/.openclaw-voicechat.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
exec /usr/local/bin/openclaw-voicechat
EOF
chmod +x "$SCRIPT_PATH"

# Build a tiny app wrapper that launches the script
/usr/bin/osacompile -o "$DIST_DIR/$APP_BUNDLE" <<EOF
on run
  do shell script "${SCRIPT_PATH}"
end run
EOF

echo "Built: $DIST_DIR/$APP_BUNDLE"
