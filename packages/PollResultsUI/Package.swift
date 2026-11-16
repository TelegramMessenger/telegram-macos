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
    ("FoundationUtils", "../FoundationUtils"),
    ("AlertsUI", "../AlertsUI"),
    ("InAppSettings", "../InAppSettings"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("StatisticsUI", "../StatisticsUI"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("InputView", "../InputView"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("Strings", "../Strings"),
    ("FilePanels", "../FilePanels"),
    ("LocalAnimations", "../LocalAnimations"),
    ("LocationUI", "../LocationUI"),
    ("GraphCore", "../../submodules/telegram-ios/submodules/GraphCore"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "PollResultsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PollResultsUI", targets: ["PollResultsUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "PollResultsUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/PollResultsUI"),
    ]
)
