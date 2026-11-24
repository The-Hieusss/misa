// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MISA",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MISA",
            path: "Sources/MISA",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("SoundAnalysis"),
                .linkedFramework("EventKit"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
