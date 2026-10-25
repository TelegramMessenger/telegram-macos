# Wallpaper cache: reuse live images without retaining more bitmaps

The shared cache keeps the 64 MiB decoded-bitmap budget and 20-entry count limit introduced in PR #60. A second, count-limited cache stores reconstruction closures with **weak NSImage references**. After a strong-cache miss, an image that still belongs to a live theme/view can be reused with its original intensity, colors, rotation and SVG metadata. A weak hit does not promote the image into the strong cache or decode it again.

This addresses a gap in the cost-only cache: an active theme can still own an evicted bitmap while a newly created theme for the same wallpaper decodes a second copy. Weak records do not own the pixels. Once the last external owner closes, the image can be released unless it remains among the strong-cache entries. Replacement and memory-pressure purge update both caches under one lock; a purge also forgets still-live weak entries. `NSCache` eviction remains best-effort, with advisory limits. Weak records retain rendering metadata, not bitmap data.

Already-created themes have their own `_backgroundMode` value. Returning to the same theme already avoided global-cache lookup and decoding before this change. The improvement is for new themes that can reuse an image still alive elsewhere. It cannot eliminate the memory-versus-redecode tradeoff for images whose owners have all closed and which no longer fit in the strong cache.

## Reproduce

From the repository root on macOS with Xcode and Python 3:

```sh
python3 tools/perflab/WallpaperCacheLab/run.py test
python3 tools/perflab/WallpaperCacheLab/run.py test \
  --test-ref 68ed4df53c55b6344e7c3f50619e15861b734273 \
  --work-dir /tmp/wallpaper-reuse-before
python3 tools/perflab/WallpaperCacheLab/run.py bench \
  --baseline-ref 35a0182637c683686a1db1d33ef48c8c3adb2e97 \
  --current-ref 68ed4df53c55b6344e7c3f50619e15861b734273 \
  --repetitions 6
```

The second command is expected to fail: six new assertions expose the missing live-image reuse in PR #60. `--work-dir` chooses the generated output location; otherwise it uses the system temporary directory. `--scenarios live-themes return-to-open` can limit a benchmark run. To repeat the concurrency check, run `swift test --sanitize=thread` on the generated `tests` package after the first command.

The runner extracts the cache classes, `TableBackgroundMode`, `SVG_SlotsMetadata`, and decoder functions from production sources. It relaxes cache access modifiers for testing. The theme scenarios additionally compile the production `backgroundMode` getter in a small probe with the same lock and per-instance stored mode. Resource keys, palette values, and wallpaper lookup use fixture adapters. The probe does not construct real `TelegramPresentationTheme`/`ChatController` instances or test routing, layout, SVG parsing, GPU work, or account/network state.

## Verification

- **19 XCTest cases pass in Debug and Release, and with Thread Sanitizer.** Existing cost/retention coverage remains; new cases exercise weak background/tiled reuse, real rendering metadata, owner release, purge, replacement without stale fallback, and returning to a retained wallpaper after unrelated visits. The concurrency case performs 16,000 operations. The same suite against the cost-only cache fails six new assertions.
- **180 native measurements:** ten scenarios × three variants × six fresh-process runs. Variant order rotates, so each variant occupies every order position twice. Full decoded-bitmap hashes match for all twenty JPEG fixtures in all variants; workload render digests also match. Pixel resolution and cache-key behavior are unchanged.
- **Complete Debug arm64 application build passed**, including `TelegramTheme` and `TelegramThemeShare`, in the prepared checkout based on `166e37d737865fc97af99aa1283e4a4454c3ab0d` with the local Xcode 27 compatibility setup. The whole patched `PhotoCache.swift` and the decoder/getter/metadata blocks match the measured sources byte for byte. This is not a clean latest-head application build or an authenticated UI test. Application version: Telegram 13.1.0 (283357).

## Measurements

Mac16,8, 24 GiB RAM, 12 logical CPUs; macOS 27.0.1, Xcode 27.1 / Swift 6.4. All application builds and sanitizer runs finished before timing measurements. Filesystem caches are warm. Each process warms the image frameworks with a small decode. Fixtures are deterministic on-disk 2080×3160 JPEGs, decoded through production `downsampledImage`; preview cases use a 132-pixel cap.

