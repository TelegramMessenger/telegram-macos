// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "RevealOptions",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "RevealOptions", targets: ["RevealOptions"]),
    ],
    dependencies: [
        .package(name: "TGUIKit", path: "../TGUIKit"),
    ],
    targets: [
        .target(
            name: "RevealOptions",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
            ],
            path: "Sources/RevealOptions"),
        .testTarget(
            name: "RevealOptionsTests",
            dependencies: [
                "RevealOptions",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
            ],
            path: "Tests/RevealOptionsTests"),
    ]
)
