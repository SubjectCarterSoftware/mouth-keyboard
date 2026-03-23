// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TestRunner",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.22.0"),
        .package(path: "/Users/elicarter/Library/Developer/Xcode/DerivedData/Speech2Text-bwengovfgtvdoueydodmpxlsrlni/SourcePackages/checkouts/mlx-swift-lm")
    ],
    targets: [
        .executableTarget(
            name: "TestRunner",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ]
        )
    ]
)