Variants: **original** = count-only cache at `35a01826`; **PR #60** = cost-only cache at `68ed4df5`; **live reuse** = the final cache implementation. Its measurement provenance records the production SHA-256 and the base commit of the measured worktree.

### Decode counts

| Scenario | Original | PR #60 | Live reuse |
| --- | ---: | ---: | ---: |
| Twelve themes remain alive; create new themes for those backgrounds 120 more times (132 requests) | 12 | 132 | 12 |
| Keep the base theme, visit twelve other backgrounds, then create a new theme for the base (14 requests) | 13 | 14 | 13 |
| Reuse the same two theme objects, 100 accesses | 2 | 2 | 2 |
| Twelve backgrounds visited twice, each theme released after its access (24 requests) | 12 | 24 | 24 |

The live-themes scenario avoids 120 redundant decodes compared with PR #60. The base-theme return also avoids a decode after unrelated backgrounds have displaced its strong-cache entry. The same-object control still decodes just twice. With fully released owners, decode counts remain unchanged from PR #60; weak references cannot recover an already-freed bitmap.

### Background-access latency

Values below are the median of six per-process p95 values, in milliseconds. They time synchronous background retrieval and probe creation only; offscreen hashing is excluded. They are **not chat-switch latency**. For `return-to-open`, each process has one measured final return access. Other theme scenarios exclude their first twelve initial accesses; the same-object control excludes its first two.

| Scenario | Original ms | PR #60 ms | Live reuse ms |
| --- | ---: | ---: | ---: |
| Recreate themes for still-live wallpapers | <0.001 | 29.789 | <0.001 |
| Return to the retained base theme after twelve other backgrounds | 0.019 | 25.590 | 0.022 |
| Access the same two theme objects | <0.001 | <0.001 | <0.001 |
| Reopen backgrounds after their owners were released | 0.020 | 28.887 | 29.970 |

Sub-microsecond differences are not claimed speedups. Miss-heavy decoder timings fluctuate by a few percent across runs; the exact raw samples and total decode/cache times are included in the reports. The stable behavioral result is elimination of duplicate decodes when an owner remains alive, with no new decodes in the tested controls. A signed-in end-to-end latency guarantee has not been established.

### Physical footprint and owner release

Memory values are medians of `TASK_VM_INFO.phys_footprint` increases from the warmed process baseline, after autorelease-pool drainage and settling. They are component-process measurements, not Telegram's total RAM usage.

| Scenario | Original MiB | PR #60 MiB | Live reuse MiB |
| --- | ---: | ---: | ---: |
| Browse twelve backgrounds without keeping external owners | 305.89 | 54.90 | 54.76 |
| Recreate themes while twelve original themes remain alive | 305.81 | 356.21 | 305.45 |
| Same scenario after the twelve themes close, before clearing the cache | 305.81 | 55.11 | 54.54 |
| Base-theme return after twelve other backgrounds | 330.19 | 79.73 | 79.63 |

The twelve live owners necessarily retain their twelve images. Live reuse avoids the duplicate copies seen with PR #60. After those owners close, both budgeted variants retain only two bitmaps (50.15 MiB of pixels), versus twelve in the original cache. The original large-memory saving is therefore preserved. `clearAll` releases every cache-only image; an explicitly retained separate image remains alive until its owner is released. After purge and all owner releases, every measured weak image is gone. Allocator/OS footprint changes are observations, not an immediate-return guarantee.

## Evidence and limits

[Summary/provenance](Results/Reuse/summary.json), [all 180 process samples](Results/Reuse/runs.jsonl), [decoded bitmap hashes](Results/Reuse/pixels.json), [verification manifest](Results/Reuse/verification.json). The [initial budget report](BudgetReport.md) preserves the earlier cost-only experiment.

The cache budget stays 64 MiB. There are no new timers, image resizes, compression/quality changes, dependencies, or public module APIs. The weak fallback is opportunistic and may itself be evicted under pressure. It improves reuse of still-live images; it does not guarantee the original count-only cache's hit rate after all owners close. Real chat navigation, frame timing, total application RAM and battery impact still need an authenticated application walkthrough/profile.
