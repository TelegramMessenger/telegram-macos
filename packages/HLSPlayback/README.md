# HLSPlayback

The native HLS player's core, shared with Telegram iOS: a Foundation-only Swift port of the parts of hls.js 1.7.3 our
streams use (the media-playlist parser, the EWMA bandwidth estimator, ABR with the abandon rule, a buffer model and the
event-driven `HLSPlaybackController`). It replaced hls.js running in JavaScriptCore behind emulated MSE objects.

## Provenance

`Sources/` and `Tests/` are copied unchanged from telegram-ios `submodules/HLSPlayback` at
`15f89745bed6c3d8825d9be5e26ee3713c8006e8`. This includes resumed-open start gates, refreshed bandwidth seeds,
and checked MP4 fragment timing with AAC-LC priming. The deviations from hls.js, failure policy and iOS measurements
are in telegram-ios `docs/native-hls-player.md`.

Do not edit these files here. To update, take the iOS revision and copy both directories again:

```
git -C submodules/telegram-ios fetch origin
git -C submodules/telegram-ios archive <revision> submodules/HLSPlayback/Sources submodules/HLSPlayback/Tests | tar -x -C /tmp/hls
cp /tmp/hls/submodules/HLSPlayback/Sources/*.swift packages/HLSPlayback/Sources/HLSPlayback/
cp -R /tmp/hls/submodules/HLSPlayback/Tests/. packages/HLSPlayback/Tests/HLSPlaybackTests/
python3 tools/tests/hls-playback/run.py
```

`Tests/HLSPlaybackTests/HLSJSGoldens.swift` is hls.js's own output. It is regenerated in telegram-ios
(`submodules/HLSPlayback/Tools/hlsjs-goldens`), never by hand.

## Tests

`python3 tools/tests/hls-playback/run.py` runs this package's suite (`swift test`, warnings as errors) and the
buffered-ranges checks of the macOS view. `swift test --package-path packages/HLSPlayback` runs the suite alone.

## The macOS side

`packages/TelegramMedia` feeds the controller and `ChunkMediaPlayerV2` (through its `.custom` source):

- `Sources/HLSNative/`: the environment over MediaBox (`TelegramEngine.resources`), the part store (the level's init
  plus one segment in a temp file, timed from its MP4 boxes with an FFmpeg fallback), the player source and the playlist loader. Ported from
  telegram-ios `TelegramUniversalVideoContent/Sources/HLSNative/`.
- `HLSVideoNativeContentView`: the gallery's player (`SVideoController`). Its initializer fails when the video has no
  playable quality, and the gallery then plays the original file.
- `HLSVideoContent.qualityKey(keys:initialQuality:)` is the one rule for the preload quality: the chat bubble, the
  media grid and the gallery preload the quality the player starts at. Auto is `HLSLevels.preloadQualityKey` (the
  smallest side of at least 600, else the smallest); a quality the user picked is the nearest available one, and
  the player keeps it as a manual level.

Facts the code depends on that it cannot show:

- Every byte goes through MediaBox's own file context (`fetch`, `rangeData`, `resourceRangesStatus`, `status`), so the
  player joins the preload's in-flight bytes, and disk reads never sample the bandwidth estimate.
- MediaBox turns a range fetch's error into completion: a load whose bytes are still missing a moment after its fetch
  completed has failed, and is retried. Preloads use `fetchedResourceRangeUntilOnDisk` for the same reason.
- A part is the level's init plus one segment, never the bytes between them (a `sidx` there makes FFmpeg report the
  whole video's duration), and ends at the later of its tracks (`HLSPartTiming`).
- `HLSNativePlayerSource` and the part store hop with `DispatchQueue.main.async`, not `Queue.mainQueue().async`, which
  runs inline on main: the player calls the source from inside its own state update.
- `ChunkMediaPlayerV2` draws no frame while paused, so the gallery keeps its frame-step preview.

Logs: `HLSNative` (per video: playlists, disk state, start level, samples, level choices, failures), `HLSStart` (once
per player, at its first frame) and `HLSSession` (once per player, when it goes away).
