// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "CubeUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "CubeUI", targets: ["CubeUI"]),
    ],
    dependencies: [
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "InlineStickerLayer", path: "../InlineStickerLayer"),
        .package(name: "UniqueGiftBackground", path: "../UniqueGiftBackground"),
    ],
    targets: [
        .target(
            name: "CubeUI",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit"),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "InlineStickerLayer", package: "InlineStickerLayer", condition: nil),
                .product(name: "UniqueGiftBackground", package: "UniqueGiftBackground", condition: nil),
            ],
            path: "Sources/CubeUI",
            resources: [.process("Resources/Assets.xcassets")]),
    ]
)
