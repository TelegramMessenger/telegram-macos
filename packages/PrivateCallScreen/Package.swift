// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let coreLibraries: [(path: String, name: String)] = [
    ("webrtc/build/webrtc", "mac_framework_objc_static"),
    ("openssl/build/openssl/lib", "ssl"),
    ("openssl/build/openssl/lib", "crypto"),
    ("ffmpeg/build/ffmpeg/lib", "avformat"),
    ("ffmpeg/build/ffmpeg/lib", "avcodec"),
    ("ffmpeg/build/ffmpeg/lib", "swresample"),
    ("ffmpeg/build/ffmpeg/lib", "avutil"),
    ("OpenH264/build/output/lib", "openh264"),
    ("libvpx/build/libvpx/lib", "vpx"),
    ("dav1d/build/dav1d/lib", "dav1d"),
    ("libopus/build/libopus/lib", "opus"),
    ("Mozjpeg/build", "jpeg"),
]
let coreXprojects = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../core-xprojects").standardized
let coreLinkerFlags: [String] = coreLibraries.flatMap { ["-L", coreXprojects.appendingPathComponent($0.path).path, "-l\($0.name)"] }

let package = Package(
    name: "PrivateCallScreen",
    platforms: [.macOS(.v10_13)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "PrivateCallScreen",
            targets: ["PrivateCallScreen"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "SSignalKit", path: "../../submodules/telegram-ios/submodules/SSignalKit"),
        .package(name: "TelegramCore", path: "../../submodules/telegram-ios/submodules/TelegramCore"),
        .package(name: "Postbox", path: "../../submodules/telegram-ios/submodules/Postbox"),
        .package(name: "MetalEngine", path: "../../submodules/telegram-ios/submodules/MetalEngine"),
        .package(name: "TGUIKit", path: "../TGUIKit"),
        .package(name: "ColorPalette", path: "../ColorPalette"),
        .package(name: "KeyboardKey", path: "../KeyboardKey"),
        .package(name: "Localization", path: "../Localization"),
        .package(name: "CallVideoLayer", path: "../CallVideoLayer"),
        .package(name: "AppAnalytics", path: "../AppAnalytics"),
        .package(name: "TelegramVoip", path: "../../submodules/telegram-ios/submodules/TelegramVoip"),
        .package(name: "rnoise", path: "../../submodules/telegram-ios/third-party/rnnoise"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "PrivateCallScreen",
            dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit", condition: nil),
                           .product(name: "MetalEngine", package: "MetalEngine", condition: nil),
                           .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                           .product(name: "Postbox", package: "Postbox", condition: nil),
                           .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                           .product(name: "Localization", package: "Localization", condition: nil),
                           .product(name: "KeyboardKey", package: "KeyboardKey", condition: nil),
                           .product(name: "ColorPalette", package: "ColorPalette", condition: nil),
                           .product(name: "CallVideoLayer", package: "CallVideoLayer", condition: nil),
                           .product(name: "AppAnalytics", package: "AppAnalytics", condition: nil)],
            path: "Sources/",
            resources: [.process("Resources/Assets.xcassets")]),
        .testTarget(
            name: "PrivateCallScreenTests",
            dependencies: [
                "PrivateCallScreen",
                .product(name: "TelegramCore", package: "TelegramCore", condition: nil),
                .product(name: "Postbox", package: "Postbox", condition: nil),
                .product(name: "Localization", package: "Localization", condition: nil),
                .product(name: "TGUIKit", package: "TGUIKit", condition: nil),
                .product(name: "CallVideoLayer", package: "CallVideoLayer", condition: nil),
                .product(name: "TelegramVoip", package: "TelegramVoip", condition: nil),
                .product(name: "rnoise", package: "rnoise"),
            ],
            path: "Tests/PrivateCallScreenTests",
            linkerSettings: [
                .unsafeFlags(coreLinkerFlags),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("c++"),
            ]),
    ]
)
