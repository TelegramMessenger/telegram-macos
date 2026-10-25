# Profile gift layout regression checks

Run on macOS with Xcode Command Line Tools:

```sh
python3 tools/tests/profile-gift-layout/run.py
```

The runner compiles the actual `PositionGenerator` declaration from `PeerInfoSpawnEmojiView.swift` and the actual `GiftIconLayer.startAnimations` method from `PeerInfoHeadItem.swift`. It bypasses the rest of the app's dependency graph and supplies plain `CALayer` instances for the sticker and glow layers.

Coverage:

- Identical base positions after recreating the generator and across five fresh processes.
- Stable position prefixes when the number of displayed gifts changes.
- One to six gifts, including six gifts at header widths from 280 pt for the standard 120 pt avatar fixture.
- Symmetric circular slots; bounds, avatar clearance, content exclusions and gift spacing across 252 geometry combinations for each gift count from one to six.
- Geometry equality includes the avatar frame and text/control exclusion rectangles.
- Empty, invalid and fully blocked layouts terminate without placing gifts.
- The existing hover, wiggle and glow animations remain looping, and repeated updates do not restart them.

This is an isolated geometry and Core Animation check. It does not build Telegram, load collectible sticker assets, exercise account data or verify profile scrolling, hit testing and animation timing in a signed-in client. Before upstream review, build the client and capture real Before/After media using the same profile, pinned gift order and window size, including a relaunch.
