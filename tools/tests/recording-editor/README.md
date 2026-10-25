# Recording editor controls and preview playback

## Change

Paused video recordings now accept both trim handles, timeline seeking and Play/Pause. The selected fragment stops at its end and can be replayed. Discard/resume confirmations yield pointer events, cannot open twice, and cannot bring back a dismissed recording overlay.

The floating recording controls previously lived in a child window above the editor. That window could intercept the right trim handle. Editor controls now share the overlay window and sit above the floating controls, with coordinates converted through screen space when crossing windows.

Video timeline actions previously reached only the audio preview player. They now reach the video player, publish position/playback state, retain seeks until the player is ready, and reject stale seek completions. Closing the preview removes its observers and stops playback. A bounded cleanup path handles missing animation callbacks.

This patch does not implement dictation. It is independent of [PR #82](https://github.com/TelegramMessenger/telegram-macos/pull/82), which removes an unused bitmap from thumbnail preparation in the same recording-preview flow. The editor failures reproduced with and without that optimization.

## Before and after

These are captures of the real AppKit timeline component with a generated placeholder: a 10-second recording, a 2–8 second selection and position at 4 seconds. They are native fixture captures, not screenshots of a signed-in client. The comparison script switches only the timeline component to the unchanged master implementation for Before.

### Before

The video timeline hides its playback control and has no video position indicator.

![Before: video timeline without Play/Pause](screenshots/before.png)

### After

The same selection shows Play/Pause, its six-second duration and the video position indicator.

![After: video timeline with Play/Pause and position](screenshots/after.png)

The images demonstrate the visible timeline change. Pointer routing, seeking, playback boundaries and dismissal are checked separately by the tests and manual workflow below.

## Validation

Environment: macOS 27.0.1 (26A434), Apple M4 Pro arm64, Xcode 27.1 / Swift 6.4. Current master base: `272d85dd7cc78864549b1d5510a177db79059fc7`.

- All 15 focused native tests pass: six control/trim tests, five synthetic-video playback/lifetime tests and four overlay/modal lifecycle tests.
- A full Debug arm64 application build passes on that base with this editor patch, without the PR #82 optimization.
- The playback-control visibility regression was observed failing before the fix. Both native snapshot cases also check the expected hidden/visible control state.
- The signed-in Master Test 13.1.0 (283357) workflow passed: both trim boundaries and seeking, full/selected Play/Pause, repeated editing with No twice, Discard, and another recording. That runtime test used source base `cdf97a0e316521c72bd606bfb8002487d8fc842c`; all affected feature source files are byte-identical to this patch. The latest master was rebuilt and tested natively, rather than claiming that older account test ran on the new build.

The full local build uses the repository's Xcode 27 compatibility adjustments and isolated app/profile configuration. Those adjustments are not part of this PR. Recordings were discarded without sending; successful send/upload/export and app-wide performance were not tested. See [verification.json](verification.json) for source hashes, test/build log hashes and the scope of each check.

## Reproduce

Prepare native dependencies using [INSTALL.md](../../../INSTALL.md), and apply [XCODE27.md](../../../XCODE27.md) when using Xcode 27. Run these commands from the repository root:

```sh
python3 tools/tests/recording-editor/run.py --derived-data /tmp/telegram-recording-tests --log /tmp/telegram-recording-tests.log
python3 tools/tests/recording-editor/render-comparison.py --derived-data /tmp/telegram-recording-tests --output /tmp/telegram-recording-comparison
```

The comparison script temporarily swaps the timeline source and adds its fixture to the existing test target, then restores both. Do not edit those files concurrently with the capture. The fixture uses only generated image data and does not access a Telegram account, camera or microphone.
