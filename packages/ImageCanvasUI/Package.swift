// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ImageCanvasUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ImageCanvasUI", targets: ["ImageCanvasUI"]),
    ],
    dependencies: [
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "TelegramMediaPlayer", path: "../../submodules/telegram-ios/submodules/MediaPlayer"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TextRecognizing", path: "../TextRecognizing"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
    ],
    targets: [
        .target(
            name: "ImageCanvasUI",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "TelegramMediaPlayer", package: "TelegramMediaPlayer", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TextRecognizing", package: "TextRecognizing", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
            ],
            path: "Sources/ImageCanvasUI",
            resources: [.copy("Resources/Assets.xcassets")]),
    ]
)
