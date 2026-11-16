// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("InputDataUI", "../InputDataUI"),
    ("GeneralRows", "../GeneralRows"),
    ("AlertsUI", "../AlertsUI"),
    ("FilePanels", "../FilePanels"),
    ("MessageTextUtils", "../MessageTextUtils"),
    ("MtProtoKit", "../../submodules/telegram-ios/submodules/MtProtoKit"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "ChatExportUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ChatExportUI", targets: ["ChatExportUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "ChatExportUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/ChatExportUI"),
    ]
)
