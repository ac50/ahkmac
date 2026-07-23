// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ahkmac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AhkMacCore"),
        .executableTarget(name: "ahkmac", dependencies: ["AhkMacCore"]),
        .testTarget(name: "AhkMacCoreTests", dependencies: ["AhkMacCore"]),
    ]
)
