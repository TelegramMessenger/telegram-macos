# Back-swipe layout regression

This native fixture builds the complete repository TGUIKit package and invokes the back-swipe closure actually registered by `NavigationViewController` on `Window`. It does not copy or reimplement swipe geometry. Two fixture-only accessors are appended to temporary copies of Window.swift and NavigationViewController.swift so the harness can deliver deterministic swipe states and inspect container frames. Production sources are otherwise unchanged.

The subscriber and profile contents are generic AppKit views, not authenticated Telegram screens. No account data is used. Images and the two-frame GIF show a paused interactive swipe at 78%, followed by the completed transition. The footer reports the returning controller's top edge: before, it changes from 64 pt to 0 pt; after, it stays at 0 pt. The fixture runs the real pop animation before capturing the settled frame. The GIF compares two captured states; it is not a continuous screen recording.

Run from the repository root:

```sh
python3 tools/tests/navigation-swipe/run.py --revision ab4e31a4 --expect-bug --scratch-path /private/tmp/telegram-navigation-build --snapshots /private/tmp/navigation-before
python3 tools/tests/navigation-swipe/run.py --scratch-path /private/tmp/telegram-navigation-build --snapshots /private/tmp/navigation-after
```

Requires Xcode, macOS screen-recording access for native captures, and the SSignalKit submodule. Omit `--snapshots` for checks without screenshots.

Checks cover 360/820 pt widths, 0/44/64/88 pt navigation bars, asymmetric controller insets, real and overlay bars, ordinary and full-slide transitions, five intermediate swipe positions, cancellation, restarting a cancelled swipe, completion, and an additional navigation header with and without visual overflow. The reference frame is recorded from the stable screen before opening the profile. The baseline mode must reproduce the vertical/height mismatch, while the patched mode must preserve the reference layout. With captures, the baseline reports 260 passing reproduction assertions and the patch reports 432 passing assertions. Without captures, the patched run reports 424.

Validation: macOS 27.0.1, Xcode 27.1. App version/build: N/A, component executable compiled from repository source based on master ab4e31a4. This is focused native navigation validation, not a full Telegram client build or a live trackpad test.
