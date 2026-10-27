# Remove the discarded full-size bitmap from blurred video previews

## Change and benefit

`CGImage.blurred` already returns the image from its small, aspect-fitted thumbnail context. Before returning it, the original implementation creates a second context at the input pixel size multiplied by the screen scale, draws the small blurred image into it, and discards that full-size result.

The fix removes that unused context and drawing operation: **one production file, ten deleted lines, zero added lines**. The small-context rendering, FastBlur invocation and returned image remain unchanged. There is no new cache, state, API or dependency.

The operation is used when the video recorder receives its first thumbnail, and when the recording trim scrubber displays placeholder thumbnails. The recorder's `.madeThumbnail` notification is delivered on the main queue before `saveThumbnail` calls `.blurred`. Its pipeline requests 500×500 buffers, but the actual camera/renderer dimensions depend on the device; the benchmark dimensions are controlled inputs, not measurements of a live camera. The scrubber computes one blurred image and repeats it across placeholder cells; the operation is not performed separately for every cell or on every video frame.

For an input of 500×500 at backing scale 2×, native bitmap allocations fall from **4,011,200 to 11,200 bytes** per call. The removed full-size canvas accounts for 4,000,000 bytes; the remaining 11,200-byte thumbnail has 32-byte-aligned rows. At 720×720 / 2×, the removed canvas is 8,294,400 bytes. These are recorded `DrawingContext.length` values from real native contexts, not a claim about persistent Telegram memory.

## Release comparison

Baseline: `deffa9c1926317a9d66a0d41bd9b1de8fcb7ca7d`. Environment: Mac16,8 arm64, 24 GiB RAM, macOS 27.0.1 (26A434), Xcode 27.1, Apple Swift 6.4. The benchmark builds the full real TGUIKit package, its native dependencies, FastBlur and the complete production `CGImageExtensions.swift` file. There are no fixture replacements for DrawingContext, CoreGraphics, FastBlur, scale handling or graphics settings.

There are **288 fresh-process measurements**: twelve input/scale configurations, two variants, twelve repetitions. Each configuration runs baseline first six times and current first six times. Each process generates one opaque deterministic source image, records its first helper invocation, performs five warmup calls, then times 100 calls with autorelease pools. Source-image generation is outside the CPU/event timing loop. No other builds or test suites ran during the matrix.

Both variants use the same executable and optimization boundary. The baseline property is extracted from the pinned Git source and renamed `referenceBlurred`; the current property comes from the unmodified production file. The benchmark uses neither allocation recording nor instrumented constructors. The retained last output is checked after timing so the result is consumed.

| Input / backing scale | CPU for 100 calls, before → after | Per-call p95, before → after | Process RSS high-water mark, before → after |
| --- | ---: | ---: | ---: |
| 50×50 / 1× | 1.173 → 0.806 ms | 13.958 → 10.084 µs | 10.359 → 10.305 MiB |
| 500×500 / 1× | 17.095 → 0.799 ms | 206.041 → 8.604 µs | 15.445 → 12.273 MiB |
| 500×500 / 2× | 84.736 → 0.975 ms | 1063.271 → 11.688 µs | 35.656 → 12.211 MiB |
| 720×720 / 2× | 175.468 → 0.919 ms | 2079.938 → 10.292 µs | 62.438 → 14.289 MiB |
| 1920×1080 / 2× | 709.612 → 0.662 ms | 7516.166 → 7.979 µs | 58.516 → 26.172 MiB |

For the configured 500×500 / 2× case, median CPU for the helper falls **98.8%**, from approximately 0.847 ms to 0.00975 ms per warm call. Median per-process p95 falls from about **1.063 ms to 0.0117 ms**. The first invocation in each fresh process falls from a median 1.045 ms to 0.194 ms; this is not an application startup measurement.

All twelve configurations improve: the smallest 50×50 / 1× control uses 31.2% less median CPU. In every configuration, the largest measured current CPU total is below the smallest baseline total. For 500×500 / 2×, the ranges are 83.367–86.909 ms versus 0.871–1.074 ms for 100 calls. All p95 medians are lower. The larger inputs show the cost of the removed size-dependent operation; 1920×1080 / 2× is a stress case, not a claimed normal camera size.

RSS is the process's resident-set high-water mark captured with `getrusage` through the end of the render loop. It includes native framework state, fixture construction, the first invocation, warmup and allocator behavior. `task_vm_info.phys_footprint` is also saved before/after the measured loop; those are endpoints, not peak physical footprint. RSS reductions must not be attributed solely to the explicit canvas or presented as steady-state memory savings for the Telegram application. All memory samples are positive; raw values, ranges and exact native canvas sizes are saved separately.

## Correctness

Before the production edit, the resource regression fails: the largest native canvas is 4,000,000 bytes against a thumbnail budget of 11,200 bytes. After deleting the unused block, **six tests pass in Debug, Release and Address Sanitizer**:

- Native resource budget and allocation comparison across twelve input/scale configurations.
- Exact active pixel bytes and image metadata for 42 opaque input configurations: seven sizes, three source color spaces, backing scales 1× and 2×. Every configuration also compares baseline against itself to detect unstable references.
- Lazy JPEG decoding at both backing scales.
- Returned pixels remain valid after the source image and autorelease pool are released.
- `NSGraphicsContext.current` remains unchanged for both baseline and current.

Image metadata checks include dimensions, row stride, bits per component/pixel, alpha information, bitmap information, interpolation and color space. Unused row-padding bytes are excluded from pixel comparison. The explicit fixture matrix covers opaque images with dimensions at least 50 pixels; it does not establish behavior for arbitrary transparent or tiny inputs.

