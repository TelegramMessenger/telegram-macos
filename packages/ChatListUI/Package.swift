// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("PerfLab", "../PerfLab"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("Strings", "../Strings"),
    ("DateUtils", "../DateUtils"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaResources", "../TelegramMediaResources"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("FetchManager", "../FetchManager"),
    ("Reactions", "../Reactions"),
    ("LocalAnimations", "../LocalAnimations"),
    ("GeneralRows", "../GeneralRows"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("InputDataUI", "../InputDataUI"),
    ("InputView", "../InputView"),
    ("AlertsUI", "../AlertsUI"),
    ("AvatarUI", "../AvatarUI"),
    ("InlineMediaGrid", "../InlineMediaGrid"),
    ("GalleryUI", "../GalleryUI"),
    ("MessageUtils", "../MessageUtils"),
    ("MessageTextUtils", "../MessageTextUtils"),
    ("SceneEffects", "../SceneEffects"),
    ("PremiumStatusUI", "../PremiumStatusUI"),
    ("StarsUI", "../StarsUI"),
    ("PasskeysUI", "../PasskeysUI"),
    ("ProxyUtils", "../ProxyUtils"),
    ("CommunityUI", "../CommunityUI"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("FolderSharingUI", "../FolderSharingUI"),
    ("WebAppUI", "../WebAppUI"),
    ("StoriesUI", "../StoriesUI"),
    ("PeerMediaUI", "../PeerMediaUI"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ChatUI", "../ChatUI"),
    ("InlineStickerLayer", "../InlineStickerLayer"),

]

let package = Package(
    name: "ChatListUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ChatListUI", targets: ["ChatListUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ] + deps.map { .package(name: $0.0, path: $0.1) } + [
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "ThemeSettings", path: "../ThemeSettings"),
        .package(name: "TLottie", path: "../TLottie"),
    ],
    targets: [
        .target(
            name: "ChatListUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/ChatListUI"),
        .testTarget(
            name: "ChatListUITests",
            dependencies: [
                "ChatListUI",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "TelegramMedia", package: "TelegramMedia", condition: nil),
                .product(name: "TLottie", package: "TLottie", condition: nil),
                .product(name: "LocalAnimations", package: "LocalAnimations", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "GeneralRows", package: "GeneralRows", condition: nil),
                .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "ThemeSettings", package: "ThemeSettings", condition: nil),
                .product(name: "MessageTextUtils", package: "MessageTextUtils", condition: nil),
                .product(name: "rnoise", package: "rnoise"),
            ],
            path: "Tests/ChatListUITests"),
    ]
)
