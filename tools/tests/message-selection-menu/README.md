# Message selection while a context menu is open

Run on macOS with Xcode and the pinned core checkout:

```
python3 tools/tests/message-selection-menu/run.py --revision 35a01826 --expect-bug --scratch-path /tmp/telegram-selection-menu-build --snapshots /tmp/selection-before
python3 tools/tests/message-selection-menu/run.py --scratch-path /tmp/telegram-selection-menu-build --snapshots /tmp/selection-after
```

The runner compiles the complete production `ChatLayerScene.swift` unchanged against native TGUIKit. It dispatches right-click, Control-click, Control-Shift-click, primary click and middle click to a focusable text node in a native Window and opens real TGUIKit context menus. The selected text is rendered by the production TextViewLayer; checks compare first-responder ownership, selection clearing, menu presentation and the local quote callback. Primary click must still acquire focus and clear the previous owner's selection.

The selection owner's `resignFirstResponder` implementation is extracted from SelectManager. Its collection storage and the text-node pointer/menu handler are controlled fixtures. The full ChatLayerTextNode, chat/account state and actual reply composer are not compiled. Quote only records a local string and never sends a message.

Optional captures briefly open a floating fixture window and require macOS screen recording access. Each image shows two steps: a selected-text reference, then the same message after the context click. macOS captures the text and the real floating Quote/Copy menu together inside the fixture's bounds. The footer reports whether the highlight survived and which substring the local Quote callback received. Both palettes and both context-click methods are included.

The first step is an independent native text-layout reference. The second step uses the actual scene dispatcher. Captions, message text, menu contents and the callback footer belong to the fixture; these are not screenshots of a running Telegram client. The Copy item only makes the menu context visible and has no clipboard side effect. No account data is captured.
