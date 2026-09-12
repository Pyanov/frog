// swift-tools-version: 6.2
import PackageDescription

var voicePetDependencies: [Target.Dependency] = [
    .product(name: "LLM", package: "LLM.swift")
]

#if arch(arm64)
voicePetDependencies.append(.product(name: "FluidAudio", package: "FluidAudio"))
#endif

let package = Package(
    name: "VoicePet",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.7"),
        .package(url: "https://github.com/eastriverlee/LLM.swift", from: "3.0.3")
    ],
    targets: [
        .executableTarget(
            name: "VoicePet",
            dependencies: voicePetDependencies,
            path: "Sources/VoicePet",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
