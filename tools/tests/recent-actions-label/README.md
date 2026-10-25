# Recent Actions label captures

Run from the repository root:

```sh
python3 tools/tests/recent-actions-label/run.py --scratch-path /private/tmp/telegram-label-build --snapshots /private/tmp/recent-actions-label
```

The runner reads the English strings file and extracts the actual TextButton setup/styling from ChannelEventLogView. It builds a small native executable against the real TGUIKit and ColorPalette packages, captures Settings/Filters in the same generic footer, and checks that each title fits the centered button. It also verifies the new localization key/accessor and the existing showFilter callback. The old English key is retained for a matching Before capture.

These are native component captures with generic content, not screenshots of an authenticated Recent Actions screen. Only the button setup/styling and string values come from production code; the surrounding title and event text are fixtures. No filter operations or account settings are changed by the executable. Screen-recording permission is needed for captures.

Validated on macOS 27.0.1 / Xcode 27.1. App version/build: N/A, focused component executable. Full Telegram client compilation and a live-account filter dialog test were not performed.
