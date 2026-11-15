// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("PhoneNumberUtils", "../PhoneNumberUtils"),
    ("TelegramTheme", "../TelegramTheme"),
    ("Localization", "../Localization"),
]

let package = Package(
    name: "PhoneInputUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PhoneInputUI", targets: ["PhoneInputUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "PhoneInputUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/PhoneInputUI"),
        .testTarget(
            name: "PhoneInputUITests",
            dependencies: [
                "PhoneInputUI",
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
            ],
            path: "Tests/PhoneInputUITests"),
    ]
)
