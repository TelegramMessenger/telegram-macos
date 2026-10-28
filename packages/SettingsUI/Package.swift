// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [

    ("AlertsUI", "../AlertsUI"),
    ("AvatarEditorUI", "../AvatarEditorUI"),
    ("AvatarUI", "../AvatarUI"),
    ("CalendarUtils", "../CalendarUtils"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("ColorPalette", "../ColorPalette"),
    ("CurrencyFormat", "../CurrencyFormat"),
    ("EDSunriseSet", "../EDSunriseSet"),
    ("FilePanels", "../FilePanels"),
    ("FoundationUtils", "../FoundationUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InAppSettings", "../InAppSettings"),
    ("InputDataUI", "../InputDataUI"),
    ("InputView", "../InputView"),
    ("KeyboardKey", "../KeyboardKey"),
    ("LocalAnimations", "../LocalAnimations"),
    ("Localization", "../Localization"),
    ("PhoneNumberUtils", "../PhoneNumberUtils"),
    ("PremiumStatusUI", "../PremiumStatusUI"),
    ("ProxyUtils", "../ProxyUtils"),
    ("Reactions", "../Reactions"),
    ("SceneEffects", "../SceneEffects"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("TGModernGrowingTextView", "../TGModernGrowingTextView"),
    ("TGUIKit", "../TGUIKit"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("TelegramLinks", "../TelegramLinks"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramUtils", "../TelegramUtils"),
    ("ThemeSettings", "../ThemeSettings"),
    ("WallpaperUI", "../WallpaperUI"),
    ("SystemPermissions", "../SystemPermissions"),
    ("ApiCredentials", "../ApiCredentials"),
    ("Translate", "../Translate"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
]

let package = Package(
    name: "SettingsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "SettingsUI", targets: ["SettingsUI"]),
        .library(name: "AccountResetSupport", targets: ["AccountResetSupport"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "BuildConfig", path: "../../submodules/BuildConfig"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "SettingsUI",
            dependencies: [
                "AccountResetSupport",
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/SettingsUI"),
        .target(
            name: "AccountResetSupport",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit"),
                .product(name: "TelegramCore", package: "TelegramCore"),
                .product(name: "Postbox", package: "Postbox"),
            ],
            path: "Sources/AccountResetSupport"),
        .testTarget(
            name: "SettingsUIAccountResetTests",
            dependencies: [
                "SettingsUI",
                "AccountResetSupport",
                .product(name: "BuildConfig", package: "BuildConfig"),
                .product(name: "FoundationUtils", package: "FoundationUtils"),
                .product(name: "SwiftSignalKit", package: "SSignalKit"),
                .product(name: "TelegramCore", package: "TelegramCore"),
                .product(name: "Postbox", package: "Postbox"),
                .product(name: "rnoise", package: "rnoise"),
            ],
            path: "Tests/SettingsUIAccountResetTests"),
    ]
)
