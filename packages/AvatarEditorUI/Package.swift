// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramTheme", "../TelegramTheme"),
    ("Localization", "../Localization"),
    ("TelegramContext", "../TelegramContext"),
    ("AlertsUI", "../AlertsUI"),
    ("ColorPalette", "../ColorPalette"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("ThemeSettings", "../ThemeSettings"),
    ("LocalAnimations", "../LocalAnimations"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("ImageCanvasUI", "../ImageCanvasUI"),
    ("PremiumStatusUI", "../PremiumStatusUI"),
    ("ObjcUtils", "../ObjcUtils"),
]

let package = Package(
    name: "AvatarEditorUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "AvatarEditorUI", targets: ["AvatarEditorUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "libwebp", path: "../../submodules/libwebp"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "AvatarEditorUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "libwebp", package: "libwebp", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/AvatarEditorUI"),
    ]
)
