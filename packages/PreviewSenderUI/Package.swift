// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("InAppSettings", "../InAppSettings"),
    ("Localization", "../Localization"),
    ("TelegramTheme", "../TelegramTheme"),
    ("TelegramContext", "../TelegramContext"),
    ("TelegramUtils", "../TelegramUtils"),
    ("TelegramMedia", "../TelegramMedia"),
    ("TelegramMediaResources", "../TelegramMediaResources"),
    ("TelegramMediaUtils", "../TelegramMediaUtils"),
    ("MessageUtils", "../MessageUtils"),
    ("GeneralRows", "../GeneralRows"),
    ("InputDataUI", "../InputDataUI"),
    ("AlertsUI", "../AlertsUI"),
    ("LocalAnimations", "../LocalAnimations"),
    ("FilePanels", "../FilePanels"),
    ("ArchiveUtils", "../ArchiveUtils"),
    ("InlineMediaGrid", "../InlineMediaGrid"),
    ("ImageCanvasUI", "../ImageCanvasUI"),
    ("AvatarEditorUI", "../AvatarEditorUI"),
    ("TGModernGrowingTextView", "../TGModernGrowingTextView"),
    ("InputView", "../InputView"),
    ("InputTextView", "../InputTextView"),
    ("ChatHistoryModel", "../ChatHistoryModel"),
    ("ChatUI", "../ChatUI"),
    ("ShortPeerRow", "../ShortPeerRow"),
    ("Strings", "../Strings"),
    ("InlineStickerLayer", "../InlineStickerLayer"),
]

let package = Package(
    name: "PreviewSenderUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "PreviewSenderUI", targets: ["PreviewSenderUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "PreviewSenderUI",
            dependencies: [
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/PreviewSenderUI",
            sources: [
                "CanCollage.swift",
                "MediaGroupPreviewRowItem.swift",
                "MediaPaidSetterController.swift",
                "MediaPreviewRowItem.swift",
                "PreviewSenderAttachmentEdits.swift",
                "PreviewSenderChildAction.swift",
                "PreviewSenderController.swift",
                "PreviewSenderPendingActions.swift",
                "PreviewSenderUIHooks.swift",
            ]),
    ]
)
