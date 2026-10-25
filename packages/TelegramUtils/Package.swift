// swift-tools-version:5.5

import PackageDescription

let common: [Target.Dependency] = [
    .product(name: "FastBlur", package: "FastBlur"),
    .product(name: "Strings", package: "Strings"),
    .product(name: "CalendarUtils", package: "CalendarUtils"),
    .product(name: "DateUtils", package: "DateUtils"),
    .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
    .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
    .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
    .product(name: "Postbox", package: "Postbox", condition: nil),
    .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
    .product(name: "InAppSettings", package: "InAppSettings", condition: nil),
    .product(name: "FoundationUtils", package: "FoundationUtils", condition: nil),
    .product(name: "Localization", package: "Localization", condition: nil),
    .product(name: "libphonenumber", package: "libphonenumber", condition: nil),
    .product(name: "TelegramMediaResources", package: "TelegramMediaResources", condition: nil),
    .product(name: "Mozjpeg", package: "Mozjpeg", condition: nil),
    .product(name: "CurrencyFormat", package: "CurrencyFormat", condition: nil),
]

let package = Package(
    name: "TelegramUtils",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "TelegramUtils", targets: ["TelegramUtils"]),
        .library(name: "TelegramUtilsShare", targets: ["TelegramUtilsShare"]),
    ],
    dependencies: [
        .package(name: "FastBlur", path: "../FastBlur"),
        .package(name: "Strings", path: "../Strings"),
        .package(name: "CalendarUtils", path: "../CalendarUtils"),
        .package(name: "DateUtils", path: "../DateUtils"),
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "InlineStickers", path: "../InlineStickers"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "FoundationUtils", path: "../FoundationUtils"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "libphonenumber", path: "../../submodules/telegram-ios/submodules/libphonenumber"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramMediaResources", path: "../TelegramMediaResources"),
        .package(name: "Mozjpeg", path: "../../submodules/Mozjpeg"),
        .package(name: "CurrencyFormat", path: "../CurrencyFormat"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
    ],
    targets: [
        .target(
            name: "TelegramUtils",
            dependencies: common + [.product(name: "ObjcUtils", package: "ObjcUtils"),
                                    .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                                    .product(name: "InlineStickers", package: "InlineStickers", condition: nil),
                                    .product(name: "TelegramContext", package: "TelegramContext", condition: nil)],
            path: "Sources/TelegramUtils"),
        .target(
            name: "TelegramUtilsShare",
            dependencies: common + [.product(name: "TelegramThemeShare", package: "TelegramTheme", condition: nil),
                                    .product(name: "TelegramContextShare", package: "TelegramContext", condition: nil)],
            path: "Sources/TelegramUtilsShare",
            swiftSettings: [.define("SHARE")]),
        .testTarget(
            name: "TelegramUtilsTests",
            dependencies: ["TelegramUtils"],
            path: "Tests/TelegramUtilsTests"),
    ]
)
