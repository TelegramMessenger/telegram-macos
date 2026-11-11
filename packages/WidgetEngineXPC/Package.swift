// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "WidgetEngineXPC",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "WidgetEngineXPC", targets: ["WidgetEngineXPC"]),
        .library(name: "WidgetEngineServer", targets: ["WidgetEngineServer"]),
    ],
    dependencies: [
        .package(name: "WidgetSandbox", path: "../../third-party/widget-sandbox"),
    ],
    targets: [
        .target(
            name: "WidgetEngineXPC",
            dependencies: [
                .product(name: "WidgetSandbox", package: "WidgetSandbox"),
                .product(name: "WidgetSandboxProtocol", package: "WidgetSandbox"),
            ],
            path: "Sources/WidgetEngineXPC"),
        .target(
            name: "WidgetEngineServer",
            dependencies: [
                "WidgetEngineXPC",
                .product(name: "WidgetSandbox", package: "WidgetSandbox"),
                .product(name: "WidgetSandboxProtocol", package: "WidgetSandbox"),
            ],
            path: "Sources/WidgetEngineServer"),
        .testTarget(
            name: "WidgetEngineXPCTests",
            dependencies: ["WidgetEngineXPC", "WidgetEngineServer", .product(name: "WidgetSandbox", package: "WidgetSandbox")],
            path: "Tests/WidgetEngineXPCTests"),
    ]
)
