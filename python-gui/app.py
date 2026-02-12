import sys
import time
import wave
import queue
import threading
import requests
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
                arr = array.array('h', indata)
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

class MainWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("OpenClaw VoiceChat")
        self.setMinimumSize(720, 520)

        self.recorder = Recorder()
        self.recorder.levelChanged.connect(self.on_level)
        self.recorder.statusChanged.connect(self.set_status)

        central = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(central)

        self.receiver = QtWidgets.QLineEdit("http://127.0.0.1:8787/ingest")
        self.token = QtWidgets.QLineEdit("")
        self.token.setEchoMode(QtWidgets.QLineEdit.Password)

        layout.addWidget(QtWidgets.QLabel("Receiver URL"))
        layout.addWidget(self.receiver)
        layout.addWidget(QtWidgets.QLabel("Token"))
        layout.addWidget(self.token)

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
        layout.addLayout(btns)

        self.status = QtWidgets.QLabel("Status: Idle")
        layout.addWidget(self.status)

        self.setCentralWidget(central)

    def refresh_devices(self):
        self.deviceBox.clear()
        devices = sd.query_devices()
        for idx, d in enumerate(devices):
            if d['max_input_channels'] > 0:
                self.deviceBox.addItem(f"{idx}: {d['name']}", idx)

    def on_level(self, v):
        self.level.setValue(int(v * 100))

    def set_status(self, s):
        self.status.setText(f"Status: {s}")

    def toggle_record(self):
        if self.recordBtn.text() == "Record":
            device = self.deviceBox.currentData()
            self.recorder.start(device=device)
            self.recordBtn.setText("Stop & Send")
        else:
            audio = self.recorder.stop()
            self.recordBtn.setText("Record")
            if audio:
                threading.Thread(target=self.send_audio, args=(audio,), daemon=True).start()

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
            files = {"audio": open(path, "rb")}
            headers = {"X-OpenClaw-Token": token}
            r = requests.post(url, files=files, headers=headers, timeout=30)
            r.raise_for_status()
            self.set_status("Uploaded successfully")
            os.remove(path)
        except Exception as e:
            self.set_status(f"Upload failed: {e}")

app = QtWidgets.QApplication(sys.argv)
window = MainWindow()
window.show()
sys.exit(app.exec())
