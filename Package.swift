// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
    ],
    swiftLanguageModes: [.v5]
)
