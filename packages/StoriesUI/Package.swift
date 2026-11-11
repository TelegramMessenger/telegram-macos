// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("FoundationUtils", "../FoundationUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AlertsUI", "../AlertsUI"),
    ("AvatarUI", "../AvatarUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("AppAnalytics", "../AppAnalytics"),
    ("LocationUI", "../LocationUI"),
    ("ObjcUtils", "../ObjcUtils"),
    ("ChatUI", "../ChatUI"),
    ("InlineMediaGrid", "../InlineMediaGrid"),
    ("ThemeSettings", "../ThemeSettings"),
    ("DateUtils", "../DateUtils"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("InputTextView", "../InputTextView"),
    ("InputView", "../InputView"),
    ("TGModernGrowingTextView", "../TGModernGrowingTextView"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaResources", "../TelegramMediaResources"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("InlineStickers", "../InlineStickers"),
    ("SceneEffects", "../SceneEffects"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("EntertainmentUI", "../EntertainmentUI"),
    ("MediaRecorderUI", "../MediaRecorderUI"),
    ("FilePanels", "../FilePanels"),
    ("TelegramCallsCore", "../TelegramCallsCore"),
    ("StarsUI", "../StarsUI"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("PremiumStatusUI", "../PremiumStatusUI"),
    ("TelegramMediaPlayer", "../../submodules/telegram-ios/submodules/MediaPlayer"),
    ("MessageUtils", "../MessageUtils"),
    ("Strings", "../Strings"),
    ("EmojiReplacements", "../EmojiReplacements"),
    ("RangeSet", "../../submodules/telegram-ios/submodules/Utils/RangeSet"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("PerfLab", "../PerfLab"),
]

let package = Package(
    name: "StoriesUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "StoriesUI", targets: ["StoriesUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "StoriesUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/StoriesUI"),
        .testTarget(
            name: "StoriesUITests",
            dependencies: [
                "StoriesUI",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "AvatarUI", package: "AvatarUI", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "rnoise", package: "rnoise"),
            ],
            path: "Tests/StoriesUITests"),
    ]
)
