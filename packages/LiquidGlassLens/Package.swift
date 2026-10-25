// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "LiquidGlassLens",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "LiquidGlassLens", targets: ["LiquidGlassLens"])],
    targets: [
        .target(name: "LiquidGlassLens"),
        .testTarget(name: "LiquidGlassLensTests", dependencies: ["LiquidGlassLens"]),
    ]
)
