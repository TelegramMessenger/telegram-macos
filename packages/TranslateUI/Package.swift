// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AlertsUI", "../AlertsUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("Translate", "../Translate"),
    ("ObjcUtils", "../ObjcUtils"),
    ("InputView", "../InputView"),
    ("InstantPageUI", "../InstantPageUI"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ChatUI", "../ChatUI"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
]

let package = Package(
    name: "TranslateUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "TranslateUI", targets: ["TranslateUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "RichTextEditor", path: "../../submodules/telegram-ios/submodules/TelegramUI/Components/RichTextEditor"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "TranslateUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "RichTextEditorCore", package: "RichTextEditor", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/TranslateUI"),
    ]
)
