// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoicePet",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/eastriverlee/LLM.swift", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "VoicePet",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio"), .product(name: "LLM", package: "LLM.swift")],
            path: "Sources/VoicePet",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
