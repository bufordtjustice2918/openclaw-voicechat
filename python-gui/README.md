# OpenClaw VoiceChat (PySide6)

Python GUI client (macOS-first), with local whisper + model download.

## Run (one‑click)
Double‑click `run.command` (creates venv + installs deps + runs).

## Run (dev)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

## macOS App Wrapper
```bash
./build_app_wrapper.sh
# Outputs: ../dist/OpenClaw VoiceChat.app
```

## Features
- Record/stop, level meter, upload
- Local whisper.cpp (if bundled)
- Download larger model button
- Log window with timestamps

## Notes
Wake-word helper placeholder lives at `python-gui/helper/voice_helper.py`.
