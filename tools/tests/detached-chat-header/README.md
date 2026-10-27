# Detached chat and profile headers

Run on macOS with the Xcode toolchain:

```sh
python3 tools/tests/detached-chat-header/run.py
```

The runner extracts `DetachedWindowControlsView` and `DetachedWindowHeaderLayout` from ComponentsUI and compiles it with AppKit. A minimal flipped `NSView` stands in for `TGUIKit.View`; the window and its standard buttons are real AppKit objects.

The six checks cover repeated attachment, native button dimensions/actions/targets, hit testing, resizing, recovery after AppKit repositions buttons, window-scoped notifications, switching windows, restoration of existing window chrome, deinitialization, repeated chat/profile handoff, and the shared leading-pill geometry and back-button spacing. Full-screen lifecycle checks post notifications; they do not exercise a real Spaces transition.

This harness does not build Telegram, render the glass header, or replace visual verification of a chat opened through **Open in New Window**.

The leading pill keeps an 80-point native-control area and a 40-point back-button target on one surface, with an eight-point gap to the rest of the header. Chat and profile views use the same layout values.
