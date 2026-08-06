// swift-tools-version: 6.1
import PackageDescription

let mlxEnabled = Context.environment["NELOA_ENABLE_MLX"] == "1"

var packageDependencies: [Package.Dependency] = []
var neloaDependencies: [Target.Dependency] = []
var neloaSwiftSettings: [SwiftSetting] = []

if mlxEnabled {
    packageDependencies = [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.4")),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.6"),
        .package(url: "https://github.com/huggingface/swift-huggingface", .upToNextMajor(from: "0.9.0")),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMajor(from: "1.3.0"))
    ]
    neloaDependencies = [
        .product(name: "MLXVLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers")
    ]
    neloaSwiftSettings = [.define("NELOA_MLX")]
}

let package = Package(
    name: "Neloa",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Neloa", targets: ["Neloa"])
    ],
    dependencies: packageDependencies,
    targets: [
        .executableTarget(
            name: "Neloa",
            dependencies: neloaDependencies,
            path: "Sources/Neloa",
            swiftSettings: neloaSwiftSettings
        )
    ],
    swiftLanguageModes: [.v5]
)
