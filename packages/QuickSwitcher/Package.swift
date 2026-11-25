// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("ColorPalette", "../ColorPalette"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AvatarUI", "../AvatarUI"),
    ("KeyboardKey", "../KeyboardKey"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("Strings", "../Strings"),
    ("InAppSettings", "../InAppSettings"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "QuickSwitcher",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "QuickSwitcher", targets: ["QuickSwitcher"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "QuickSwitcher",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/QuickSwitcher"),
    ]
)
