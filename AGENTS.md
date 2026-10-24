# AGENTS.md

This file provides guidance to coding agents working with code in this repository.


## Code Style

### Comments
- Do NOT add comments to code except for special markers like `//TODOLANG` (for strings that need localization) or similar task markers
- Code should be self-documenting through clear naming


## Useful Documents
Read the matching document before starting the task.

| Task | Document |
|---|---|
| Creating a new screen or controller | [docs/swift/TemplateController/README.md](docs/swift/TemplateController/README.md), template in [TemplateController.swift](docs/swift/TemplateController/TemplateController.swift) |
| Building locally or changing build settings | [README.md](README.md), [INSTALL.md](INSTALL.md), [XCODE27.md](XCODE27.md) for Xcode 27 compatibility |


## Local Development Builds

Use `scripts/build-local.sh` on macOS with full Xcode. It builds a Debug app without archiving or deploying it.

The script passes `SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG BETA` to every Swift target, including packages. Local Debug builds therefore include beta features such as the app icon picker while retaining Debug behavior and inherited conditions like `SHARE`.

| Command | Purpose |
|---|---|
| `sh scripts/build-local.sh` | Prompt for `arm64`, `x86_64` or `universal`, defaulting to this Mac's architecture |
| `sh scripts/build-local.sh arm64` | Prepare native frameworks and build the app for Apple Silicon |
| `sh scripts/build-local.sh arm64 --app-only` | Rebuild the app using existing native frameworks |
| `sh scripts/build-local.sh arm64 --app-only --dry-run` | Preview the app build command without building or applying compatibility changes |

Replace `arm64` with `x86_64` or `universal` as needed. Prefer `--app-only` for app and Swift changes once native outputs are prepared for the selected architecture. Xcode may still rebuild affected Swift packages and workspace dependencies. Run without `--app-only` when native sources or the required framework architectures change.

Keep `.build/local-<architecture>/DerivedData` for incremental builds. The same directory contains `app.log` and `timings.tsv`; a full run also writes `frameworks.log`. Avoid `clean` or deleting caches as a routine troubleshooting step. The app is at `.build/local-<architecture>/DerivedData/Build/Products/Debug/Telegram.app`.

The script applies Xcode 27 compatibility changes and disables Rust stripping through `CARGO_PROFILE_RELEASE_STRIP=none` and `CARGO_PROFILE_DEV_STRIP=none`. Preserve these settings when changing the build flow. Check the diff before committing: local compatibility changes in project files and submodules are separate from the requested source changes.

### Local Credentials and Signing

- Copy `Telegram-Mac/Local.xcconfig.example` to `Telegram-Mac/Local.xcconfig` if the local file does not exist; preserve an existing file.
- Put personal API credentials, bundle ID and signing team only in the ignored `Local.xcconfig`, using `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_BUNDLE_ID` and `TELEGRAM_TEAM_ID`.
- Keep `DEVELOPMENT_TEAM = $(TELEGRAM_TEAM_ID)` in that file. The app, share extension and app groups use the same identity settings. Local builds require an installed Apple Development certificate for the configured team.
- Do not copy personal values into source files, examples, documentation, tests or commit messages. Inspect the staged diff before committing and keep `Local.xcconfig` untracked.

### Updates in Local Builds

Keep `TELEGRAM_DISABLE_UPDATES=YES` for local builds. The script sets it, and `Local.xcconfig` should include it for builds launched directly from Xcode. It disables checks, downloads, manual update actions, crash recovery updates and installation on quit, and hides the updater UI. Changing the bundle ID or feed alone does not disable updates.

The policy is read from the built app's Info.plist. Source or configuration changes take effect after rebuilding; an already-built or running app retains its previous update behavior. Distribution builds without the local override keep updates enabled.


## Architecture Overview

