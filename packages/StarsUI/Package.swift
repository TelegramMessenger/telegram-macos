// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("UniqueGiftBackground", "../UniqueGiftBackground"),
    ("PerfLab", "../PerfLab"),
    ("ColorPalette", "../ColorPalette"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AvatarUI", "../AvatarUI"),
    ("AlertsUI", "../AlertsUI"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("LocalAnimations", "../LocalAnimations"),
    ("CurrencyFormat", "../CurrencyFormat"),
    ("PremiumStatusUI", "../PremiumStatusUI"),
    ("SceneEffects", "../SceneEffects"),
    ("DustLayer", "../DustLayer"),
    ("InAppPurchaseManager", "../InAppPurchaseManager"),
    ("ObjcUtils", "../ObjcUtils"),
    ("PremiumUI", "../PremiumUI"),
    ("CalendarUtils", "../CalendarUtils"),
    ("DateUtils", "../DateUtils"),
    ("LokiRng", "../../submodules/telegram-ios/submodules/Utils/LokiRng"),
    ("FoundationUtils", "../FoundationUtils"),
    ("InputTextView", "../InputTextView"),
    ("InputView", "../InputView"),
    ("SelectPeersUI", "../SelectPeersUI"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("CalendarUI", "../CalendarUI"),
    ("MessageUtils", "../MessageUtils"),

]

let package = Package(
    name: "StarsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "StarsUI", targets: ["StarsUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "StarsUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/StarsUI"),
        .testTarget(
            name: "StarsUITests",
            dependencies: [
                "StarsUI",
                .product(name: "TGUIKit", package: "TGUIKit"),
                .product(name: "TelegramCore", package: "TelegramCore"),
                .product(name: "Postbox", package: "Postbox"),
                .product(name: "Localization", package: "Localization"),
                .product(name: "LocalAnimations", package: "LocalAnimations"),
            ],
            path: "Tests/StarsUITests"),
    ]
)
