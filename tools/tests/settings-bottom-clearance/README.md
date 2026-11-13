# Settings bottom-overlay clearance regression

Run on macOS with Python 3 and Xcode command-line tools:

```sh
python3 -I tools/tests/settings-bottom-clearance/run.py
python3 -I tools/tests/settings-bottom-clearance/run.py --revision c64a3ea7
```

The fixed source must pass. The original source must compile and fail assertions about missing Settings clearance, rather than fail compilation. Default temporary output is automatically removed; `--output-dir /absolute/new/directory` retains generated source, binary and module cache and refuses an existing directory.

The runner compiles the exact main-controller overlay method, update-button positioning helper, Settings inset application and base inset storage. It uses native offscreen NSViews for coordinate conversion and hierarchy/intersection checks. Boundary stand-ins replace Telegram controllers, table scroll state and chat overlay layout. Static source checks cover existing resize, visibility/layout and tab-change callbacks, and search-controller initialization.

Cases cover multiple container sizes and translated Settings frames, tabbar visible/hidden, several update-button sizes, visible/hidden/visible transitions, repeated layout without accumulating insets, tab changes, active and later search propagation, detached/nonintersecting views, a raised update control, unloaded Settings, and preservation of the existing chat-overlay routing.

This is not live Telegram UI automation or proof of native table scrolling/animation. No windows are opened, update is not clicked, and no account, application profile or Keychain is accessed. Manual verification should scroll Settings and its search results to the bottom while the update control is visible; the last row should remain reachable above the control. The unrelated chat-list overlap report is outside this fix.
