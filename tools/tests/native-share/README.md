# Native share tests

Run on macOS with Xcode command-line tools:

```sh
python3 tools/tests/native-share/run.py
```

The runner uses an existing Debug SwiftSignalKit build when available. Otherwise, initialize `submodules/telegram-ios` and its `submodules/SSignalKit` dependency; the runner compiles SwiftSignalKit in a temporary directory.

These tests exercise the production folder-title transformation and folder-refresh signal. They cover UTF-16 ranges, composed characters, overlapping entities, cached and remote folder names, duplicate suppression, and disposal across reopening. Rendering, glass appearance, native extension presentation, and sending require manual testing.
