// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("Strings", "../Strings"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("LocalAnimations", "../LocalAnimations"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ChatUI", "../ChatUI"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AlertsUI", "../AlertsUI"),
    ("SelectPeersUI", "../SelectPeersUI"),

]

let package = Package(
    name: "PeerModerationUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PeerModerationUI", targets: ["PeerModerationUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "PeerModerationUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/PeerModerationUI"),
        .testTarget(
            name: "PeerModerationUITests",
            dependencies: [
                "PeerModerationUI",
                .product(name: "TGUIKit", package: "TGUIKit"),
                .product(name: "ChatUI", package: "ChatUI"),
                .product(name: "TelegramCore", package: "TelegramCore"),
                .product(name: "Postbox", package: "Postbox"),
                .product(name: "SwiftSignalKit", package: "SSignalKit"),
            ],
            path: "Tests/PeerModerationUITests"),
    ]
)
