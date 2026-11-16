// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "BroadcastPlayback",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "BroadcastPlayback", targets: ["BroadcastPlayback"])],
    dependencies: [.package(name: "HLSPlayback", path: "../HLSPlayback")],
    targets: [
        .target(name: "BroadcastPlayback", dependencies: [
            .product(name: "HLSPlayback", package: "HLSPlayback"),
        ], path: "Sources"),
    ]
)
