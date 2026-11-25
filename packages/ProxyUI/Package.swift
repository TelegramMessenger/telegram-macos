// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "ProxyUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ProxyUI", targets: ["ProxyUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "MtProtoKit", path: "../../submodules/telegram-ios/submodules/MtProtoKit"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "GeneralRows", path: "../GeneralRows"),
        .package(name: "InputDataUI", path: "../InputDataUI"),
        .package(name: "AlertsUI", path: "../AlertsUI"),
        .package(name: "ProxyUtils", path: "../ProxyUtils"),
        .package(name: "QRCodeUtils", path: "../QRCodeUtils"),
        .package(name: "AppAnalytics", path: "../AppAnalytics"),
    ],
    targets: [
        .target(
            name: "ProxyUI",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "MtProtoKit", package: "MtProtoKit", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext", condition: nil),
                .product(name: "GeneralRows", package: "GeneralRows", condition: nil),
                .product(name: "InputDataUI", package: "InputDataUI", condition: nil),
                .product(name: "AlertsUI", package: "AlertsUI", condition: nil),
                .product(name: "ProxyUtils", package: "ProxyUtils", condition: nil),
                .product(name: "QRCodeUtils", package: "QRCodeUtils", condition: nil),
                .product(name: "AppAnalytics", package: "AppAnalytics", condition: nil),
            ],
            path: "Sources/ProxyUI"),
    ]
)
