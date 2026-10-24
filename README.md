<div align="center">
  <img src="Telegram-Mac/Assets.xcassets/AppIcon.appiconset/Logo_1024.png"
      width="125" 
      height="125">
  
  <h2 align="center">Telegram for macOS</h2>
</div>

![Telegram macOS screenshot](images/tg.png)

[**Telegram**](https://telegram.org) is a messaging app with a focus on speed and security. It’s superfast, simple, and free! This repo contains the official source code for [Telegram for macOS](https://macos.telegram.org/).

## Get it

[![Download on the Mac App Store](images/mas_badge.png)](https://itunes.apple.com/us/app/telegram/id747648890?mt=12)

### Using `mas-cli`

```
mas install 747648890
```

### Manual download

If you would like, you can [download the non-MAS version](https://telegram.org/dl/macos).

You can also [download the beta version](https://telegram.org/dl/macos/beta) if you want to try the latest features and you are prepared for bugs and crashes. If you are running the beta, join the [beta testing chat on Telegram](https://t.me/macswift) to report bugs.

## Contributors

### Contributors on GitHub
See [this repository’s contributors graph](https://github.com/macosswift/telegram/graphs/contributors).

### Bugs and Suggestions
You can report bug or suggestions feature for Telegram for macOS on [Telegram’s Bugs & Suggestions platform](https://bugs.telegram.org). Read [the platform tip](https://bugs.telegram.org/c/746) before creating first card.

### Translations
You can help translate Telegram for macOS on [Telegram’s translations platform](https://translations.telegram.org). Pick your language, then look for the macOS translation set.

<!--### Third-party libraries-->
<!--See [LIBRARIES](LIBRARIES.md).-->

## Permissions
Telegram strives to protect your privacy.  This app asks for as few permissions as possible:

* **Microphone**: You can send voice messages and make audio calls with Telegram.
* **Camera**: You can set your profile picture using your Mac’s iSight camera.
* **Location**: You can send your location to friends.
* **Outgoing network connections**: Telegram needs to connect to the internet to send your messages to your friends.
* **Incoming network connections**: Telegram needs to accept incoming connections for peer-to-peer voice calls.
* **User-selected files**: You can save files or images to your Mac.
* **Downloads folder**: Telegram can automatically download files or images you receive.

## Shortcuts
With [Shortcuts](https://github.com/macosswift/telegram/wiki) you can learn how easy is navigate using your devices.

## License
Telegram for macOS is licensed under the GNU Public License, version 2.0. See [LICENSE](LICENSE) for more information.

## Forking
You can fork this application and make something awesome! Make sure that your fork follows these five requirements:

1. **Do** [get your own API ID](https://core.telegram.org/api/obtaining_api_id).
2. **Don’t** call your fork **Telegram** — or at least make sure your users understand that yours is unofficial.
3. **Don’t** use our standard logo (white paper plane in a blue circle) for your fork.
3. **Do** read and follow our [security guidelines](https://core.telegram.org/mtproto/security_guidelines) to make sure you take good care of your users’ data and protect their privacy.
4. **Do** publish your code. The [GPL license](LICENSE) requires it!

## How to Build

For a local test build, install the prerequisites in [INSTALL.md](INSTALL.md), then copy
`Telegram-Mac/Local.xcconfig.example` to `Telegram-Mac/Local.xcconfig`. Fill in your API ID,
API hash, a unique bundle ID, and the team ID of your installed Apple Development certificate.
The local configuration is ignored by Git. Then run:

```sh
sh scripts/build-local.sh
```

Choose `arm64` (Apple Silicon), `x86_64` (Intel), or `universal`. Press Enter to use this Mac's
architecture. The choice applies to the native libraries and Rust engines as well as the Debug app.
The script signs with your Apple Development certificate. The configured bundle ID and team
are shared by the app, extension and app groups, keeping local data separate from the official app
when you choose a distinct bundle ID.
Local builds disable the app updater, including background downloads, manual update commands,
recovery update actions and installation on quit. The update menu and Settings entry are hidden.
The script applies the Xcode 27 compatibility changes when needed and keeps logs, timings and
DerivedData under `.build/local-<architecture>/`.
It does not archive or deploy the app. The finished app is under `DerivedData/Build/Products/Debug/Telegram.app`.

You can also pass the architecture directly or preview the commands without building:

```sh
sh scripts/build-local.sh arm64
sh scripts/build-local.sh arm64 --dry-run
```

After preparing the native frameworks for an architecture, rebuild just the app with:

```sh
sh scripts/build-local.sh arm64 --app-only
```

`--app-only` skips framework preparation and its tool checks, while keeping the Xcode compatibility
step, local signing, disabled updater, logs and existing DerivedData. It also works with `--dry-run`
and the interactive architecture prompt. Xcode may still rebuild affected Swift packages and workspace
dependencies. Run without `--app-only` when native sources or the required framework architectures change.

Repeated builds reuse compatible native outputs. Changing architectures rebuilds those shared
outputs; the regular framework and release scripts still default to both architectures.
The script checks tools but does not install them. The legacy `setup_build_env.sh` still requests
`openssl@1.1`; use the Homebrew dependency list without that formula, since OpenSSL is built from source.

Quick start (full details, requirements and troubleshooting are in [INSTALL.md](INSTALL.md)):

1. Install Xcode 16 or newer, Homebrew and a Rust toolchain (rustup). On Xcode 27, apply the local changes in
   [XCODE27.md](XCODE27.md) first: it supports macOS 12.0 and newer only, and the project targets 10.13.
2. Clone with submodules:
   ```
   git clone --recurse-submodules https://github.com/macosswift/telegram.git
   ```
3. Prepare the machine and build the native libraries once:
   ```
   sh scripts/setup_build_env.sh --build
   ```
4. Open `Telegram-Mac.xcworkspace` in Xcode and build the `Telegram` scheme.
