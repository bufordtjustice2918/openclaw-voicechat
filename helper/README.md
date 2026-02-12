# Voice helper (Vosk + VAD + Whisper)

Install deps:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Download a Vosk model (small) and place at:
`~/.openclaw-voicechat/vosk-model`

Run:
```bash
RECEIVER_URL="http://127.0.0.1:8787/ingest_text" \
OPENCLAW_TOKEN="..." \
WAKE_WORD="buford" \
SILENCE_MS=900 \
python3 voice_helper.py
```

Requires `whisper` CLI on PATH.
