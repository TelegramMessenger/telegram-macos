// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "FolderSharingUI",
    platforms: [.macOS(.v10_13)],
    products: [.library(name: "FolderSharingUI", targets: ["FolderSharingUI"])],
    dependencies: [
        .package(name: "InputDataUI", path: "../InputDataUI"),
        .package(name: "GeneralRows", path: "../GeneralRows"),
        .package(name: "TelegramContext", path: "../TelegramContext"),
        .package(name: "TelegramTheme", path: "../TelegramTheme"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "AppAnalytics", path: "../AppAnalytics"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox")
    ],
    targets: [
        .target(name: "FolderSharingUI", dependencies: [
            .product(name: "InputDataUI", package: "InputDataUI"),
            .product(name: "GeneralRows", package: "GeneralRows"),
            .product(name: "TelegramContext", package: "TelegramContext"),
            .product(name: "TelegramTheme", package: "TelegramTheme"),
            .product(name: "Localization", package: "Localization"),
            .product(name: "TGUIKit", package: "TGUIKit"),
            .product(name: "AppAnalytics", package: "AppAnalytics"),
            .product(name: "SwiftSignalKit", package: "SSignalKit"),
            .product(name: "TelegramCore", package: "TelegramCore"),
            .product(name: "Postbox", package: "Postbox")
        ]),
        .testTarget(name: "FolderSharingUITests", dependencies: ["FolderSharingUI"])
    ]
)
