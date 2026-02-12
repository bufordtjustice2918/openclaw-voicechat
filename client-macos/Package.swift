// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenClawVoiceChat",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "openclaw-voicechat", targets: ["OpenClawVoiceChat"])
    ],
    targets: [
        .executableTarget(
            name: "OpenClawVoiceChat",
            path: "Sources/OpenClawVoiceChat"
        )
    ]
)
