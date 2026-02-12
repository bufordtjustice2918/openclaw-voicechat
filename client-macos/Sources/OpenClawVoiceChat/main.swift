import Foundation
import AVFoundation

// Config (env overrides)
let receiverURL = URL(string: ProcessInfo.processInfo.environment["RECEIVER_URL"] ?? "http://127.0.0.1:8787/ingest")!
let token = ProcessInfo.processInfo.environment["OPENCLAW_TOKEN"] ?? ""
let keyCode = Int(ProcessInfo.processInfo.environment["PTT_KEY_CODE"] ?? "61")! // Default: Right Option

if token.isEmpty {
    print("OPENCLAW_TOKEN is required")
    exit(1)
}

final class Recorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private var isRecording = false

    func start() {
        if isRecording { return }
        isRecording = true

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        let fileName = "openclaw_" + UUID().uuidString + ".caf"
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(fileName)
        fileURL = url

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            print("Failed to open audio file: \(error)")
            isRecording = false
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                print("Write error: \(error)")
            }
        }

        do {
            try engine.start()
            print("Recording...")
        } catch {
            print("Engine start error: \(error)")
            isRecording = false
        }
    }

    func stop(completion: @escaping (URL?) -> Void) {
        if !isRecording { completion(nil); return }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let url = fileURL
        audioFile = nil
        fileURL = nil
        print("Stopped recording")
        completion(url)
    }
}

func upload(fileURL: URL) {
    var request = URLRequest(url: receiverURL)
    request.httpMethod = "POST"
    request.addValue(token, forHTTPHeaderField: "X-OpenClaw-Token")

    let boundary = "Boundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let fileData = (try? Data(contentsOf: fileURL)) ?? Data()
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"audio.caf\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: audio/x-caf\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    let task = URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
        if let error = error {
            print("Upload error: \(error)")
        } else if let http = response as? HTTPURLResponse {
            print("Upload status: \(http.statusCode)")
        }
        try? FileManager.default.removeItem(at: fileURL)
    }
    task.resume()
}

let recorder = Recorder()

// Request mic permission
let sema = DispatchSemaphore(value: 0)
AVCaptureDevice.requestAccess(for: .audio) { granted in
    print("Mic permission: \(granted)")
    sema.signal()
}
sema.wait()

// Global hotkey via event tap
let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

let callback: CGEventTapCallBack = { proxy, type, event, refcon in
    let keyCodePressed = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let recorder = Unmanaged<Recorder>.fromOpaque(refcon!).takeUnretainedValue()

    if keyCodePressed == keyCode {
        if type == .keyDown {
            recorder.start()
        } else if type == .keyUp {
            recorder.stop { url in
                if let url = url { upload(fileURL: url) }
            }
        }
    }
    return Unmanaged.passRetained(event)
}

let refcon = Unmanaged.passUnretained(recorder).toOpaque()
if let eventTap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: callback,
    userInfo: refcon
) {
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    print("Push‑to‑talk running. Hold keyCode \(keyCode) to record.")
    CFRunLoopRun()
} else {
    print("Failed to create event tap. Make sure Accessibility permissions are granted.")
    exit(1)
}
