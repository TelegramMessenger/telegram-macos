# Recording editor controls and preview playback

## Latest verification: Send during finalization and real resume, 27 October 2026

On master `e1883098` plus code `1a6e4032`, Send waits for a pending native-writer completion before composing the recording. This prevents a complete first take from being discarded, or the newest resumed segment from being omitted, when Send arrives during pause finalization. Repeated Send requests do not finalize the writer again. Discard, writer failure and obsolete writer callbacks reject late completion.

| Scenario | Before this follow-up | After |
|---|---|---|
| Send during first paused-segment finalization | Stopped with no finished video | One complete 60-second result |
| Send while a resumed segment finishes | Could use only earlier completed segments | Waits for both segments; the test checks 2 + 3 = 5 seconds |
| Resume after trimming 60 seconds to 10 | Old test manually published 10 seconds and could hide a regression | Actual trim/export and resume must publish 10 before recording status |

All **29 focused native tests pass**, including eight actual-pipeline cases. The first new race test failed before the fix on three assertions while the old 22 tests passed. Removing the production duration publication from `resume()` makes the real resume test fail with 60 seconds instead of 10; restoring it returns the final suite to green. The old manually primed resume case was removed.

The pipeline tests instantiate the production class. Only capture setup and writer I/O are controlled; composition, trim/export, pause, stop and resume run in the real implementation with generated local video files. The full Debug arm64 application build and installed signature verification pass. The installed production source matches this code commit by SHA-256; it was built before the commit was created.

The account owner confirmed **Send after 60 seconds** and **continuation after trimming** in that installed client. This is a manual result, separate from deterministic delayed-writer tests. It does not establish how often the race occurs on real hardware. The earlier limit-to-editor, phone playback and camera-off observations remain recorded under the earlier code version below. A separate held-gesture release run and device-disconnect/error paths were not newly confirmed. Local tests do not use a camera, microphone, account or network; no GitHub CI or app-wide performance result is claimed.

Environment: macOS 27.0.1 (26A434), Apple M4 Pro arm64, Xcode 27.1 / Swift 6.4; Telegram Master Test 13.1.0 (283357), Debug arm64. Sending and recording pre-upload were enabled. See `pause_finalization_and_real_resume_review` in [verification.json](verification.json) for source and log hashes. Reproduction commands are below.

Earlier checks are retained below with their original code versions and scope.

## Review at the 60-second limit, 27 October 2026

Reaching the video-message duration limit now pauses recording in the existing editor instead of automatically sending it. The user can play, seek, trim or discard the recording and explicitly choose Send. This is an intentional change to the previous macOS behavior, which submitted the video and closed the recorder at 60 seconds.

This protects users from accidental sends caused by reaching the limit and gives them a chance to trim the video and send only the selected fragment, instead of immediately submitting the entire unedited recording.

The limit requests hands-free mode so releasing the original recording gesture does not submit the video. Record More is disabled while the effective selection remains at the limit; trimming it shorter enables continuation. The pipeline publishes the retained duration on resume so the timer does not immediately react to the old pre-trim duration.

At this earlier stage, all 22 focused native tests passed on master `e1883098` plus code `d33bf763`. A full Debug arm64 application build and strict signature verification also pass. The new controller test failed before the change: one submission callback and one recording reset occurred, with no paused editor. After the fix, the editor opens, submission/reset counts stay zero, and hands-free mode is requested. Additional checks cover 59.99 seconds, repeated limit events and reaching the limit again after a shorter resumed duration. These tests inject duration events into the current production controller compiled with capture/view probes; they do not record a physical minute of footage or access a Telegram account.

Separately, the account owner confirmed ordinary and trimmed video sending and the previous automatic completion behavior in the full unguarded client on master `e1883098` plus the earlier PR code (`3749a4a8`). After installing `d33bf763`, the account owner also confirmed the new limit-to-editor workflow: at 60 seconds no video was sent automatically, the editor allowed Play/Pause and trimming, explicit Send delivered the video for playback on the phone, and the recording window closed with the camera indicator off. This is a user-confirmed manual result; it is not an automated end-to-end run. Record More after trimming, a separate held-gesture release run and hardware-error paths were not independently confirmed in that client check. The newer Record More check is recorded above. See `current_client_sending_validation` and `recording_limit_review` in [verification.json](verification.json).

For a manual check, record in Saved Messages until 60 seconds: no outgoing message should appear, the paused editor should remain usable, and releasing the recording gesture should not send. Check playback and trim boundaries, then explicitly Send or Discard. Confirm delivery/playback after Send and camera/window cleanup after Send or Discard. Also verify that trimming the selection shorter enables Record More. Sending and recording pre-upload remain enabled; the local guard used in earlier checks is excluded from this PR.

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

