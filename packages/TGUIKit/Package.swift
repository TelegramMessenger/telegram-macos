// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TGUIKit",
    platforms: [.macOS(.v10_13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "TGUIKit",
            targets: ["TGUIKit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "KeyboardKey", path: "../KeyboardKey"),
        .package(name: "ObjcUtils", path: "../ObjcUtils"),
        
    ],
    targets: [
        .target(
            name: "TGUIKit",
            dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                           .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                           .product(name: "KeyboardKey", package: "KeyboardKey", condition: nil),
                           .product(name: "ObjcUtils", package: "ObjcUtils", condition: nil),
                          ],
            path: "Sources"),
        .testTarget(
            name: "TGUIKitTests",
            dependencies: ["TGUIKit", .product(name: "ObjcUtils", package: "ObjcUtils"), .product(name: "ColorPalette", package: "ColorPalette")],
            path: "Tests/TGUIKitTests"),
    ]
)
