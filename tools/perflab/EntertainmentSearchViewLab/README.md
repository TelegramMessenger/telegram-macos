# Search status view lab

Builds the actual `PanelSearchStatusView` with TGUIKit, without TelegramCore or the main app. `prepare.py` copies the production view and presentation model into the lab. The six AppKit tests cover the single gradient/mask shimmer, lazy duck creation, release when hidden or detached, reduced motion, accessibility labels, and compact layout.

The adjacent EntertainmentSearchLab covers startup, queries, loading/empty/result transitions, spacer-only sticker tables, and the production emoji state equality comparison. Its unrelated equality fields use simple array fixtures; the comparison body is extracted unchanged.

```sh
python3 tools/perflab/EntertainmentSearchViewLab/prepare.py
swift test --package-path tools/perflab/EntertainmentSearchViewLab --scratch-path /tmp/EntertainmentSearchViewLab-build
swift test -c release --package-path tools/perflab/EntertainmentSearchViewLab --scratch-path /tmp/EntertainmentSearchViewLab-release
swift test --sanitize=address --package-path tools/perflab/EntertainmentSearchViewLab --scratch-path /tmp/EntertainmentSearchViewLab-asan
```

## Preview reproduction

The app uses `LottiePlayerView` to play the bundled `duck_empty` animation once at up to 30 fps, or shows one frame with reduced motion. The standalone preview renders frame 20 of that same asset with TLottie and injects the image into the actual status view. The surrounding search header and footer are lab fixtures. These captures verify the view's appearance, not full-app integration or LottiePlayerView playback.

Build the reference renderer into `/tmp`, without changing any submodule files:

```sh
cargo build --manifest-path submodules/tlottie/Cargo.toml --locked --features c-api --target-dir /tmp/EntertainmentSearch-tlottie
python3 tools/perflab/EntertainmentSearchViewLab/render_duck.py /tmp/EntertainmentSearch-tlottie/debug/libtlottie.dylib /tmp/EntertainmentSearch-duck.bgra
swift run --package-path tools/perflab/EntertainmentSearchViewLab --scratch-path /tmp/EntertainmentSearchViewLab-build SearchPreview /tmp/EntertainmentSearch-previews /tmp/EntertainmentSearch-duck.bgra
```

The preview briefly displays its own windows so AppKit creates and draws its layers, then closes them. Validation hashes are in [validation.json](validation.json). Local preview images are saved under `tools/perflab/results/entertainment-search-status-2026-10-15/`; generated images remain outside version control.

The main app was not built. In-app follow-up should exercise empty text searches, category changes, clearing a loading query, GIF pagination, hover opening, and closing/reopening the picker.
