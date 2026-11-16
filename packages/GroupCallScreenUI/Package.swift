// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("Localization", "../Localization"),
    ("InAppSettings", "../InAppSettings"),
    ("Strings", "../Strings"),
    ("ObjcUtils", "../ObjcUtils"),
    ("HotKey", "../HotKey"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("TelegramCallsCore", "../TelegramCallsCore"),
    ("CallVideoLayer", "../CallVideoLayer"),
    ("MessageUtils", "../MessageUtils"),
    ("EmojiReplacements", "../EmojiReplacements"),
    ("InlineStickers", "../InlineStickers"),
    ("InputView", "../InputView"),
    ("InputTextView", "../InputTextView"),
    ("SceneEffects", "../SceneEffects"),
    ("LocalAnimations", "../LocalAnimations"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AlertsUI", "../AlertsUI"),
    ("AvatarUI", "../AvatarUI"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("PremiumStatusUI", "../PremiumStatusUI"),
    ("SystemPermissions", "../SystemPermissions"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("InviteLinksUI", "../InviteLinksUI"),
    ("CallsUI", "../CallsUI"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("EntertainmentUI", "../EntertainmentUI"),
    ("TgVoipWebrtc", "../../submodules/tgcalls"),
    ("PushToTalk", "../PushToTalk"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
]

let package = Package(
    name: "GroupCallScreenUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "GroupCallScreenUI", targets: ["GroupCallScreenUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "GroupCallScreenUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/GroupCallScreenUI",
            swiftSettings: [.unsafeFlags(["-Xcc", "-DWEBRTC_MAC=1"])]),
    ]
)
