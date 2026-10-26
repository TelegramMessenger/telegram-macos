// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusFilterCore",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "FocusFilterCore", targets: ["FocusFilterCore"])],
    targets: [
        .target(name: "FocusFilterCore"),
        .testTarget(name: "FocusFilterCoreTests", dependencies: ["FocusFilterCore"])
    ]
)