## Full-client screenshots: PR #82 and PR #92 together

These additional screenshots are from the signed-in Telegram Master Test 13.1.0 (283357) client on current master with both PRs applied. They show the real recording bar, separate from the native fixture comparison above.

### Playing

The Pause control is visible while the selected fragment plays.

![Full client: selected fragment playing](screenshots/client-playing.png)

### Paused

The Play control is visible while the selected fragment is paused.

![Full client: selected fragment paused](screenshots/client-paused.png)

I confirmed that seeking and the playhead stay within the range selected by the left and right trim handles. Both PRs work together: preview images and thumbnails remain normal, both trim boundaries move in both directions, Play/Pause works for the full recording and selected fragment, and repeated No/Discard confirmations allow another recording to start.

## Earlier editor validation

Environment: macOS 27.0.1 (26A434), Apple M4 Pro arm64, Xcode 27.1 / Swift 6.4. Master base for this earlier check: `272d85dd7cc78864549b1d5510a177db79059fc7`.

- All 15 focused native tests pass: six control/trim tests, five synthetic-video playback/lifetime tests and four overlay/modal lifecycle tests.
- A full Debug arm64 application build passes on that base with this editor patch, without the PR #82 optimization.
- The playback-control visibility regression was observed failing before the fix. Both native snapshot cases also check the expected hidden/visible control state.
- The signed-in Master Test 13.1.0 (283357) workflow now also passes on current master `272d85dd7cc78864549b1d5510a177db79059fc7` with PR #82 (`362ca9f6`) and PR #92 (`5add38a4`) together. The full combined build, signature verification and the same 15 native tests pass. Live testing confirms normal preview/thumbnails, both trim boundaries and seeking within the selected range, full/selected Play/Pause, repeated No/Discard confirmations and another recording. The original independent editor test remains recorded separately in `verification.json`.

The full local build uses the repository's Xcode 27 compatibility adjustments and isolated app/profile configuration. Those adjustments are not part of this PR. Recordings were discarded without sending; successful send/upload/export and app-wide performance were not tested. See [verification.json](verification.json) for source hashes, test/build log hashes and the scope of each check.

## Reproduce

Prepare native dependencies using [INSTALL.md](../../../INSTALL.md), and apply [XCODE27.md](../../../XCODE27.md) when using Xcode 27. Run these commands from the repository root:

```sh
python3 tools/tests/recording-editor/run.py --derived-data /tmp/telegram-recording-tests --log /tmp/telegram-recording-tests.log
python3 tools/tests/recording-editor/render-comparison.py --derived-data /tmp/telegram-recording-tests --output /tmp/telegram-recording-comparison
```

The comparison script temporarily swaps the timeline source and adds its fixture to the existing test target, then restores both. Do not edit those files concurrently with the capture. The fixture uses only generated image data and does not access a Telegram account, camera or microphone.


## Camera shutdown regression, 27 October 2026

The pipeline status subscription now survives `viewWillDisappear`, so late completion, discard and failure events can still call `stopCapture()`. The subscription is disposed in `deinit`; preview-player and countdown cleanup are unchanged.

The runner compiles the current modal controller source into a temporary test fixture, replacing only its class name, capture-pipeline type and preview-view type with probes. Controller lifecycle and subscription code are taken from the production file on every run. The probes do not open a camera, microphone or Telegram account. Generated test files are removed when the runner exits; do not edit those fixture paths concurrently.

Before the fix, all three late-terminal-event tests failed while the controller remained retained; the existing 15 editor tests passed. After the one-line fix, all 18 tests pass, including a final rerun on master `605ade9e0e467f88da6de7c209a874a439139e21`. This verifies requests to stop capture before controller deallocation. A full Debug arm64 client build passes on that final master base; the installed client retains the account and opens Saved Messages.

The physical-camera check used an isolated local build with media sending and recording pre-upload disabled; that guard is excluded from this PR. All six observed capture sessions emitted start/running=true followed by stop/running=false. The account owner explicitly confirmed that pausing and discarding a recording closed its window and switched off the camera indicator. UI automation did not expose the separate recorder window, so the pause/discard step was manual. These observations do not measure shutdown latency or establish retained-object lifetime; normal send/upload/export was not validated in the guarded build.

An earlier unguarded automated attempt missed the separate window and reached automatic completion, submitting test videos to Saved Messages. It is not counted as a passing manual-discard test. Subsequent live checks used the local sending guard. See `camera_shutdown_revalidation` in `verification.json`.

The physical camera check ran on `e537320b` plus fix `39b2e335`. Final master `605ade9e` added only password-field and message-copy changes. The recorder controller, capture pipeline, modal preview, recording controls and guarded ChatController were verified byte-identical to the live-tested source. Hardware recording was not repeated after this final unrelated master update.
