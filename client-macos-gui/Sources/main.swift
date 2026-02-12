import SwiftUI
import AVFoundation
import AppKit
import AudioToolbox

@main
struct OpenClawVoiceChatGUIApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 660, minHeight: 460)
        }
    }
}

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

final class AppState: ObservableObject {
    @Published var receiverURL: String = "http://127.0.0.1:8787/ingest"
    @Published var token: String = ""
    @Published var status: String = "Idle"
    @Published var isRecording: Bool = false
    @Published var lastUpload: String = ""
    @Published var level: Double = 0.0
    @Published var inputDevices: [InputDevice] = []
    @Published var selectedDeviceId: AudioDeviceID? = nil
    @Published var fastModeLocalWhisper: Bool = true
    @Published var uploadAudioInBackground: Bool = false

    private var recorder: AVAudioRecorder?
    private var tempURL: URL?
    private var meterTimer: Timer?

    init() {
        loadEnvFile()
        refreshInputDevices()
        requestMicAccess()
    }

    func loadEnvFile() {
        let path = (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw-voicechat.env")).path
        guard let data = try? String(contentsOfFile: path) else { return }
        for line in data.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            let cleaned = trimmed.replacingOccurrences(of: "export ", with: "")
            let parts = cleaned.split(separator: "=", maxSplits: 1).map { String($0) }
            if parts.count != 2 { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if key == "RECEIVER_URL" { receiverURL = value }
            if key == "OPENCLAW_TOKEN" { token = value }
        }
    }

    func saveEnvFile() {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw-voicechat.env")
        let content = "export RECEIVER_URL=\"\(receiverURL)\"\nexport OPENCLAW_TOKEN=\"\(token)\"\n"
        try? content.write(to: path, atomically: true, encoding: .utf8)
        status = "Settings saved"
    }

    func requestMicAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.status = granted ? "Mic permission granted" : "Mic permission denied"
            }
        }
    }

    func refreshInputDevices() {
        inputDevices = listInputDevices()
        if selectedDeviceId == nil {
            selectedDeviceId = inputDevices.first?.id
        }
    }

    func setDefaultInputDevice(_ deviceId: AudioDeviceID) {
        var deviceID = deviceId
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &deviceID)
        if status == noErr {
            selectedDeviceId = deviceId
            self.status = "Input device set"
        } else {
            self.status = "Failed to set input device (\(status))"
        }
    }

    func startRecording() {
        if isRecording { return }
        status = "Recording…"
        isRecording = true

        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            status = "Mic permission not granted"
            isRecording = false
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString + ".caf"
        let url = tempDir.appendingPathComponent(filename)
        tempURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleIMA4,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 12800
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            startMeter()
        } catch {
            status = "Failed to start recording: \(error.localizedDescription)"
            isRecording = false
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        recorder?.stop()
        recorder = nil
        stopMeter()

        guard let url = tempURL else {
            status = "No recording found"
            return
        }

        if fastModeLocalWhisper {
            status = "Transcribing locally…"
            if let transcript = runLocalWhisper(fileURL: url), !transcript.isEmpty {
                sendText(transcript)
                if uploadAudioInBackground {
                    upload(fileURL: url)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            } else {
                status = "Local whisper failed (is whisper installed?)"
            }
        } else {
            status = "Uploading…"
            upload(fileURL: url)
        }
    }

    func startMeter() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0) // -160..0
            let normalized = max(0.0, (power + 60) / 60) // 0..1
            self.level = Double(normalized)
        }
    }

    func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        level = 0
    }

    func testMic() {
        status = "Mic test: recording 2s…"
        startRecording()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isRecording = false
            self.recorder?.stop()
            self.recorder = nil
            self.stopMeter()
            if let url = self.tempURL {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.play()
                    self.status = "Mic test: playback"
                } else {
                    self.status = "Mic test: playback failed"
                }
            }
        }
    }

    func runLocalWhisper(fileURL: URL) -> String? {
        let which = Process()
        which.launchPath = "/usr/bin/which"
        which.arguments = ["whisper"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus != 0 { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let whisperPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if whisperPath == nil || whisperPath!.isEmpty { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let outDir = tempDir.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.launchPath = whisperPath
        proc.arguments = ["--model", "tiny", "--language", "en", "--output_format", "txt", "--output_dir", outDir.path, fileURL.path]
        try? proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 { return nil }

        let txtPath = outDir.appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + ".txt")
        let text = try? String(contentsOf: txtPath)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sendText(_ text: String) {
        let textURL = receiverURL.replacingOccurrences(of: "/ingest", with: "/ingest_text")
        guard let endpoint = URL(string: textURL) else {
            status = "Invalid RECEIVER_URL"
            return
        }
        if token.isEmpty {
            status = "OPENCLAW_TOKEN is required"
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-OpenClaw-Token")
        let payload = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.status = "Text send failed: \(error.localizedDescription)"
                } else {
                    let http = response as? HTTPURLResponse
                    if http?.statusCode == 200 {
                        self?.status = "Text sent"
                    } else {
                        self?.status = "Text send failed (status \(http?.statusCode ?? -1))"
                    }
                }
            }
        }.resume()
    }

    func upload(fileURL: URL) {
        guard let endpoint = URL(string: receiverURL) else {
            status = "Invalid RECEIVER_URL"
            return
        }
        if token.isEmpty {
            status = "OPENCLAW_TOKEN is required"
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-OpenClaw-Token")

        var body = Data()
        let filename = fileURL.lastPathComponent
        let mimeType = "audio/x-caf"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        if let fileData = try? Data(contentsOf: fileURL) {
            body.append(fileData)
        }
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: body) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.status = "Upload failed: \(error.localizedDescription)"
                } else {
                    let http = response as? HTTPURLResponse
                    if http?.statusCode == 200 {
                        self?.status = "Uploaded successfully"
                        self?.lastUpload = filename
                    } else {
                        self?.status = "Upload failed (status \(http?.statusCode ?? -1))"
                    }
                }
                try? FileManager.default.removeItem(at: fileURL)
            }
        }.resume()
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                Text("OpenClaw VoiceChat")
                    .font(.largeTitle)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Receiver URL")
                TextField("http://127.0.0.1:8787/ingest", text: $state.receiverURL)
                    .textFieldStyle(.roundedBorder)

                Text("Token")
                SecureField("OPENCLAW_TOKEN", text: $state.token)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Input Device")
                HStack {
                    Picker("Input Device", selection: $state.selectedDeviceId) {
                        ForEach(state.inputDevices) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                    Button("Refresh") { state.refreshInputDevices() }
                }
                .onChange(of: state.selectedDeviceId) { newValue in
                    if let id = newValue { state.setDefaultInputDevice(id) }
                }
            }

            HStack(spacing: 12) {
                Button(action: {
                    if state.isRecording { state.stopRecording() } else { state.startRecording() }
                }) {
                    Text(state.isRecording ? "Stop & Send" : "Record")
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Save Settings") {
                    state.saveEnvFile()
                }
            }

            HStack(spacing: 12) {
                Button("Test Mic") { state.testMic() }
                Toggle("Fast mode (local whisper)", isOn: $state.fastModeLocalWhisper)
                Toggle("Upload audio in background", isOn: $state.uploadAudioInBackground)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Recording Level")
                ProgressView(value: state.level)
            }

            Text("Status: \(state.status)")
                .font(.headline)

            if !state.lastUpload.isEmpty {
                Text("Last upload: \(state.lastUpload)")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }
}

// MARK: - CoreAudio helpers
func listInputDevices() -> [InputDevice] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
    if status != noErr { return [] }

    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
    if status != noErr { return [] }

    var inputs: [InputDevice] = []
    for id in deviceIDs {
        if isInputDevice(id) {
            let name = getDeviceName(id) ?? "Unknown"
            inputs.append(InputDevice(id: id, name: name))
        }
    }
    return inputs
}

func isInputDevice(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize)
    if status != noErr { return false }
    let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
    defer { bufferList.deallocate() }
    var size = dataSize
    let status2 = AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList)
    if status2 != noErr { return false }
    let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
    for buffer in buffers {
        if buffer.mNumberChannels > 0 { return true }
    }
    return false
}

func getDeviceName(_ id: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var cfName: CFString = "" as CFString
    var dataSize = UInt32(MemoryLayout<CFString>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &cfName)
    if status != noErr { return nil }
    return cfName as String
}
