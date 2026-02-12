# macOS GUI Client

A simple full‑window app for recording and uploading voice clips.

## Build app bundle
```bash
cd openclaw-voicechat/client-macos-gui
./build_app_bundle.sh
# Outputs: ../dist/OpenClaw VoiceChat.app
```

## Run settings
- Receiver URL and Token are editable in the UI.
- Click **Save Settings** to persist to `~/.openclaw-voicechat.env`.
- Click **Record** to start, **Stop & Send** to send.
- **Test Mic** (records 2s + plays back, **no upload**).
- **Recording level** meter updates while recording.
- **Input device** picker sets the system default input device.
- **Fast mode (local whisper)** sends transcript instantly.
- **Upload audio in background** is optional.
- **Always‑listen** uses a local Python helper (Vosk + VAD + Whisper) for wake‑word.

Mic permission will be requested on first run.
