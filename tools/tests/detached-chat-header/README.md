# Detached chat and profile headers

Run on macOS with the Xcode toolchain:

```sh
python3 tools/tests/detached-chat-header/run.py
```

The runner extracts `DetachedWindowControlsView` and `DetachedWindowHeaderLayout` from ComponentsUI and compiles it with AppKit. A minimal flipped `NSView` stands in for `TGUIKit.View`; the window and its standard buttons are real AppKit objects.

The eight checks cover repeated attachment, traffic-light hover state, native button dimensions/actions/targets, hit testing, resizing, recovery after AppKit repositions buttons, window-scoped notifications, switching windows, restoration of existing window chrome, deinitialization, repeated chat/profile handoff, and the shared leading-pill geometry and back-button spacing. Full-screen lifecycle checks post notifications; they do not exercise a real Spaces transition.

This harness does not build Telegram, render the glass header, or replace visual verification of a chat opened through **Open in New Window**.

The leading capsule is 120 x 36 points with an 18-point radius, vertically centered on the 40-point header row. The 14-point traffic lights start 11 points in, sit 23 points apart (9-point gaps) and keep 11-point vertical insets. A 1 x 20 divider sits 12 points after the green light, at (83, 8) in the capsule. The 30 x 30 back target starts at (87, 3), leaving 3 points on every side. A six-point gap separates the capsule from the rest of the header. Chat and profile views use the same layout values.

Below 650 points the detached header uses compact glass controls. At 650 points and wider it returns the buttons to the standard titlebar and restores the original window chrome. The resize check crosses this boundary repeatedly in both directions. Chat and profile windows opt out and keep the capsule at every width; the check also covers that opt-out.

Compact detached profile headers fill the window width with square corners. Their action rows use the same 12-point outer inset as the leading pill. At the standard-layout threshold the profile returns to its centered card and regular action sizing.