All **144 measurement pairs** have equal output dimensions and active-pixel checksums. No visible change is expected. The returned `CGImage` retains the small context's `CGDataProvider`; the unused full-size context was a separate owner and buffer. Removing it does not shorten the lifetime of the returned pixels.

Allocation tests compile a separate `TrackedBlur` copy whose only transformation is replacing `DrawingContext(size:` calls with a recorder function. That function creates and returns a real `TGUIKit.DrawingContext` and records its actual `length`. Performance tests use `NativeBlur`, with no such transformation. Tests are serial because native screen scale and graphics-context settings are process globals.

Address Sanitizer uses `ASAN_OPTIONS=detect_leaks=0` for address/lifetime validation; this is not a leak-free claim. The complete helper source and full TGUIKit compile in the standalone native package. The initial benchmark did not build or run the full Telegram application; subsequent client testing is described below. The performance measurements demonstrate lower helper CPU and transient allocation, not an improvement in overall application speed, FPS, battery or total application memory.

## Full-client follow-up and current master, 26 October 2026

I tested the exact production helper from this PR in a full local Debug arm64 client, Telegram Master Test 13.1.0 (283357), on macOS 27.0.1 (26A434), Apple M4 Pro. The client was based on `cdf97a0e316521c72bd606bfb8002487d8fc842c`. I compared it with a control build on the same profile; only `CGImageExtensions.swift` differed between those two variants.

I recorded video messages, opened the paused preview, checked the video image and initial trim thumbnails, and discarded the recordings without sending. Images and thumbnails looked the same in both variants, without black or empty frames. A runtime breakpoint observed the helper five times from `VideoRecorderModalController` and three times from `RecordingTrimScrubberView`; it was removed before control-build testing. This establishes that both callers were exercised, not a performance improvement in the client.

The right trim handle and timeline seeking failed in both variants. These controls are not changed by this PR, and the complete trimming workflow must not be reported as passing for either comparison build. Separate local recording-editor fixes were subsequently tested successfully; they are outside this PR. The later editor test does not replace the controlled before/after preview comparison.

I also checked current upstream master `272d85dd7cc78864549b1d5510a177db79059fc7`. The PR merges without conflicts, and the original helper and both caller files are unchanged from the full-client test base. All six native tests pass again in Debug, Release and Address Sanitizer using the helper and real TGUIKit/native dependencies exported from the merged source tree. The 288 original benchmark samples and all summary statistics were independently rechecked, including all 144 matching output pairs. The original measurements remain the results of the initial benchmark, rather than a new full-client performance measurement.

I subsequently rebuilt the full Debug arm64 client from current master `272d85dd7cc78864549b1d5510a177db79059fc7` with the exact production helper from PR head `302047c182b9fffae0c57bfb37679dde0d2f6b7c`, excluding the separate local editor fixes. The build and ad-hoc signature verification passed. The existing account and chats remained available, and I confirmed normal video preview and initial timeline thumbnails. The requested scenario was an 8–10 second locked recording, pause, inspect, discard without sending and repeat. This supersedes the earlier limitation about not rebuilding the full client from current master.

The full-client check used the prepared local source tree with Xcode 27 compatibility and isolated app/profile configuration, not an official beta binary. It does not establish a successful send/upload/export, app-wide performance improvement or leak-free result. There are no GitHub Actions workflows or reported CI statuses for this PR at this check; the passing checks above are local. Structured follow-up evidence is in [revalidation.json](Results/revalidation.json); the original measurement files remain unchanged.

### Combined full-client test with PR #92

I also tested PR #82 (`362ca9f6`) and [PR #92](https://github.com/TelegramMessenger/telegram-macos/pull/92) (`5add38a4`) together on master `272d85dd`. The combined full Debug arm64 build, signature verification and all 15 editor tests pass. The signed-in workflow passes: normal video preview/thumbnails, both trim handles, seeking and a playhead constrained to the selected range, full/selected Play/Pause, repeated No/Discard confirmations and another recording. Additional real-client screenshots are included with #92. This is functional integration validation, not a new performance measurement; the original standalone checks remain valid.

## Reproduce

From this checkout, initialize telegram-ios according to the repository instructions, or supply a path to an existing telegram-ios Git checkout. The generator reads SwiftSignalKit from the exact pinned Git commit, ignoring local changes in that checkout. All generated packages and build products stay in the chosen output directory.

```sh
python3 tools/perflab/BlurredPreviewLab/prepare.py /tmp/telegram-blur-lab --telegram-ios-source /absolute/path/to/telegram-ios
swift test --package-path /tmp/telegram-blur-lab --jobs 4
swift test --package-path /tmp/telegram-blur-lab -c release --jobs 4
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/telegram-blur-lab --scratch-path /tmp/telegram-blur-asan --sanitize address --jobs 4
python3 tools/perflab/BlurredPreviewLab/measure.py /tmp/telegram-blur-lab /tmp/telegram-blur-results --repetitions 12 --iterations 100
```

Run measurements only after builds/tests have finished. To reproduce the failing resource test, prepare a separate lab while the production file contains the pinned baseline version; do not replace a working file containing unrelated changes. The frozen `referenceBlurred` in an already prepared lab also preserves the original output for comparisons.

Saved evidence: [summary and complete provenance](Results/summary.json), [all process samples](Results/runs.jsonl), [native canvas allocation sizes](Results/native-canvases.json), [checks and source hashes](Results/verification.json). Reported p50/p95 are medians of twelve per-process percentiles, not pooled percentiles. Source snapshots and full compiler/test logs remain in the local evidence directory.
