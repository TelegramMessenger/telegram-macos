// swift-tools-version:5.5

import PackageDescription

let deps: [(String, String)] = [
    ("AppAnalytics", "../AppAnalytics"),
    ("TGUIKit", "../TGUIKit"),
    ("ColorPalette", "../ColorPalette"),
    ("KeyboardKey", "../KeyboardKey"),
    ("Localization", "../Localization"),
]

let package = Package(
    name: "CrashRecoveryUI",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "CrashRecoveryUI", targets: ["CrashRecoveryUI"]),
    ],
    dependencies: [
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
    ] + deps.map { .package(name: $0.0, path: $0.1) },
    targets: [
        .target(
            name: "CrashSignalMarker",
            path: "Sources/CrashSignalMarker"),
        .target(
            name: "CrashRecoveryUI",
            dependencies: [
                "CrashSignalMarker",
                .product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
            ] + deps.map { .product(name: $0.0, package: $0.0, condition: nil) },
            path: "Sources/CrashRecoveryUI"),
        .target(
            name: "CrashSignalMarkerTestSupport",
            dependencies: ["CrashSignalMarker"],
            path: "Tests/CrashSignalMarkerTestSupport"),
        .testTarget(
            name: "CrashRecoveryUITests",
            dependencies: ["CrashRecoveryUI", "CrashSignalMarkerTestSupport"],
            path: "Tests/CrashRecoveryUITests"),
    ]
)
