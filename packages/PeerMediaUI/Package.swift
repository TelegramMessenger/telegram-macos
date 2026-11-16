// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("Strings", "../Strings"),
    ("FoundationUtils", "../FoundationUtils"),
    ("ThemeSettings", "../ThemeSettings"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramLinks", "../TelegramLinks"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("TelegramMediaResources", "../TelegramMediaResources"),
    ("MessageUtils", "../MessageUtils"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ChatUI", "../ChatUI"),
    ("AlertsUI", "../AlertsUI"),
    ("AudioPlayerCore", "../AudioPlayerCore"),
    ("GalleryUI", "../GalleryUI"),
    ("GeneralRows", "../GeneralRows"),
    ("InlineMediaGrid", "../InlineMediaGrid"),
    ("InputDataUI", "../InputDataUI"),
    ("FilePanels", "../FilePanels"),
    ("InstantPageUI", "../InstantPageUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("InputView", "../InputView"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "PeerMediaUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PeerMediaUI", targets: ["PeerMediaUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TelegramMediaPlayer", path: "../../submodules/telegram-ios/submodules/MediaPlayer"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "PeerMediaUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "TelegramMediaPlayer", package: "TelegramMediaPlayer", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/PeerMediaUI"),
        .testTarget(
            name: "PeerMediaUITests",
            dependencies: [
                "PeerMediaUI",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "ChatHistoryModel", package: "ChatHistoryModel", condition: nil),
                .product(name: "MessageUtils", package: "MessageUtils", condition: nil),
                .product(name: "rnoise", package: "rnoise"),
            ],
            path: "Tests/PeerMediaUITests"),
    ]
)
