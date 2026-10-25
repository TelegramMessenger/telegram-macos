# Paid send-button checks

Run on macOS with Xcode and the pinned `telegram-ios` checkout available:

```
python3 tools/tests/paid-send-button/run.py --scratch-path /tmp/telegram-paid-send-build
```

Optional `--snapshots /tmp/telegram-paid-send-images` captures ordinary sending and prices 1, 1K and 12.5K beside the emoji action, against light and dark fixture backgrounds. This briefly opens a component window and requires macOS screen recording access. Capture the baseline separately with:

```
python3 tools/tests/paid-send-button/run.py --revision 3cacb03e --captures-only --scratch-path /tmp/telegram-paid-send-build --snapshots /tmp/telegram-paid-send-before
```

Baseline capture compiles that revision's production view and methods; it does not run the assertions for the new layout.

The runner compiles the complete production `StarsSendActionView`, the send button's state/update/sizing/layout methods and the composer's send-slot/placement methods against the real TGUIKit package. It uses the app's star, emoji and plane assets, native text measurement and native mouse events. Checks cover eight prices, four pane widths, centering, matching button/glass geometry, input-space reservation, clicks on both edges and the label, callback routing, price changes and transitions to recording, ordinary send, slow mode and inline loading.

The production field-transition and plane-flight methods also run unchanged, with a hook recording each transition call. Native Core Animation checks compare spring mass/stiffness/damping, duration, start/end scale, blur and fade against ordinary sending, plus the outgoing paid collapse. The source-extracted action-row layout positions the emoji control; checks compare the entire field frame and emoji-to-send gap with ordinary sending. The original 343 checks plus these 106 comparisons total 449 assertions.

Account models, theme/localization, loader content, optional extra actions and the edit-icon morph hook are controlled fixtures. Clicks increment a local counter and never send messages. Captures use a plain field background and a real native LiquidGlassView positioned with the production send-slot geometry. They show settled geometry, not animation playback. They do not show the running client or validate the composer's full Liquid Glass container merge. Full ChatUI/Telegram compilation is outside this focused check.
