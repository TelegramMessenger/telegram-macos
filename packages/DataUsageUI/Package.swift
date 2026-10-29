// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [

    ("TGUIKit", "../TGUIKit"),
    ("InputDataUI", "../InputDataUI"),
    ("GeneralRows", "../GeneralRows"),
    ("Localization", "../Localization"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramTheme", "../TelegramTheme"),
    ("ColorPalette", "../ColorPalette"),
    ("FoundationUtils", "../FoundationUtils"),
    ("AlertsUI", "../AlertsUI"),
    ("InAppSettings", "../InAppSettings"),
    ("LocalAnimations", "../LocalAnimations"),
    ("AvatarUI", "../AvatarUI"),
    ("ProxyUtils", "../ProxyUtils"),
    ("FilePanels", "../FilePanels"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("SystemPermissions", "../SystemPermissions"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("AudioPlayerCore", "../AudioPlayerCore"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("InlineMediaGrid", "../InlineMediaGrid"),
    ("GraphCore", "../../submodules/telegram-ios/submodules/GraphCore"),
]

let package = Package(
    name: "DataUsageUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "DataUsageUI", targets: ["DataUsageUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
        .package(name: "ThemeSettings", path: "../ThemeSettings"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "DataUsageUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/DataUsageUI",
            resources: [.process("Resources/StorageUsageAssets.xcassets")]),
        .testTarget(
            name: "DataUsageUITests",
            dependencies: [
                "DataUsageUI",
                .product(name: "TGUIKit", package: "TGUIKit"),
                .product(name: "GeneralRows", package: "GeneralRows"),
                .product(name: "TelegramTheme", package: "TelegramTheme"),
                .product(name: "ColorPalette", package: "ColorPalette"),
                .product(name: "InAppSettings", package: "InAppSettings"),
                .product(name: "ThemeSettings", package: "ThemeSettings"),
                .product(name: "rnoise", package: "rnoise"),
            ],
            path: "Tests/DataUsageUITests"),
    ]
)
