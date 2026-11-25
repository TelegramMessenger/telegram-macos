// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("Localization", "../Localization"),
    ("InAppSettings", "../InAppSettings"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("TelegramCallsCore", "../TelegramCallsCore"),
    ("PrivateCallScreen", "../PrivateCallScreen"),
    ("CallVideoLayer", "../CallVideoLayer"),
    ("AvatarUI", "../AvatarUI"),
    ("AlertsUI", "../AlertsUI"),
    ("SystemPermissions", "../SystemPermissions"),
    ("LocalAnimations", "../LocalAnimations"),
    ("ObjcUtils", "../ObjcUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("DateUtils", "../DateUtils"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("MessageUtils", "../MessageUtils"),
    ("DateSelectorUI", "../DateSelectorUI"),
    ("TgVoipWebrtc", "../../submodules/tgcalls"),
    ("PushToTalk", "../PushToTalk"),
    ("PerfLab", "../PerfLab"),
    ("SceneEffects", "../SceneEffects"),
]

let package = Package(
    name: "CallsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "CallsUI", targets: ["CallsUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TelegramVoip", path: "../../submodules/telegram-ios/submodules/TelegramVoip"),
        .package(name: "Emoji", path: "../../submodules/telegram-ios/submodules/Emoji"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "CallsUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TelegramVoip", package: "TelegramVoip", condition: nil),
                .product(name: "Emoji", package: "Emoji", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/CallsUI",
            swiftSettings: [.unsafeFlags(["-Xcc", "-DWEBRTC_MAC=1"])]),
    ]
)
