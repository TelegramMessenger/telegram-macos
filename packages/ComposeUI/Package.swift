// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("AvatarUI", "../AvatarUI"),
    ("GeneralRows", "../GeneralRows"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("InputDataUI", "../InputDataUI"),
    ("TGModernGrowingTextView", "../TGModernGrowingTextView"),
    ("AlertsUI", "../AlertsUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("FilePanels", "../FilePanels"),
    ("AvatarEditorUI", "../AvatarEditorUI"),
    ("PremiumUI", "../PremiumUI"),
    ("InactiveChannelsUI", "../InactiveChannelsUI"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "ComposeUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ComposeUI", targets: ["ComposeUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "ComposeUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/ComposeUI"),
        .testTarget(
            name: "ComposeUITests",
            dependencies: [
                "ComposeUI",
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "rnoise", package: "rnoise", condition: nil),
            ],
            path: "Tests/ComposeUITests"),
    ]
)
