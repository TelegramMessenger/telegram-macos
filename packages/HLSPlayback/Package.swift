// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "HLSPlayback",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "HLSPlayback", targets: ["HLSPlayback"]),
    ],
    targets: [
        .target(
            name: "HLSPlayback",
            path: "Sources/HLSPlayback"),
        .testTarget(
            name: "HLSPlaybackTests",
            dependencies: ["HLSPlayback"],
            path: "Tests/HLSPlaybackTests"),
    ]
)
