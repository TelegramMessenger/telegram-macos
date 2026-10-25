// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "MessageTextUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "MessageTextUtils", targets: ["MessageTextUtils"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "MessageUtils", path: "../MessageUtils"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "InputView", path: "../InputView"),
        .package(name: "CurrencyFormat", path: "../CurrencyFormat"),
        .package(name: "TGCurrencyFormatter", path: "../TGCurrencyFormatter"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "SecureIdUtils", path: "../SecureIdUtils"),
        .package(name: "InlineStickerLayer", path: "../InlineStickerLayer"),
    ],
    targets: [
        .target(
            name: "MessageTextUtils",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils", condition: nil),
                .product(name: "MessageUtils", package: "MessageUtils", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "InputView", package: "InputView", condition: nil),
                .product(name: "CurrencyFormat", package: "CurrencyFormat", condition: nil),
                .product(name: "TGCurrencyFormatter", package: "TGCurrencyFormatter", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "SecureIdUtils", package: "SecureIdUtils", condition: nil),
                .product(name: "InlineStickerLayer", package: "InlineStickerLayer", condition: nil),
            ],
            path: "Sources/MessageTextUtils"),
        .testTarget(
            name: "MessageTextUtilsTests",
            dependencies: ["MessageTextUtils", .product(name: "TelegramUtils", package: "TelegramUtils")],
            path: "Tests/MessageTextUtilsTests"),
    ]
)
