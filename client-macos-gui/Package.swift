// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "OpenClawVoiceChatGUI",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "openclaw-voicechat-gui", targets: ["OpenClawVoiceChatGUI"]) 
    ],
    targets: [
        .executableTarget(
            name: "OpenClawVoiceChatGUI",
            path: "Sources"
        )
    ]
)
