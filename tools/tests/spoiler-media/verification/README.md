# Spoiler preview cache verification

Real concealed message photo/video previews, including sensitive-content previews, bypass the shared sharp-image cache and do not satisfy its already-rendered shortcut. Parentless send/rich-editor previews and secret self-destructing media retain the original paths, avoiding repeated decode and empty recycled secret frames.

`python3 tools/tests/spoiler-media/review-tests.py` compiles the production cache policy with controlled parent/media values: six cases and three wiring assertions cover concealed/revealed, parentless, secret, video and sensitive previews. These establish cache routing, not video playback/reveal rendering.

The retained Before/After images come from a separate diagnostic window containing three standalone production ChatInteractiveContentView instances with neutral checkerboard images. It passes parent messages with a grouping key but no grouped row or positionFlags. Reveal directly calls update with isRevealed=true; it does not click the real ink overlay or exercise the chat album reveal flow. The images demonstrate the component cache transition only, not an actual album row or end-to-end reveal. Old labels saying album do not establish album coverage. Sensitive/video/secret rendering and a real grouped-row reveal have not been demonstrated by these captures.

`build-native.py --source-root /path/to/full/checkout --derived-data /path/to/derived-data` clones the supplied source tree into a disposable APFS copy before installing SpoilerMediaHarness and its probe. Hard termination can leave that copy but cannot leave diagnostic writes in the supplied checkout. These diagnostic sources are committed under tools and excluded from shipping target membership. Never use private user media as public evidence.

The diagnostic window now clears its global owner on close, disables release-on-close and weakly captures the launcher interaction. New window/button labels call these isolated previews. The retained screenshots are historical and are not edited to simulate a new test.
