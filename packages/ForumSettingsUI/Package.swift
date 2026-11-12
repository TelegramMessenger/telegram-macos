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
    ("AlertsUI", "../AlertsUI"),
    ("InAppSettings", "../InAppSettings"),
    ("LocalAnimations", "../LocalAnimations"),
    ("SidebarUI", "../SidebarUI"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaResources", "../TelegramMediaResources"),
    ("InlineStickers", "../InlineStickers"),
    ("SceneEffects", "../SceneEffects"),
    ("EntertainmentUI", "../EntertainmentUI"),
    ("ChatListUI", "../ChatListUI"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "ForumSettingsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ForumSettingsUI", targets: ["ForumSettingsUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "ForumSettingsUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/ForumSettingsUI"),
    ]
)
