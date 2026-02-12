#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi
if ! command -v pkgbuild >/dev/null 2>&1; then
  echo "pkgbuild not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

"$ROOT_DIR/client-macos/build_pkg.sh"

echo "\nDone. Installer at: $ROOT_DIR/dist/OpenClawVoiceChat-0.1.0.pkg"
