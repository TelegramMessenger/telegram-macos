// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [

    ("TGUIKit", "../TGUIKit"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramTheme", "../TelegramTheme"),
    ("Localization", "../Localization"),
    ("TelegramContext", "../TelegramContext"),
    ("AvatarUI", "../AvatarUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("AlertsUI", "../AlertsUI"),
    ("DateUtils", "../DateUtils"),
    ("ColorPalette", "../ColorPalette"),
    ("TelegramIconsTheme", "../TelegramIconsTheme"),
    ("ApiCredentials", "../ApiCredentials"),
]

let package = Package(
    name: "SessionsUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "SessionsUI", targets: ["SessionsUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "SessionsUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/SessionsUI"),
    ]
)
