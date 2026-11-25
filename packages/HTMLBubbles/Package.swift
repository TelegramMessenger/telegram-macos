// swift-tools-version:5.5

import PackageDescription
import Foundation

let mozjpegLibraryPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../core-xprojects/Mozjpeg/build").standardized.path

let deps: [(String, String)] = [
    ("TGUIKit", "../TGUIKit"),
    ("TelegramTheme", "../TelegramTheme"),
    ("ColorPalette", "../ColorPalette"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("KeyboardKey", "../KeyboardKey"),
    ("Localization", "../Localization"),
]

let package = Package(
    name: "HTMLBubbles",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "HTMLBubbles", targets: ["HTMLBubbles"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "twidget", path: "../../third-party/twidget"),
        .package(name: "WidgetSandbox", path: "../../third-party/widget-sandbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "HTMLBubbles",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "LiteHTML", package: "twidget", condition: nil),
                .product(name: "HTMLScript", package: "twidget", condition: nil),
                .product(name: "HTML3D", package: "twidget", condition: nil),
                .product(name: "TwidgetRenderer", package: "twidget", condition: nil),
                .product(name: "TwidgetIcons", package: "twidget", condition: nil),
                .product(name: "Twidget3DSandbox", package: "twidget", condition: nil),
                .product(name: "WidgetSandbox", package: "WidgetSandbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/HTMLBubbles",
            resources: [.copy("Resources/lib")]),
        .testTarget(
            name: "HTMLBubblesTests",
            dependencies: [
                "HTMLBubbles",
                .product(name: "TelegramTheme", package: "TelegramTheme", condition: nil),
                .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
            ],
            path: "Tests/HTMLBubblesTests",
            exclude: ["Fixtures"],
            linkerSettings: [.unsafeFlags(["-L" + mozjpegLibraryPath, "-ljpeg"])]),
    ]
)