### Project Structure
- **Telegram-Mac/** - Thin app target: launch and hook installation (`app/`), the concrete `AccountContext` (`account/`), hook installers and bridges (`packages-integration/`), strings (`en.lproj/Localizable.strings`)
- **packages/** - Swift Package Manager modules; almost every feature and UI lives here
- **packages/TGUIKit/** - UI Library
- **TelegramShare/** - Share extension
- **submodules/** - Core libraries and telegram-ios shared code (TelegramCore, Postbox, SSignalKit)
- **core-xprojects/** - Native framework build projects (OpenH264, FFmpeg, WebRTC, etc.)
- **docs/** - Guides and code templates, not part of any target

### Main Modules
Only the modules you will touch most. Find anything else with `grep -rn "func NameController" packages`.

| Module | Use it for |
|---|---|
| `TGUIKit` | Views, `TableView`, `ViewController`, modals, `Window` |
| `TelegramContext` | `AccountContextProtocol`; packages take `any AccountContextProtocol` |
| `Localization` | `strings()`, generated from `Telegram-Mac/en.lproj/Localizable.strings` by `tools/swiftgen.sh` |
| `TelegramTheme` | The `theme` global, `TelegramPresentationTheme`, `deliverOnPrepareQueue` |
| `ColorPalette`, `TelegramIconsTheme` | Palette colors and `theme.icons` |
| `InAppSettings` | App preferences stored in Postbox, `FastSettings` |
| `TelegramUtils` | Telegram helpers shared by many features (formatting, peer status text, `bestWindow`) |
| `FoundationUtils`, `Strings`, `DateUtils`, `ObjcUtils` | Pure helpers with no Telegram UI |
| `TelegramMedia`, `TelegramMediaUtils`, `TelegramMediaResources` | Players, media fetching and saving, media resources |
| `LocalAnimations` | Bundled Lottie animations |
| `InputDataUI` | `InputDataController` list and form screens, `FeatureNavigationHooks` |
| `GeneralRows` | `GeneralRowItem` and the common table rows |
| `AlertsUI` | `alert`, `verifyAlert` |
| `AvatarUI`, `ShortPeerRow`, `SelectPeersUI`, `InputView`, `InlineStickerLayer` | Avatars, peer rows, peer pickers, text input, inline custom emoji |
| `ChatModeTypes`, `ChatHistoryModel`, `MessageUtils`, `MessageTextUtils` | Chat and message model shared by several screens |
| `ChatUI`, `ChatListUI`, `SettingsUI`, `PeerInfoUI` | The big screens: chat, chat list, settings, peer info |
| `PremiumUI`, `StarsUI`, `StoriesUI`, `CallsUI`, `GalleryUI`, `WalletUI`, ... | One `*UI` package per feature screen |

### Adding a Feature
- Add the screen to the package it belongs to; create a new package only for a standalone multi-file feature, copying `packages/GroupsInCommonUI/Package.swift`, then add it to the `Packages` group and link it to the `Telegram` target
- Build screens by following [docs/swift/TemplateController](docs/swift/TemplateController/README.md)
- App-only code (`AccountContext`, app singletons) is reached through a `<Name>Hooks` struct in the package, installed from `Telegram-Mac/packages-integration/hooks/` and `app/main.swift`
- Other features' screens are opened through `FeatureNavigationHooks`, never imported

### Dependencies
- Declare only modules whose symbols you actually use; never add dependencies "just in case"
- No screen package may depend on another screen package; existing ones are debt
- Keep feature code out of hubs (`TGUIKit`, `TelegramTheme`, `TelegramContext`, `Localization`, `TelegramUtils`, `InAppSettings`, `GeneralRows`, `InputDataUI`); a hub API change recompiles ~90 packages
- `*Share` products are for the share extension only

### Moving Code into Packages
- Packages enforce runtime exclusivity (the app has it off), so `inout` access conflicts can trap after a move
- `BETA`/`STABLE`/`ALPHA`/`APP_STORE` are false in packages in Xcode UI builds; `buildbox/build-mac.sh` passes the release channel, and `scripts/build-local.sh` passes `DEBUG BETA`
- App extensions like `Peer.isForum` and `Peer.displayLetters` shadow TelegramCore members; in a package call them through hooks


## Shipping a Beta
A beta build starts when `beta` is pushed to `origin`.
1. Commit all pending work on `beta`, including any submodule bumps (`submodules/telegram-ios` carries the Rust engine)
2. Merge the feature branches being shipped into `beta`, e.g. `git merge origin/sam/new-wallet`
3. Bump the build number: increment `CFBundleVersion` in `Telegram-Mac/Info.plist` and `TelegramShare/Info.plist`, commit as `Bump the build number to <N>`
4. `git push origin beta`
