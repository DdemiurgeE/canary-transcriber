// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "canary-transcriber",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CanaryTranscriber", targets: ["CanaryTranscriber"]),
        .executable(name: "canary-transcriber", targets: ["CanaryTranscriberApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .target(
            name: "CanaryTranscriberCore",
            path: "Sources/CanaryTranscriberCore"
        ),
        .target(
            name: "CanaryTranscriber",
            dependencies: ["CanaryTranscriberCore"],
            path: "Sources/CanaryTranscriberLib"
        ),
        .executableTarget(
            name: "CanaryTranscriberApp",
            dependencies: [
                "CanaryTranscriber",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CanaryTranscriberApp"
        ),
        .testTarget(
            name: "CanaryTranscriberTests",
            dependencies: ["CanaryTranscriberCore", "CanaryTranscriber"],
            path: "Tests/CanaryTranscriberTests"
        )
    ]
)
