// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TelepathyEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .macCatalyst(.v17)
    ],
    products: [
        .library(name: "NeuralCore", targets: ["NeuralCore"]),
        .library(name: "SessionKit", targets: ["SessionKit"]),
        .library(name: "MemoryBankKit", targets: ["MemoryBankKit"]),
        .library(name: "LLMBridge", targets: ["LLMBridge"]),
        .executable(name: "Streamer", targets: ["Streamer"])
    ],
    targets: [
        .target(
            name: "NeuralCore",
            path: "Packages/NeuralCore/Sources/NeuralCore"
        ),
        .testTarget(
            name: "NeuralCoreTests",
            dependencies: ["NeuralCore"],
            path: "Packages/NeuralCore/Tests/NeuralCoreTests"
        ),
        .target(
            name: "SessionKit",
            dependencies: ["NeuralCore"],
            path: "Packages/SessionKit/Sources/SessionKit"
        ),
        .testTarget(
            name: "SessionKitTests",
            dependencies: ["SessionKit", "NeuralCore"],
            path: "Packages/SessionKit/Tests/SessionKitTests"
        ),
        .target(
            name: "MemoryBankKit",
            dependencies: ["NeuralCore"],
            path: "Packages/MemoryBankKit/Sources/MemoryBankKit"
        ),
        .target(
            name: "LLMBridge",
            dependencies: ["MemoryBankKit", "NeuralCore"],
            path: "Packages/LLMBridge/Sources/LLMBridge"
        ),
        .executableTarget(
            name: "Streamer",
            dependencies: ["NeuralCore"],
            path: "Streamer/Sources/Streamer"
        )
    ]
)
