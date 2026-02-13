import os
import uuid
import shutil
from pathlib import Path
from fastapi import FastAPI, UploadFile, File, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from dotenv import load_dotenv
import subprocess

load_dotenv()

OPENCLAW_TOKEN = os.getenv("OPENCLAW_TOKEN", "")
WORKSPACE_DIR = Path(os.getenv("WORKSPACE_DIR", "/home/kavan/.openclaw/workspace")).resolve()
INBOUND_DIR = Path(os.getenv("INBOUND_DIR", "../inbound")).resolve()
DELETE_ON_SUCCESS = os.getenv("DELETE_ON_SUCCESS", "true").lower() == "true"
TARGET_CHANNEL = os.getenv("TARGET_CHANNEL", "")  # e.g., channel:1469340639987499182

app = FastAPI()

class TextPayload(BaseModel):
    text: str


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/ingest")
def ingest(
    audio: UploadFile = File(...),
    x_openclaw_token: str = Header(default="")
):
    if not OPENCLAW_TOKEN or x_openclaw_token != OPENCLAW_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")

    INBOUND_DIR.mkdir(parents=True, exist_ok=True)
    suffix = Path(audio.filename).suffix or ".wav"
    file_id = uuid.uuid4().hex
    inbound_path = INBOUND_DIR / f"{file_id}{suffix}"

    with inbound_path.open("wb") as f:
        shutil.copyfileobj(audio.file, f)

    # Transcribe locally (fast whisper) and post directly to Discord channel if configured.
    try:
        rel_path = os.path.relpath(inbound_path, WORKSPACE_DIR)
        media_ref = f"MEDIA:./{rel_path}" if not rel_path.startswith(".") else f"MEDIA:{rel_path}"

        transcript = ""
        try:
            transcript = subprocess.check_output(
                ["/home/kavan/.openclaw/venv/whisper/bin/python", "-u",
                 "/home/kavan/.openclaw/bin/transcribe_faster_whisper.py", str(inbound_path)],
                text=True,
                timeout=60
            ).strip()
        except Exception:
            transcript = ""

        if transcript:
            body = f"Voice input: {transcript}\n{media_ref}\nSource: openclaw-voicechat"
            if TARGET_CHANNEL:
                subprocess.run(
                    ["openclaw", "message", "send", "--channel", "discord", "--target", TARGET_CHANNEL, "--message", body],
                    capture_output=True,
                    text=True,
                    check=True,
                )
            else:
                subprocess.run(
                    ["openclaw", "system", "event", "--mode", "now", "--text", body],
                    capture_output=True,
                    text=True,
                    check=True,
                )
        else:
            print('BLANK_AUDIO: transcript empty, not sending')
        else:
            subprocess.run(
                ["openclaw", "system", "event", "--mode", "now", "--text", body],
                capture_output=True,
                text=True,
                check=True,
            )
    except Exception as e:
        return JSONResponse(status_code=502, content={"error": "Gateway enqueue failed", "detail": str(e)})

    if DELETE_ON_SUCCESS:
        try:
            inbound_path.unlink(missing_ok=True)
        except Exception:
            pass

    return {"ok": True, "file_id": file_id}


@app.post("/ingest_text")
def ingest_text(payload: TextPayload, x_openclaw_token: str = Header(default="")):
    if not OPENCLAW_TOKEN or x_openclaw_token != OPENCLAW_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")

    text = (payload.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Missing text")

    try:
        body = f"Voice input: {text}\nSource: openclaw-voicechat"
        # Send to Discord channel directly if TARGET_CHANNEL is set, else system event
        if TARGET_CHANNEL:
            subprocess.run(
                ["openclaw", "message", "send", "--channel", "discord", "--target", TARGET_CHANNEL, "--message", body],
                capture_output=True,
                text=True,
                check=True,
            )
        else:
            subprocess.run(
                ["openclaw", "system", "event", "--mode", "now", "--text", body],
                capture_output=True,
                text=True,
                check=True,
            )
    except Exception as e:
        return JSONResponse(status_code=502, content={"error": "Gateway enqueue failed", "detail": str(e)})

    return {"ok": True}
