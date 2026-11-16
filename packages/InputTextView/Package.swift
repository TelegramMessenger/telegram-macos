// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "InputTextView",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "InputTextView", targets: ["InputTextView"]),
    ],
    dependencies: [
        .package(name: "AppAnalytics", path: "../AppAnalytics"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "InlineStickerLayer", path: "../InlineStickerLayer"),
        .package(name: "InputView", path: "../InputView"),
        .package(name: "RichTextEditor", path: "../../submodules/telegram-ios/submodules/TelegramUI/Components/RichTextEditor"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "TelegramMedia", path: "../TelegramMedia"),
        .package(name: "Translate", path: "../Translate"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "LocalAnimations", path: "../LocalAnimations"),
    ],
    targets: [
        .target(
            name: "InputTextView",
            dependencies: [
                .product(name: "AppAnalytics", package: "AppAnalytics", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "InlineStickerLayer", package: "InlineStickerLayer", condition: nil),
                .product(name: "RichTextEditorCore", package: "RichTextEditor"),
                .product(name: "InputView", package: "InputView", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "Translate", package: "Translate", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "TelegramUtils", package: "TelegramUtils", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "LocalAnimations", package: "LocalAnimations", condition: nil),
            ],
            path: "Sources/InputTextView"),
    ]
)
