// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .target(name: "FanCore", dependencies: ["Shared"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore", "Shared"]),
    ],
    swiftLanguageModes: [.v5]
)
