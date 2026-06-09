// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "canary-transcriber",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "canary-transcriber", targets: ["CanaryTranscriber"])
    ],
    targets: [
        .executableTarget(
            name: "CanaryTranscriber",
            path: "Sources/CanaryTranscriber"
        )
    ]
)
