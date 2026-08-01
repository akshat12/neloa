// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Humana",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Humana", targets: ["Humana"])
    ],
    targets: [
        .executableTarget(name: "Humana", path: "Sources/Humana")
    ],
    swiftLanguageModes: [.v5]
)
