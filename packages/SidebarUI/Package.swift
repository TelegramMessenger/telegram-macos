// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "SidebarUI",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "SidebarUI", targets: ["SidebarUI"])],
    dependencies: [
        .package(name: "InputDataUI", path: "../InputDataUI"),
        .package(name: "GeneralRows", path: "../GeneralRows"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "TelegramUtils", path: "../TelegramUtils"),
        .package(name: "InAppSettings", path: "../InAppSettings"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "InputView", path: "../InputView"),
        .package(name: "LocalAnimations", path: "../LocalAnimations"),
        .package(name: "AppAnalytics", path: "../AppAnalytics"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox")
    ],
    targets: [
        .target(name: "SidebarUI", dependencies: [
            .product(name: "InputDataUI", package: "InputDataUI"),
            .product(name: "GeneralRows", package: "GeneralRows"),
            .product(name: "TelegramContext", package: "TelegramContext"),
            .product(name: "TelegramTheme", package: "TelegramTheme"),
            .product(name: "TelegramUtils", package: "TelegramUtils"),
            .product(name: "InAppSettings", package: "InAppSettings"),
            .product(name: "Localization", package: "Localization"),
            .product(name: "TGUIKit", package: "TGUIKit"),
            .product(name: "InputView", package: "InputView"),
            .product(name: "LocalAnimations", package: "LocalAnimations"),
            .product(name: "AppAnalytics", package: "AppAnalytics", condition: nil),
            .product(name: "SwiftSignalKit", package: "SSignalKit"),
            .product(name: "TelegramCore", package: "TelegramCore"),
            .product(name: "Postbox", package: "Postbox")
        ]),
        .testTarget(name: "SidebarUITests", dependencies: ["SidebarUI"])
    ]
)
