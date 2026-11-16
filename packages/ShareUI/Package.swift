// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("KeyboardKey", "../KeyboardKey"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("Strings", "../Strings"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("MessageUtils", "../MessageUtils"),
    ("LocalAnimations", "../LocalAnimations"),
    ("GeneralRows", "../GeneralRows"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("AlertsUI", "../AlertsUI"),
    ("InputView", "../InputView"),
    ("InputTextView", "../InputTextView"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ChatUI", "../ChatUI"),
    ("EntertainmentUI", "../EntertainmentUI"),
    ("ChatListUI", "../ChatListUI"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("InputDataUI", "../InputDataUI"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "ShareUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ShareUI", targets: ["ShareUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "ShareUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/ShareUI"),
        .testTarget(
            name: "ShareUITests",
            dependencies: ["ShareUI", .product(name: "SwiftSignalKit", package: "SSignalKit"), .product(name: "TelegramCore", package: "TelegramCore"), .product(name: "Postbox", package: "Postbox"), .product(name: "rnoise", package: "rnoise")],
            path: "Tests/ShareUITests"),
    ]
)
