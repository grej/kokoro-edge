// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "kokoro-edge",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "KokoroEdge", targets: ["KokoroEdge"]),
        .executable(name: "kokoro-edge", targets: ["KokoroEdgeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/mlalma/kokoro-ios.git", from: "1.0.8"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.17.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "KokoroEdge",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdRouter", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .executableTarget(
            name: "KokoroEdgeCLI",
            dependencies: ["KokoroEdge"]
        ),
        .testTarget(
            name: "KokoroEdgeTests",
            dependencies: [
                "KokoroEdge",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
    ]
)
