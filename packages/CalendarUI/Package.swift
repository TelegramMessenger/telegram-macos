// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "CalendarUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "CalendarUI", targets: ["CalendarUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "GeneralRows", path: "../GeneralRows"),
        .package(name: "CalendarUtils", path: "../CalendarUtils"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramMediaUtils", path: "../TelegramMediaUtils"),
        .package(name: "AlertsUI", path: "../AlertsUI"),
    ],
    targets: [
        .target(
            name: "CalendarUI",
            dependencies: [
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "GeneralRows", package: "GeneralRows", condition: nil),
                .product(name: "CalendarUtils", package: "CalendarUtils", condition: nil),
                .product(name: "TelegramContext", package: "TelegramContext"),
                .product(name: "TelegramMediaUtils", package: "TelegramMediaUtils"),
                .product(name: "AlertsUI", package: "AlertsUI"),
            ],
            path: "Sources/CalendarUI"),
    ]
)
