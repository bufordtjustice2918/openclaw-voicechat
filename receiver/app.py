import os
import uuid
import shutil
from pathlib import Path
from fastapi import FastAPI, UploadFile, File, Header, HTTPException
from fastapi.responses import JSONResponse
from dotenv import load_dotenv
import subprocess

load_dotenv()

OPENCLAW_TOKEN = os.getenv("OPENCLAW_TOKEN", "")
WORKSPACE_DIR = Path(os.getenv("WORKSPACE_DIR", "/home/kavan/.openclaw/workspace")).resolve()
INBOUND_DIR = Path(os.getenv("INBOUND_DIR", "../inbound")).resolve()
DELETE_ON_SUCCESS = os.getenv("DELETE_ON_SUCCESS", "true").lower() == "true"

app = FastAPI()


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

    # Enqueue a system event on the main session via the OpenClaw CLI.
    # Use a safe relative MEDIA path (relative to workspace) to avoid absolute path blocking.
    try:
        rel_path = os.path.relpath(inbound_path, WORKSPACE_DIR)
        media_ref = f"MEDIA:./{rel_path}" if not rel_path.startswith(".") else f"MEDIA:{rel_path}"
        text = f"{media_ref}\nSource: openclaw-voicechat"

        result = subprocess.run(
            ["openclaw", "system", "event", "--mode", "now", "--text", text],
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
