#!/usr/bin/env python3
import os
import sys
import time
import json
import queue
import wave
import tempfile
import threading
import subprocess

import requests
import sounddevice as sd
import webrtcvad
from vosk import Model, KaldiRecognizer

RECEIVER_URL = os.getenv("RECEIVER_URL", "http://127.0.0.1:8787/ingest_text")
TOKEN = os.getenv("OPENCLAW_TOKEN", "")
WAKE_WORD = os.getenv("WAKE_WORD", "buford").lower()
SILENCE_MS = int(os.getenv("SILENCE_MS", "900"))
SAMPLE_RATE = int(os.getenv("SAMPLE_RATE", "16000"))
DEVICE = os.getenv("AUDIO_DEVICE", "")

MODEL_PATH = os.getenv("VOSK_MODEL_PATH", os.path.expanduser("~/.openclaw-voicechat/vosk-model"))

if not TOKEN:
    print("OPENCLAW_TOKEN missing", file=sys.stderr)
    sys.exit(1)

if not os.path.isdir(MODEL_PATH):
    print(f"Vosk model not found at {MODEL_PATH}", file=sys.stderr)
    sys.exit(2)

q = queue.Queue()


def callback(indata, frames, time_info, status):
    if status:
        print(status, file=sys.stderr)
    q.put(bytes(indata))


def send_text(text):
    text = text.strip()
    if not text:
        return
    try:
        r = requests.post(
            RECEIVER_URL,
            headers={"X-OpenClaw-Token": TOKEN, "Content-Type": "application/json"},
            data=json.dumps({"text": text}),
            timeout=10,
        )
        r.raise_for_status()
    except Exception as e:
        print(f"send_text failed: {e}", file=sys.stderr)


def run_whisper(wav_path):
    try:
        # Requires `whisper` CLI on PATH
        proc = subprocess.run(
            ["whisper", "--model", "tiny", "--language", "en", "--output_format", "txt", "--output_dir", os.path.dirname(wav_path), wav_path],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if proc.returncode != 0:
            return ""
        txt_path = wav_path + ".txt"
        if not os.path.exists(txt_path):
            return ""
        with open(txt_path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return ""


def write_wav(frames):
    fd, path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(b"".join(frames))
    return path


def main():
    print("voice_helper: starting")
    model = Model(MODEL_PATH)
    rec = KaldiRecognizer(model, SAMPLE_RATE, f'["{WAKE_WORD}"]')
    rec.SetWords(False)

    vad = webrtcvad.Vad(2)
    frame_ms = 30
    frame_bytes = int(SAMPLE_RATE * (frame_ms / 1000.0) * 2)  # 16-bit mono
    silence_frames = int(SILENCE_MS / frame_ms)

    listening = True
    recording_frames = []
    silence_count = 0
    triggered = False

    with sd.RawInputStream(samplerate=SAMPLE_RATE, blocksize=frame_bytes, dtype='int16', channels=1,
                           callback=callback, device=int(DEVICE) if DEVICE else None):
        while True:
            data = q.get()
            if listening and rec.AcceptWaveform(data):
                try:
                    res = json.loads(rec.Result())
                    if res.get("text", "").strip().lower() == WAKE_WORD:
                        print("wakeword detected")
                        triggered = True
                        listening = False
                        recording_frames = []
                        silence_count = 0
                except Exception:
                    pass

            if triggered:
                # VAD
                for i in range(0, len(data), frame_bytes):
                    frame = data[i:i+frame_bytes]
                    if len(frame) < frame_bytes:
                        continue
                    is_speech = vad.is_speech(frame, SAMPLE_RATE)
                    recording_frames.append(frame)
                    if is_speech:
                        silence_count = 0
                    else:
                        silence_count += 1
                    if silence_count >= silence_frames:
                        # stop
                        triggered = False
                        listening = True
                        print("silence detected, stopping")
                        wav_path = write_wav(recording_frames)
                        text = run_whisper(wav_path)
                        if text:
                            send_text(text)
                        try:
                            os.remove(wav_path)
                            if os.path.exists(wav_path + ".txt"):
                                os.remove(wav_path + ".txt")
                        except Exception:
                            pass
                        recording_frames = []
                        silence_count = 0
                        break


if __name__ == "__main__":
    main()
