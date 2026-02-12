# macOS Push‑to‑Talk Client

A small Swift command‑line app that records while a hotkey is held and uploads the audio to the local receiver.

## Build (dev)
```bash
cd openclaw-voicechat/client-macos
swift build -c release
```

## Installer (pkg)
```bash
cd openclaw-voicechat/client-macos
./build_pkg.sh
# Outputs: ../dist/OpenClawVoiceChat-0.1.0.pkg
```

## Run
```bash
export RECEIVER_URL="http://127.0.0.1:8787/ingest"
export OPENCLAW_TOKEN="<token>"
# Optional: key code (default 61 = Right Option)
export PTT_KEY_CODE=61

./.build/release/openclaw-voicechat
```

## App wrapper (shows in Applications)
```bash
cd openclaw-voicechat/client-macos
./build_app_wrapper.sh
# Outputs: ../dist/OpenClaw VoiceChat.app
```

Tip: create `~/.openclaw-voicechat.env` with:
```
export RECEIVER_URL="http://127.0.0.1:8787/ingest"
export OPENCLAW_TOKEN="..."
export PTT_KEY_CODE=61
```
The app wrapper will source it automatically.

## Permissions
- **Microphone** access will be requested on first run.
- **Accessibility** permissions are required for global hotkeys.
  - System Settings → Privacy & Security → Accessibility → enable the terminal/IDE you run from.

## Notes
- Recording saves to a temporary `.caf` file, uploads it, then deletes it locally.
- Adjust `PTT_KEY_CODE` for a different hotkey.
