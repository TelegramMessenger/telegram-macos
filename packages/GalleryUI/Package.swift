// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("SecureIdUtils", "../SecureIdUtils"),
    ("TGUIKit", "../TGUIKit"),
    ("KeyboardKey", "../KeyboardKey"),
    ("InstantPageUI", "../InstantPageUI"),
    ("ColorPalette", "../ColorPalette"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("AvatarUI", "../AvatarUI"),
    ("AlertsUI", "../AlertsUI"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("AudioPlayerCore", "../AudioPlayerCore"),
    ("LocalAnimations", "../LocalAnimations"),
    ("MessageUtils", "../MessageUtils"),
    ("ChatModeTypes", "../ChatModeTypes"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ObjcUtils", "../ObjcUtils"),
    ("InAppVideoServices", "../InAppVideoServices"),
    ("TextRecognizing", "../TextRecognizing"),
    ("ExternalVideoUtils", "../ExternalVideoUtils"),
    ("Translate", "../Translate"),
    ("InputTextView", "../InputTextView"),
    ("CaptureExclusion", "../CaptureExclusion"),
    ("FilePanels", "../FilePanels"),
    ("FoundationUtils", "../FoundationUtils"),
    ("RangeSet", "../../submodules/telegram-ios/submodules/Utils/RangeSet"),
    ("TelegramMediaPlayer", "../../submodules/telegram-ios/submodules/MediaPlayer"),
    ("TelegramApi", "../../submodules/telegram-ios/submodules/TelegramApi"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
    ("TelegramMediaResources", "../TelegramMediaResources"),
    ("InputDataUI", "../InputDataUI"),
    ("PerfLab", "../PerfLab"),
    ("AppAnalytics", "../AppAnalytics"),
]

let package = Package(
    name: "GalleryUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "GalleryUI", targets: ["GalleryUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "InputView", path: "../InputView"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "GalleryUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/GalleryUI"),
        .testTarget(
            name: "GalleryUITests",
            dependencies: [
                "GalleryUI",
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "KeyboardKey", package: "KeyboardKey", condition: nil),
                .product(name: "InputView", package: "InputView", condition: nil),
            ],
            path: "Tests/GalleryUITests"),
    ]
)
