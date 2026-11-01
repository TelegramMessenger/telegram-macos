# Video playback regression tests

Build the Debug `Telegram` scheme with testability enabled, saving the Xcode build
log. Then run the tests against that app's production modules and debug library:

```sh
/usr/bin/python3 tools/tests/video-playback/run.py \
  --build-log .ci-build-logs/local/video-part1.log
```

The default derived-data directory is `.build/Xcode`; use `--derived-data` for a
different location. The log must contain a `TelegramMedia` Swift compilation from
the matching build. The runner reuses its module and header search paths, builds
an XCTest executable under `.build/video-playback-tests`, and runs it without
opening the signed-in app or accessing its account data. Run on macOS 14.4 or
later, with access to VideoToolbox and the window server.

The tests check player routing, decoded video pixels and audio, stream codec and
rotation discovery, capture protection, and moving displayed pixels across a
playback loop. Paused-seek cases exercise both chunked parts and direct readers,
including forward/backward seeks, the final frame, rapid superseding seeks,
clock stability, displayed pixels when the seek reports ready, immediately
resuming when scrubbing ends, and completion with capture protection or a hidden
window. The fixtures contain only FFmpeg-generated test patterns and sine
waves. They have a three-second duration, 128×96 resolution, and ten frames per
second.

To regenerate the fixtures with an FFmpeg executable containing the listed
encoders:

```sh
fixtures=tools/tests/video-playback/fixtures
ffmpeg -f lavfi -i 'testsrc2=size=128x96:rate=10:duration=3' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=3' \
  -c:v libsvtav1 -preset 12 -g 10 -crf 40 -c:a aac -b:a 32k \
  -movflags +faststart "$fixtures/av1.mp4"
ffmpeg -f lavfi -i 'testsrc2=size=128x96:rate=10:duration=3' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=3' \
  -c:v libx264 -preset ultrafast -g 10 -pix_fmt yuv420p -c:a aac -b:a 32k \
  -movflags +faststart "$fixtures/h264.mp4"
ffmpeg -f lavfi -i 'testsrc2=size=128x96:rate=10:duration=3' \
  -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=3' \
  -c:v libx265 -preset ultrafast -x265-params 'keyint=10:log-level=error:pools=1' \
  -tag:v hvc1 -c:a aac -b:a 32k -movflags +faststart "$fixtures/hevc.mp4"
ffmpeg -display_rotation 90 -i "$fixtures/h264.mp4" -c copy \
  "$fixtures/h264-rotated.mp4"
```
