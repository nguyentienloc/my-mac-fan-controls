// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Shared"),
        .target(name: "FanCore", dependencies: ["Shared"]),
        .target(name: "SystemStats"),
        .executableTarget(name: "fanctld", dependencies: ["FanCore", "Shared"]),
        .executableTarget(name: "FanControlApp", dependencies: ["Shared", "SystemStats"]),
        .testTarget(name: "SharedTests", dependencies: ["Shared"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore", "Shared"]),
        .testTarget(name: "SystemStatsTests", dependencies: ["SystemStats"]),
    ],
    swiftLanguageModes: [.v5]
)
