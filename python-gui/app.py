import sys
from PySide6 import QtWidgets, QtCore

class MainWindow(QtWidgets.QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("OpenClaw VoiceChat")
        self.setMinimumSize(700, 480)
        central = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(central)

        self.receiver = QtWidgets.QLineEdit("http://127.0.0.1:8787/ingest")
        self.token = QtWidgets.QLineEdit("")
        self.token.setEchoMode(QtWidgets.QLineEdit.Password)

        layout.addWidget(QtWidgets.QLabel("Receiver URL"))
        layout.addWidget(self.receiver)
        layout.addWidget(QtWidgets.QLabel("Token"))
        layout.addWidget(self.token)

        self.status = QtWidgets.QLabel("Status: Idle")
        layout.addWidget(self.status)

        self.setCentralWidget(central)

app = QtWidgets.QApplication(sys.argv)
window = MainWindow()
window.show()
sys.exit(app.exec())
