# Preview close confirmation

Run on macOS with the Xcode Swift toolchain:

```sh
python3 -I tools/tests/preview-close-confirmation/run.py
```

The runner extracts the real close-button callback, close/closeModal methods, pending-action guard and child-confirmation lifecycle into a temporary XCTest package. UI and analytics boundaries use lightweight stand-ins; no Telegram account, GUI interaction or network access is required. Tests exercise modified/unchanged captions, cancel/discard, stale callbacks, sent/closed state and weak ownership. Programmatic post-send closing remains separate.

To keep build output outside the checkout, pass `--output /absolute/new/directory`. Without it, temporary build products are removed when the command exits.

For a negative control, run the same tests against an earlier revision:

```sh
python3 -I tools/tests/preview-close-confirmation/run.py --baseline <revision>
```

That control is expected to fail when the close button bypasses confirmation. These tests do not replace manual AppKit checks of the alert, focus or draft restoration.
