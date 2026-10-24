# Paid send-button checks

Run on macOS with Xcode and the pinned `telegram-ios` checkout available:

```
python3 tools/tests/paid-send-button/run.py --scratch-path /tmp/telegram-paid-send-build
```

Optional `--snapshots /tmp/telegram-paid-send-images` renders prices 1, 1K and 12.5K against light and dark fixture backgrounds.

The runner compiles the complete production `StarsSendActionView`, the send button's state/update/sizing/layout methods and the composer's send-slot/placement methods against the real TGUIKit package. It uses the app's star asset, native text measurement and native mouse events. Checks cover eight prices, four pane widths, centering, matching button/glass geometry, input-space reservation, clicks on both edges and the label, callback routing, price changes and transitions to recording, ordinary send, slow mode and inline loading.

Account models, theme/localization, loader content and animation hooks are controlled fixtures. Clicks increment a local counter and never send messages. The optional renders use a plain field background; they do not show the running client or validate Liquid Glass composition. Full ChatUI/Telegram compilation is outside this focused check.
