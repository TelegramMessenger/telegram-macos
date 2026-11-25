// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("InAppSettings", "../InAppSettings"),
    ("ColorPalette", "../ColorPalette"),
    ("ThemeSettings", "../ThemeSettings"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AlertsUI", "../AlertsUI"),
    ("AvatarUI", "../AvatarUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("PremiumStatusUI", "../PremiumStatusUI"),
    ("StarsUI", "../StarsUI"),
    ("WallpaperUI", "../WallpaperUI"),
    ("SceneEffects", "../SceneEffects"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("UniqueGiftBackground", "../UniqueGiftBackground"),
    ("SettingsUI", "../SettingsUI"),
]

let package = Package(
    name: "SelectColorUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "SelectColorUI", targets: ["SelectColorUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "SelectColorUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/SelectColorUI"),
    ]
)
