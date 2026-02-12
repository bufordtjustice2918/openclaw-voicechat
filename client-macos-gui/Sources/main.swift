import SwiftUI
import AVFoundation

@main
struct OpenClawVoiceChatGUIApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 520, minHeight: 360)
        }
    }
}

final class AppState: ObservableObject {
    @Published var receiverURL: String = "http://127.0.0.1:8787/ingest"
    @Published var token: String = ""
    @Published var status: String = "Idle"
    @Published var isRecording: Bool = false
    @Published var lastUpload: String = ""

    private var recorder: AVAudioRecorder?
    private var tempURL: URL?

    init() {
        loadEnvFile()
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
    }

    func startRecording() {
        if isRecording { return }
        status = "Recording…"
        isRecording = true

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
            recorder?.record()
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
        status = "Uploading…"

        guard let url = tempURL else {
            status = "No recording found"
            return
        }
        upload(fileURL: url)
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
            Text("OpenClaw VoiceChat")
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Receiver URL")
                TextField("http://127.0.0.1:8787/ingest", text: $state.receiverURL)
                    .textFieldStyle(.roundedBorder)

                Text("Token")
                SecureField("OPENCLAW_TOKEN", text: $state.token)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button(action: {
                    if state.isRecording { state.stopRecording() } else { state.startRecording() }
                }) {
                    Text(state.isRecording ? "Stop & Upload" : "Record")
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("Save Settings") {
                    state.saveEnvFile()
                }
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
