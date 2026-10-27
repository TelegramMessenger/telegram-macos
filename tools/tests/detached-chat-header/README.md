# Detached chat and profile headers

Run on macOS with the Xcode toolchain:

```sh
python3 tools/tests/detached-chat-header/run.py
```

The runner extracts `DetachedWindowControlsView` and `DetachedWindowHeaderLayout` from ComponentsUI and compiles it with AppKit. A minimal flipped `NSView` stands in for `TGUIKit.View`; the window and its standard buttons are real AppKit objects.

The seven checks cover repeated attachment, native button dimensions/actions/targets, hit testing, resizing, recovery after AppKit repositions buttons, window-scoped notifications, switching windows, restoration of existing window chrome, deinitialization, repeated chat/profile handoff, and the shared leading-pill geometry and back-button spacing. Full-screen lifecycle checks post notifications; they do not exercise a real Spaces transition.

This harness does not build Telegram, render the glass header, or replace visual verification of a chat opened through **Open in New Window**.

The leading pill keeps a 72-point native-control area and a 40-point back-button target on one surface, with a six-point gap to the rest of the header. Chat and profile views use the same layout values.

To check the profile glass initializer against the actual built TGUIKit implementation, use an unsigned Debug app and its Xcode build log:

```sh
python3 tools/tests/detached-chat-header/profile-construction.py --app-bundle /path/to/Telegram.app --build-log /path/to/xcodebuild.log
```

This extracts the profile's production glass-container expression, links it against `Telegram.debug.dylib`, and repeatedly constructs and resizes the container. It does not launch Telegram or access an account. The build log must contain a ComponentsUI compiler invocation so the probe can reuse the matching module/header search paths. Pass `--revision <git-revision>` to check an earlier version of the expression against the same library.

Below 650 points the detached header uses compact glass controls. At 650 points and wider it returns the buttons to the standard titlebar and restores the original window chrome. The resize check crosses this boundary repeatedly in both directions.

Compact detached profile headers fill the window width with square corners. Their action rows use the same 12-point outer inset as the leading pill. At the standard-layout threshold the profile returns to its centered card and regular action sizing.
