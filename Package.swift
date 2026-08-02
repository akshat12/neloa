// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Neloa",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Neloa", targets: ["Neloa"])
    ],
    targets: [
        .executableTarget(name: "Neloa", path: "Sources/Neloa")
    ],
    swiftLanguageModes: [.v5]
)
