# OpenClaw VoiceChat (PySide6)

Python GUI client (macOS-first), with local whisper + model download.

## Run (dev)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

## Features
- Record/stop, level meter, upload
- Local whisper.cpp (if bundled)
- Download larger model button
- Log window with timestamps

## Notes
Wake-word helper placeholder lives at `python-gui/helper/voice_helper.py`.
