// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusFilterCore",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "FocusFilterCore", targets: ["FocusFilterCore"]),
        .library(name: "FocusFilterInfrastructure", targets: ["FocusFilterInfrastructure"])
    ],
    targets: [
        .target(name: "FocusFilterCore"),
        .target(name: "FocusFilterInfrastructure", dependencies: ["FocusFilterCore"]),
        .testTarget(name: "FocusFilterCoreTests", dependencies: ["FocusFilterCore"]),
        .testTarget(name: "FocusFilterInfrastructureTests", dependencies: ["FocusFilterCore", "FocusFilterInfrastructure"])
    ]
)
