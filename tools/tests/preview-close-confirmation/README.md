# Preview close confirmation

Run on macOS with the Xcode Swift toolchain:

```sh
python3 -I tools/tests/preview-close-confirmation/run.py
```

The runner extracts the real caption-initialization branches and baseline capture, close-button callback, close/closeModal methods, pending-action guard and child-confirmation lifecycle into a temporary XCTest package. UI, input-state storage, attributed-text conversion and analytics boundaries use lightweight stand-ins; no Telegram account, GUI interaction or network access is required. Tests exercise untouched, edited, deleted and reverted prefilled captions, ordinary chat drafts, cancel/discard, stale callbacks, sent/closed state and weak ownership. The displayed caption baseline is separate from temporary draft-restoration state. Programmatic post-send closing remains separate. The initializer boundary executes the extracted production statements, not the complete AppKit controller lifecycle.

To keep build output outside the checkout, pass `--output /absolute/new/directory`. Without it, temporary build products are removed when the command exits.

For a negative control, run the same tests against an earlier revision:

```sh
python3 -I tools/tests/preview-close-confirmation/run.py --baseline <revision>
```

The original pre-fix control fails when the close button bypasses confirmation. Revision `ca991d7e` compiles but fails the prefilled-caption regressions: untouched/reverted captions incorrectly prompt, while deleting a supplied caption incorrectly closes directly. These tests do not replace manual AppKit checks of the alert, focus, formatting conversion or draft restoration.
