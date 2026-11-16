// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FilePanels",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "FilePanels", targets: ["FilePanels"]),
    ],
    dependencies: [
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "AppAnalytics", path: "../AppAnalytics"),
    ],
    targets: [
        .target(
            name: "FilePanels",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "AppAnalytics", package: "AppAnalytics", condition: nil),
            ],
            path: "Sources/FilePanels"),
    ]
)
