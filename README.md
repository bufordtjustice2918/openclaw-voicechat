# openclaw-voicechat

Local voice chat bridge for OpenClaw.

## What it does
- **Receiver**: local HTTP endpoint on `localhost` that accepts audio uploads with a token header, saves to `inbound/`, then enqueues a **system event** (via `openclaw system event`) pointing at the audio file and deletes it after processing.
- **macOS client**: push‑to‑talk command‑line app that records while the hotkey is held, then uploads to the receiver.

> Security note: this is intended to run **locally**. Do not expose the receiver publicly.

---

## Repo structure
```
openclaw-voicechat/
  receiver/                 # Local HTTP receiver (FastAPI)
    app.py
    requirements.txt
    config.example.env
  client-macos/             # macOS push‑to‑talk client (Swift)
    Package.swift
    Sources/OpenClawVoiceChat/main.swift
    README.md
    build_pkg.sh
  inbound/                  # Incoming audio (runtime)
  .gitignore
```

---

## Receiver (local HTTP)

### Setup
```bash
cd openclaw-voicechat/receiver
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp config.example.env .env
# edit .env (set OPENCLAW_TOKEN; WORKSPACE_DIR if different)
```

### Run
```bash
source .venv/bin/activate
uvicorn app:app --host 127.0.0.1 --port 8787
```

### Example curl
```bash
curl -X POST http://127.0.0.1:8787/ingest \
  -H "X-OpenClaw-Token: <token>" \
  -F "audio=@/path/to/audio.wav"
```

---

## macOS Push‑to‑Talk Client
**Easy installer build (macOS):**
```bash
./build_macos_pkg.sh
# Outputs: ./dist/OpenClawVoiceChat-0.1.0.pkg
```
Then double‑click the `.pkg` to install.

See `client-macos/README.md` for dev run details.

---

## Cross‑platform future notes
- The receiver is OS‑agnostic and can run on Linux/Windows.
- For Windows, implement a similar push‑to‑talk client using WASAPI + low‑level keyboard hooks.
- For Linux, implement a small Rust or Python client (pyaudio + evdev) to capture hotkeys and mic audio.
- Consider **TLS + auth** if the receiver must be exposed beyond localhost.
- Consider **streaming** (WebSocket) to reduce latency, with chunked enqueue in Gateway.
