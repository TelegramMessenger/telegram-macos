# Initial wallpaper cache budget report

This is the historical cost-only report for `68ed4df53c55b6344e7c3f50619e15861b734273`, before live-image reuse was added. Use the lab at that revision to reproduce the commands and measurements below. The current implementation and checks are documented in [README.md](README.md).

The global wallpaper cache previously limited the number of entries to 20, regardless of decoded bitmap size. Twelve distinct 2080×3160 wallpapers occupy about 301 MiB of bitmap data even after their callers release them. The cache can retain those images until eviction or a memory-pressure purge.

The change supplies each record's drawing bitmap cost (`CGImage.bytesPerRow × height`) to `NSCache` and sets a 64 MiB total-cost limit. This accommodates two wallpapers at the default 1040×1580-point background size at 2× resolution, while preserving the 20-entry limit for small previews and modes without an image. A single image larger than the budget is not admitted, so it cannot flush useful smaller entries. Replacing an existing key with such an image removes the old entry instead of returning stale content.

`NSCache` cost/count limits are advisory, and its eviction order is unspecified. This is a cache-retention budget, not a strict cap on process RAM. The byte cost describes the selected drawing bitmap, not every possible image representation or metadata allocation. Active themes and views retain their own backgrounds; clearing or evicting the shared cache does not release those owners. The production patch changes no cache keys, image resolution, rendering, or memory-pressure hook.

## Reproduce

On macOS with Xcode and Python 3, run from the repository root:

```sh
python3 tools/perflab/WallpaperCacheLab/run.py test
python3 tools/perflab/WallpaperCacheLab/run.py bench \
  --baseline-ref 35a0182637c683686a1db1d33ef48c8c3adb2e97 \
  --repetitions 5
```

`--work-dir /absolute/path` chooses the output directory; the default is `/tmp/telegram-wallpaper-cache-lab` (under the system temporary directory). Generated sources, fixtures, binaries, XCTest logs, individual process reports, `summary.json`, `runs.jsonl`, and `pixels.json` remain outside the checkout.

The runner extracts `WallpaperCache` and `WallpaperCachedRecord` directly from `PhotoCache.swift`, relaxing only access modifiers. It uses the actual `TableBackgroundMode` enum and the unchanged production `downsampledImage`/`decodedBitmapImage` functions. Stand-ins provide an integer cache key and SVG metadata: TelegramCore resource-key construction and SVG parsing are not exercised. The comparison executable extracts the old cache from the requested Git revision; both executables use the same decoder. No full application, account, network request, or dependency submodule build is required.

## Verification

Twelve XCTest cases pass in both Debug and Release. They cover pixel rather than point dimensions, row padding, tiled/background costs, image identity and settings, non-image modes, exact-budget admission, oversized admission/replacement, replacement release, purge with and without an external image owner, and 16,000 concurrent cache operations. Tests do not assume a particular `NSCache` eviction order.

The benchmark generates twenty deterministic JPEG files on disk, then decodes them through the production path. Full decoded bitmap SHA-256 hashes match for all twenty images before/after. Each workload also checks 64×64 offscreen render hashes, including cache hits and subsequent decodes. These checks establish image equivalence in the native harness; they are not screenshots from an authenticated client.

A complete Debug arm64 application build also passed with the exact patched `PhotoCache.swift` in a prepared checkout based on `166e37d737865fc97af99aa1283e4a4454c3ab0d`, using the repository's local Xcode 27 compatibility changes. Both `TelegramTheme` and `TelegramThemeShare` compiled; the whole patched file matched by SHA-256. This is not a clean build of the latest PR head. The build used macOS 27.0.1, Xcode 27.1/Swift 6.4, Telegram 13.1.0 build 283357. An authenticated client walkthrough and app-wide RAM/FPS/battery profiling were not performed.

## Before / after

Measured on a Mac16,8 with 24 GiB RAM and 12 logical CPUs, macOS 27.0.1. Values are medians of five fresh-process runs per variant/scenario (50 processes total), with before/after order alternated. Full-app compilation had finished before timing runs. A small decode warms the image frameworks before the initial memory reading. The metric is the increase in `TASK_VM_INFO.phys_footprint` after the workload, with autorelease pools drained and a 100 ms settling interval. File-system caches are warm: this does not measure cold disk latency.

| Workload | Before footprint increase | After footprint increase | Before → after decodes | Before → after cache hits |
| --- | ---: | ---: | ---: | ---: |
| 12 different full-size wallpapers, one pass | 304.94 MiB | 54.08 MiB | 12 → 12 | 0 → 0 |
| Same pass with first image retained by an external owner | 304.94 MiB | 79.17 MiB | 12 → 12 | 0 → 0 |
| Alternate two recent wallpapers, 100 requests | 52.59 MiB | 52.66 MiB | 2 → 2 | 98 → 98 |
| Twenty 132-pixel previews, 100 requests | 1.58 MiB | 1.61 MiB | 20 → 20 | 80 → 80 |
| Cycle through twelve full-size wallpapers twice | 304.91 MiB | 53.77 MiB | 12 → 24 | 12 → 0 |

The first workload retained 12 → 2 cache-only images, or 300.88 → 50.15 MiB of bitmap data. It reduced this harness's footprint increase by 250.86 MiB (82%). Two recent full-size wallpapers and twenty previews still fit and have the same hit counts. Small differences near equality are noise, not claimed improvements.

There is an explicit reuse tradeoff. Cycling through a working set larger than the budget needs additional decodes: twelve wallpapers visited twice took 262.81 → 503.25 ms of total decode time (about 240 ms extra across the second pass). Total cache-operation time including insertion/eviction was 0.059 → 3.911 ms over those 24 requests. For two recent wallpapers it was 0.037 → 0.047 ms over 100 requests. This is a memory-retention improvement, not a universal speedup.

After `clearAll`, weak references observed zero cache-only images in every run; the external-owner scenario retained its one independently owned image. The footprint readings after clear are included in the raw reports, but allocator/OS behavior is not an immediate-return guarantee.

These are controlled cache/decoder measurements, not a claim that every Telegram session saves 251 MiB. Actual benefit depends on image sizes, distinct backgrounds visited, their other owners, and system eviction.

[Summary and provenance](Results/summary.json), [all 50 process measurements](Results/runs.jsonl), [full bitmap hashes](Results/pixels.json). Individual unsummarized JSON reports and test/build logs can be regenerated with the commands above; the full application build additionally needs the documented native dependencies and local toolchain setup.
