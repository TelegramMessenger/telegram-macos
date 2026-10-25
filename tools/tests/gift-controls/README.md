# Collectible-gift header component captures

From the repository root, run on macOS with Xcode and screen recording access:

```
python3 tools/tests/gift-controls/run.py --revision 21f688c0 --scratch-path /tmp/telegram-gift-controls-build --snapshots /tmp/gift-before
python3 tools/tests/gift-controls/run.py --scratch-path /tmp/telegram-gift-controls-build --snapshots /tmp/gift-after
```

The runner compiles the actual collectible-gift More-button styling from the selected source revision against native TGUIKit. Both captures use the same 350-point window, icons, green background and existing Close-button configuration. It briefly opens a component window and uses macOS window capture so the compositor renders the real Liquid Glass effect. The output includes button/effect dimensions for the light and dark palettes.

These are component fixtures, not a running Telegram client or full gift modal. Gift data, account services, modal layout and menu callbacks are outside this check. No production source or account data is changed by the runner.
