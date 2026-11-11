// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("Localization", "../Localization"),
    ("Strings", "../Strings"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("LocalAnimations", "../LocalAnimations"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("InputView", "../InputView"),
    ("InputTextView", "../InputTextView"),
    ("AvatarUI", "../AvatarUI"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AlertsUI", "../AlertsUI"),
    ("PremiumUI", "../PremiumUI"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("StickerSettingsUI", "../StickerSettingsUI"),
    ("ChatUI", "../ChatUI"),
    ("EntertainmentUI", "../EntertainmentUI"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("InviteLinksUI", "../InviteLinksUI"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "ChannelSettingsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ChannelSettingsUI", targets: ["ChannelSettingsUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "ChannelSettingsUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/ChannelSettingsUI"),
    ]
)
