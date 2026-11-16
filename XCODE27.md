# Building with Xcode 27

Xcode 27 supports macOS **12.0** and newer as a deployment target, but the project targets **10.13**, so the build
fails with:

```
error: The macOS deployment target 'MACOSX_DEPLOYMENT_TARGET' is set to 10.13, but the range of supported deployment target versions is 12.0 to 27.0.x.
```

Make the three changes below to build locally. Do not commit them: the shipped app still supports 10.13.

`scripts/xcode27.sh apply` makes all three changes. `scripts/xcode27.sh revert` undoes only those changes, keeping
any other edits in the same files; run it before you stage any of these files.

## 1. Set the minimum macOS version to 12.0

Set **macOS Deployment Target** (`MACOSX_DEPLOYMENT_TARGET`) to **12.0** for every target in these projects
(target → Build Settings → macOS Deployment Target), or replace every `MACOSX_DEPLOYMENT_TARGET = 10.x;` with
`MACOSX_DEPLOYMENT_TARGET = 12.0;` in their `project.pbxproj`:

- `Telegram.xcodeproj` (Telegram, TelegramShare)
- `submodules/CodeSyntax/CodeSyntax/CodeSyntax.xcodeproj`
- `submodules/Sparkle/Sparkle.xcodeproj`
- Before running `scripts/configure_frameworks.sh`, also the native library projects it builds:
  `core-xprojects/{OpenH264,openssl,libopus,libvpx,Mozjpeg,libwebp,dav1d,ffmpeg,webrtc,tde2e,wallet-engine}/*.xcodeproj`

Swift packages need no change: Xcode 27 builds them for 12.0 anyway. As a result, a green build no longer catches a
missing `@available(macOS 10.15, *)`.

## 2. Keep ImplicitStrongCapture a warning

Swift 6.4 adds the `ImplicitStrongCapture` warning, and `TelegramCore` treats warnings as errors. In
`submodules/telegram-ios/submodules/TelegramCore/Package.swift`, replace
`swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]),` with:

```swift
swiftSettings: [
    .unsafeFlags([
        "-warnings-as-errors",
        "-Wwarning", "ImplicitStrongCapture"
    ])
]),
```

## 3. Let Xcode compile the Metal shaders

Xcode 27 copies `.copy("*.metal")` resources as source instead of compiling them, so the shaders fail to load at
runtime (call screen, dust effect). Delete the `resources: [.copy(...)]` argument from the target in:

- `packages/CallVideoLayer/Package.swift`
- `packages/DustLayer/Package.swift`
- `submodules/telegram-ios/submodules/MetalEngine/Package.swift`

Compiling shaders needs the Metal toolchain. If `xcodebuild -showComponent MetalToolchain` does not report it as
installed, run `xcodebuild -downloadComponent MetalToolchain`.
