// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("Localization", "../Localization"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramTheme", "../TelegramTheme"),
    ("ThemeSettings", "../ThemeSettings"),
    ("ColorPalette", "../ColorPalette"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("LocalAnimations", "../LocalAnimations"),
    ("FilePanels", "../FilePanels"),
    ("UniqueGiftBackground", "../UniqueGiftBackground"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
]

let package = Package(
    name: "QrStudioUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "QrStudioUI", targets: ["QrStudioUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "QrStudioUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/QrStudioUI",
            resources: [.copy("Resources/anim_sun.json"), .copy("Resources/anim_sun_reverse.json"), .copy("Resources/QrStudioNoGifts.tgs")]),
        .testTarget(name: "QrStudioUITests", dependencies: [
            "QrStudioUI",
            .product(name: "rnoise", package: "rnoise"),
            .product(name: "TelegramCore", package: "TelegramCore"),
            .product(name: "Postbox", package: "Postbox"),
        ]),
    ]
)
