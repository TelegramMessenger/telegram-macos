// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("Localization", "../Localization"),
    ("Strings", "../Strings"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("ChatUI", "../ChatUI"),
    ("PeerInfoUI", "../PeerInfoUI"),
    ("LocalAnimations", "../LocalAnimations"),
]

let package = Package(
    name: "AboutFeatureUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "AboutFeatureUI", targets: ["AboutFeatureUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "AboutFeatureUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/AboutFeatureUI"),
    ]
)
