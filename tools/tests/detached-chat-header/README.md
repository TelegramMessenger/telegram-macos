# Detached chat window controls

Run on macOS with the Xcode toolchain:

```sh
python3 tools/tests/detached-chat-header/run.py
```

The runner extracts `DetachedChatWindowControlsView` from the production header source and compiles it with AppKit. A minimal flipped `NSView` stands in for `TGUIKit.View`; the window and its standard buttons are real AppKit objects.

The four checks cover repeated attachment, native button dimensions/actions/targets, hit testing, resizing, recovery after AppKit repositions buttons, window-scoped notifications, switching windows, restoration of existing window chrome, and deinitialization. Full-screen lifecycle checks post notifications; they do not exercise a real Spaces transition.

This harness does not build Telegram, render the glass header, or replace visual verification of a chat opened through **Open in New Window**.
