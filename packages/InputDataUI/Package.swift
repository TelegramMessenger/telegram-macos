// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "InputDataUI",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "InputDataUI", targets: ["InputDataUI"])],
    dependencies: [
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "GeneralRows", path: "../GeneralRows"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "SecureIdUtils", path: "../SecureIdUtils"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "AppAnalytics", path: "../AppAnalytics"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGModernGrowingTextView", path: "../TGModernGrowingTextView"),
        .package(name: "CalendarUtils", path: "../CalendarUtils"),
        .package(name: "KeyboardKey", path: "../KeyboardKey"),
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "ThemeSettings", path: "../ThemeSettings"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ],
    targets: [
        .target(name: "InputDataUI", dependencies: [
            .product(name: "ColorPalette", package: "ColorPalette"),
            .product(name: "GeneralRows", package: "GeneralRows"),
            .product(name: "TelegramContext", package: "TelegramContext"),
            .product(name: "TelegramTheme", package: "TelegramTheme"),
            .product(name: "TelegramUtils", package: "TelegramUtils"),
            .product(name: "SecureIdUtils", package: "SecureIdUtils"),
            .product(name: "Localization", package: "Localization"),
            .product(name: "TGUIKit", package: "TGUIKit"),
            .product(name: "SwiftSignalKit", package: "SSignalKit"),
            .product(name: "TelegramCore", package: "TelegramCore"),
            .product(name: "Postbox", package: "Postbox"),
            .product(name: "TGModernGrowingTextView", package: "TGModernGrowingTextView"),
            .product(name: "CalendarUtils", package: "CalendarUtils"),
            .product(name: "KeyboardKey", package: "KeyboardKey"),
            .product(name: "ObjcUtils", package: "ObjcUtils"),
            .product(name: "AppAnalytics", package: "AppAnalytics"),
        ]),
        .testTarget(name: "InputDataUITests", dependencies: [
            "InputDataUI",
            .product(name: "TGUIKit", package: "TGUIKit"),
            .product(name: "GeneralRows", package: "GeneralRows"),
            .product(name: "TelegramTheme", package: "TelegramTheme"),
            .product(name: "ColorPalette", package: "ColorPalette"),
            .product(name: "InAppSettings", package: "InAppSettings"),
            .product(name: "ThemeSettings", package: "ThemeSettings"),
            .product(name: "rnoise", package: "rnoise"),
        ])
    ]
)
