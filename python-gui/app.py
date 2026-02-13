import sys
import time
import wave
import queue
import threading
import requests
import os
import json
import vosk
from PySide6 import QtWidgets, QtCore
import sounddevice as sd

class Recorder(QtCore.QObject):
    levelChanged = QtCore.Signal(float)
    statusChanged = QtCore.Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.q = queue.Queue()
        self.recording = False
        self.stream = None
        self.frames = []
        self.samplerate = 16000

    def _callback(self, indata, frames, time_info, status):
        if status:
            self.statusChanged.emit(str(status))
        if self.recording:
            self.frames.append(bytes(indata))
            # compute RMS level
            if len(indata) > 0:
                # indata is bytes-like int16
                import array
                arr = array.array('h')
                arr.frombytes(indata)
                if len(arr):
                    rms = (sum(x*x for x in arr) / len(arr)) ** 0.5
                    level = min(1.0, rms / 2000.0)
                    self.levelChanged.emit(level)

    def start(self, device=None):
        if self.recording:
            return
        self.frames = []
        self.recording = True
        self.stream = sd.RawInputStream(
            samplerate=self.samplerate,
            channels=1,
            dtype='int16',
            blocksize=0,
            device=device,
            callback=self._callback,
        )
        self.stream.start()
        self.statusChanged.emit("Recording…")

    def stop(self):
        if not self.recording:
            return None
        self.recording = False
        if self.stream:
            self.stream.stop()
            self.stream.close()
            self.stream = None
        self.statusChanged.emit("Recording stopped")
        return b"".join(self.frames)

class KeyFilter(QtCore.QObject):
    def __init__(self, parent, on_down, on_up, key_getter):
        self.on_key = key_getter
        super().__init__(parent)
        self.on_down = on_down
        self.on_up = on_up
        self.on_key = key_getter
        self.down = False

    def eventFilter(self, obj, event):
        if event.type() == QtCore.QEvent.KeyPress and event.key() == self.on_key():
            if not self.down:
                self.down = True
                self.on_down()
            return True
        if event.type() == QtCore.QEvent.KeyRelease and event.key() == self.on_key():
            if self.down:
                self.down = False
                self.on_up()
            return True
        return False

class MainWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("OpenClaw VoiceChat")
        self.setMinimumSize(720, 520)

        self.settings_path = os.path.expanduser("~/.openclaw-voicechat.json")
        self.wake_thread = None
        self.recorder = Recorder()
        self.recorder.levelChanged.connect(self.on_level)
        self.recorder.statusChanged.connect(self.set_status)

        central = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(central)

        self.receiver = QtWidgets.QLineEdit("http://127.0.0.1:8787/ingest")
        self.token = QtWidgets.QLineEdit("")
        self.token.setEchoMode(QtWidgets.QLineEdit.Password)

        self.localWhisper = QtWidgets.QCheckBox("Use local whisper")
        self.localWhisper.setChecked(True)
        self.alwaysListen = QtWidgets.QCheckBox("Always‑listen (wake word)")
        self.wakeWord = QtWidgets.QLineEdit("buford")
        self.modelStatus = QtWidgets.QLabel("Model: tiny")
        self.hotkey = QtWidgets.QLineEdit("Space")
        self.hotkeyStatus = QtWidgets.QLabel("Hotkey: idle")
        self.hotkeyLight = QtWidgets.QLabel("●")
        self.hotkeyLight.setStyleSheet("color: #c00; font-size: 20px;")
        self.hotkeyStatus.setStyleSheet("color: white; background-color: #c00; padding: 2px 6px; border-radius: 4px;")
        self.wakeStatus = QtWidgets.QLabel("Wake: idle")
        self.wakeLight = QtWidgets.QLabel("●")
        self.wakeLight.setStyleSheet("color: #c00; font-size: 20px;")
        self.wakeDetectedLight = QtWidgets.QLabel("●")
        self.wakeDetectedLight.setStyleSheet("color: #c00; font-size: 20px;")
        self.recordLight = QtWidgets.QLabel("●")
        self.recordLight.setStyleSheet("color: #c00; font-size: 20px;")
        self.wakeStatus.setStyleSheet("color: white; background-color: #c00; padding: 2px 6px; border-radius: 4px;")
        self.modelStatus.setStyleSheet("color: white; background-color: #c00; padding: 2px 6px; border-radius: 4px;")

        layout.addWidget(QtWidgets.QLabel("Receiver URL"))
        layout.addWidget(self.receiver)
        layout.addWidget(QtWidgets.QLabel("Token"))
        layout.addWidget(self.token)
        layout.addWidget(self.localWhisper)
        hl = QtWidgets.QHBoxLayout()
        hl.addWidget(QtWidgets.QLabel("Wake word"))
        hl.addWidget(self.wakeWord)
        hl.addWidget(self.alwaysListen)
        hl.addWidget(self.modelStatus)
        layout.addLayout(hl)
        self.alwaysListen.stateChanged.connect(lambda _: self.start_wake_listener())

        self.deviceBox = QtWidgets.QComboBox()
        self.refresh_devices()
        layout.addWidget(QtWidgets.QLabel("Input Device"))
        layout.addWidget(self.deviceBox)

        self.level = QtWidgets.QProgressBar()
        self.level.setRange(0, 100)
        layout.addWidget(QtWidgets.QLabel("Recording Level"))
        layout.addWidget(self.level)

        btns = QtWidgets.QHBoxLayout()
        self.recordBtn = QtWidgets.QPushButton("Record")
        self.recordBtn.clicked.connect(self.toggle_record)
        btns.addWidget(self.recordBtn)

        self.saveBtn = QtWidgets.QPushButton("Save Settings")
        self.saveBtn.clicked.connect(self.save_settings)
        btns.addWidget(self.saveBtn)

        self.downloadBtn = QtWidgets.QPushButton("Download larger model")
        self.downloadBtn.clicked.connect(self.download_model)
        btns.addWidget(self.downloadBtn)

        self.debug = QtWidgets.QCheckBox("Debug")
        self.debug.setChecked(True)
        btns.addWidget(self.debug)

        layout.addLayout(btns)

        statusRow = QtWidgets.QHBoxLayout()
        statusRow.addWidget(QtWidgets.QLabel('Status:'))
        statusRow.addWidget(self.hotkeyLight)
        statusRow.addWidget(QtWidgets.QLabel('Hotkey'))
        statusRow.addWidget(self.wakeLight)
        statusRow.addWidget(QtWidgets.QLabel('Wake listening'))
        statusRow.addWidget(self.wakeDetectedLight)
        statusRow.addWidget(QtWidgets.QLabel('Wake detected'))
        statusRow.addWidget(self.recordLight)
        statusRow.addWidget(QtWidgets.QLabel('Recording'))
        statusRow.addStretch(1)
        layout.addLayout(statusRow)

        self.log = QtWidgets.QTextEdit()
        self.log.setReadOnly(True)
        self.log.setStyleSheet('background-color: #000; color: #fff; font-family: Menlo;')
        layout.addWidget(self.log)
        self.append_log('✅ Ready')

        self.setCentralWidget(central)
        self.load_settings()
        self.update_model_status()
        self.keyFilter = KeyFilter(self, self.start_hotkey_record, self.stop_hotkey_record, self.get_hotkey_qt)
        QtWidgets.QApplication.instance().installEventFilter(self.keyFilter)

    def load_settings(self):
        try:
            if os.path.exists(self.settings_path):
                data = json.load(open(self.settings_path, 'r'))
                self.receiver.setText(data.get('receiver', self.receiver.text()))
                self.token.setText(data.get('token', ''))
                self.localWhisper.setChecked(data.get('local_whisper', True))
                self.wakeWord.setText(data.get('wake_word', 'buford'))
                self.alwaysListen.setChecked(data.get('always_listen', False))
        except Exception:
            pass

    def save_settings(self):
        data = {
            'receiver': self.receiver.text().strip(),
            'token': self.token.text().strip(),
            'local_whisper': self.localWhisper.isChecked(),
            'wake_word': self.wakeWord.text().strip(),
            'always_listen': self.alwaysListen.isChecked(),
        }
        try:
            json.dump(data, open(self.settings_path, 'w'))
            self.set_status('✅ Settings saved')
        except Exception as e:
            self.set_status(f'❌ Settings save failed: {e}')

    def update_model_status(self):
        base_dir = os.path.join(os.path.dirname(__file__), 'whisper')
        base_model = os.path.join(base_dir, 'ggml-base.bin')
        if os.path.exists(base_model):
            self.modelStatus.setText('Model: base')
            self.modelStatus.setStyleSheet('color: white; background-color: #0a0; padding: 2px 6px; border-radius: 4px;')
        else:
            self.modelStatus.setText('Model: tiny')
            self.modelStatus.setStyleSheet('color: white; background-color: #c00; padding: 2px 6px; border-radius: 4px;')

    def refresh_devices(self):
        self.deviceBox.clear()
        devices = sd.query_devices()
        for idx, d in enumerate(devices):
            if d['max_input_channels'] > 0:
                self.deviceBox.addItem(f"{idx}: {d['name']}", idx)

    def debug_log(self, msg):
        if self.debug.isChecked():
            self.append_log('🐛 ' + msg)

    def append_log(self, msg):
        ts = QtCore.QDateTime.currentDateTime().toString('HH:mm:ss')
        self.log.append(f'[{ts}] {msg}')

    def on_level(self, v):
        self.level.setValue(int(v * 100))

    def set_status(self, s):
        self.append_log(f'📝 {s}')

    def get_hotkey_qt(self):
        key = self.hotkey.text().strip().lower()
        mapping = {'space': QtCore.Qt.Key_Space, 'enter': QtCore.Qt.Key_Return, 'return': QtCore.Qt.Key_Return}
        return mapping.get(key, QtCore.Qt.Key_Space)

    def start_hotkey_record(self):
        if self.recordBtn.text() == 'Record':
            self.hotkeyStatus.setText('Hotkey: down')
            self.hotkeyStatus.setStyleSheet('color: white; background-color: #0a0; padding: 2px 6px; border-radius: 4px;')
            self.hotkeyLight.setStyleSheet('color: #0a0; font-size: 16px;')
            self.set_status('␣ Hotkey down: recording')
            self.toggle_record()

    def stop_hotkey_record(self):
        if self.recordBtn.text() != 'Record':
            self.hotkeyStatus.setText('Hotkey: idle')
            self.hotkeyStatus.setStyleSheet('color: white; background-color: #c00; padding: 2px 6px; border-radius: 4px;')
            self.hotkeyLight.setStyleSheet('color: #c00; font-size: 16px;')
            self.set_status('␣ Hotkey up: send')
            self.toggle_record()

    def toggle_record(self):
        if self.recordBtn.text() == "Record":
            device = self.deviceBox.currentData()
            self.recorder.start(device=device)
            self.recordLight.setStyleSheet("color: #0a0; font-size: 20px;")
            self.recordBtn.setText("Stop & Send")
        else:
            audio = self.recorder.stop()
            self.recordLight.setStyleSheet("color: #c00; font-size: 20px;")
            self.recordBtn.setText("Record")
            if audio:
                threading.Thread(target=self.send_audio, args=(audio,), daemon=True).start(); self.debug_log('Wake send thread started')

    def send_audio(self, audio_bytes: bytes):
        try:
            url = self.receiver.text().strip()
            token = self.token.text().strip()
            if not url or not token:
                self.set_status("Missing URL or token")
                return
            # write wav temp
            import tempfile
            fd, path = tempfile.mkstemp(suffix=".wav")
            import os
            os.close(fd)
            with wave.open(path, "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(16000)
                wf.writeframes(audio_bytes)

            self.debug_log(f'Send audio bytes: {len(audio_bytes)}')
            # try local whisper.cpp
            text = self.run_local_whisper(path) if self.localWhisper.isChecked() else ""
            if text:
                self.send_text(text)
                self.set_status("Text sent")
            else:
                files = {"audio": open(path, "rb")}
                headers = {"X-OpenClaw-Token": token}
                r = requests.post(url, files=files, headers=headers, timeout=30)
                r.raise_for_status()
                self.set_status("Uploaded successfully")

            os.remove(path)
        except Exception as e:
            self.set_status(f"Upload failed: {e}")

    def run_local_whisper(self, wav_path: str):
        try:
            import subprocess, os, tempfile
            base_dir = os.path.join(os.path.dirname(__file__), "whisper")
            whisper_bin = os.path.join(base_dir, "whisper")
            tiny_model = os.path.join(base_dir, "ggml-tiny.bin")
            if not (os.path.exists(whisper_bin) and os.path.exists(tiny_model)):
                self.set_status('❌ Bundled whisper missing (run build_app_wrapper.sh)')
                return ''
            out_base = os.path.join(tempfile.gettempdir(), f"whisper_{int(time.time())}")
            proc = subprocess.run([whisper_bin, "-m", tiny_model, "-f", wav_path, "-otxt", "-of", out_base, "-l", "en"],
                                 capture_output=True, text=True, timeout=120)
            if proc.returncode != 0:
                return ""
            txt = out_base + ".txt"
            if not os.path.exists(txt):
                return ""
            with open(txt, "r", encoding="utf-8") as f:
                return f.read().strip()
        except Exception:
            return ""

    def send_text(self, text: str):
        try:
            url = self.receiver.text().strip().replace("/ingest", "/ingest_text")
            token = self.token.text().strip()
            if not url or not token:
                return
            r = requests.post(url, json={"text": text}, headers={"X-OpenClaw-Token": token}, timeout=10)
            r.raise_for_status()
        except Exception:
            pass

    def start_wake_listener(self):
        if self.wake_thread and self.wake_thread.is_alive():
            return
        if not self.alwaysListen.isChecked():
            self.set_status('🛑 Wake word disabled')
            return
        def run():
            try:
                model_path = os.path.expanduser('.vosk/vosk-model')
                if not os.path.isdir(model_path):
                    self.set_status('❌ Vosk model missing (.vosk/vosk-model)')
                    return
                model = vosk.Model(model_path)
                rec = vosk.KaldiRecognizer(model, 16000, f'["{self.wakeWord.text().strip().lower()}"]')
                try:
                    import webrtcvad
                    vad = webrtcvad.Vad(2)
                    use_webrtcvad = True
                except Exception as e:
                    self.set_status(f"⚠️ webrtcvad unavailable, using energy VAD: {e}")
                    use_webrtcvad = False
                    vad = None
                q = queue.Queue()
                def cb(indata, frames, time_info, status):
                    q.put(bytes(indata))
                frame_bytes = int(16000*0.03*2)
                device = self.deviceBox.currentData()
                with sd.RawInputStream(samplerate=16000, channels=1, dtype='int16', blocksize=frame_bytes, device=device, callback=cb):
                    self.wakeStatus.setText('Wake: listening'); self.wakeStatus.setStyleSheet('color: white; background-color: #0a0; padding: 2px 6px; border-radius: 4px;'); self.wakeLight.setStyleSheet('color: #0a0; font-size: 16px;'); self.set_status('🟢 Listening for wake word…')
                    listening = True
                    triggered = False
                    frames = []
                    silence = 0
                    silence_frames = 12
                    max_frames = int(16000 * 10)  # ~10s cap
                    while self.alwaysListen.isChecked():
                        try:
                            data = q.get(timeout=1)
                            self.debug_log(f"Wake data bytes: {len(data)}")
                        except Exception:
                            if triggered:
                                self.debug_log("Wake: waiting for audio...")
                            continue
                        if listening and rec.AcceptWaveform(data):
                            try:
                                r = json.loads(rec.Result())
                                if r.get('text','').strip().lower() == self.wakeWord.text().strip().lower():
                                    triggered = True
                                    listening = False
                                    frames = []
                                    silence = 0
                                    self.wakeStatus.setText('Wake: recording'); self.wakeStatus.setStyleSheet('color: white; background-color: #0a0; padding: 2px 6px; border-radius: 4px;'); self.wakeLight.setStyleSheet('color: #0a0; font-size: 16px;'); self.set_status('🎙️ Wake word detected'); self.debug_log('Wake triggered, starting capture')
                            except Exception:
                                pass
                        if triggered:
                            for i in range(0, len(data), frame_bytes):
                                frame = data[i:i+frame_bytes]
                                if len(frame) < frame_bytes:
                                    continue
                                frames.append(frame)
                                if use_webrtcvad:
                                    if vad.is_speech(frame, 16000):
                                        silence = 0
                                    else:
                                        silence += 1
                                else:
                                    # energy-based VAD fallback
                                    import array
                                    arr = array.array('h')
                                    arr.frombytes(frame)
                                    if len(arr) > 0:
                                        energy = sum(x*x for x in arr) / len(arr)
                                        if energy > 1500:
                                            silence = 0
                                        else:
                                            silence += 1
                                if len(frames) % 50 == 0:
                                    self.debug_log(f"Wake frames={len(frames)} silence={silence}")
                                if silence >= silence_frames or len(frames) >= max_frames:
                                    if len(frames) == 0:
                                        listening = True
                                        triggered = False
                                        silence = 0
                                        continue
                                    triggered = False
                                    listening = True
                                    audio = b"".join(frames)
                                    self.debug_log(f'Wake frames: {len(frames)} bytes: {len(audio)}')
                                    if len(audio) == 0:
                                        self.set_status("⚠️ Wake captured no audio")
                                    else:
                                        self.set_status("📤 Wake send")
                                    threading.Thread(target=self.send_audio, args=(audio,), daemon=True).start(); self.debug_log('Wake send thread started')
                                    frames = []
                                    silence = 0
                                    break
            except Exception as e:
                self.set_status(f'❌ Wake listener error: {e}')
        self.wake_thread = threading.Thread(target=run, daemon=True)
        self.wake_thread.start()

    def download_model(self):
        try:
            import os, requests
            base_dir = os.path.join(os.path.dirname(__file__), "whisper")
            os.makedirs(base_dir, exist_ok=True)
            url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
            dest = os.path.join(base_dir, "ggml-base.bin")
            self.set_status("Downloading base model…")
            r = requests.get(url, stream=True, timeout=60)
            r.raise_for_status()
            with open(dest, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024*1024):
                    if chunk:
                        f.write(chunk)
            self.set_status("Downloaded base model")
        except Exception as e:
            self.set_status(f"Download failed: {e}")

app = QtWidgets.QApplication(sys.argv)
window = MainWindow()
window.show()
sys.exit(app.exec())
