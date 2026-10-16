// swift-tools-version: 6.2
// ThongDichKit — all of the app's logic and screens.
// Every dependency is pinned to an exact, verified release.
// Optional features of the libraries that the app does not need are switched off (`traits: []`).

import PackageDescription

let package = Package(
    name: "ThongDichKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "ThongDichKit", targets: ["ThongDichKit"])
    ],
    dependencies: [
        // On-device LLM runtime (Apple MLX, runs on the iPhone GPU through Metal)
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3", traits: []),
        // Tokenizers for the Gemma models (loaded from local files only)
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.5"),
        // Parakeet speech recognition + Silero voice detection on the Neural Engine
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        .target(
            name: "ThongDichKit",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
