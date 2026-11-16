# Widget stress suite

Self-contained fixtures for the real sandbox and renderer. They use the normal strict policy, CPU quotas and resource limits. No network resources are needed.

| Fixture | Workload | Controls |
| --- | --- | --- |
| `canvas-market.html` | 12 canvas charts, 192 gradient bars, 768 chart points and 360 changing text labels per frame, at 2× backing resolution | Pause / Resume |
| `live-board.html` | 192 service cards, nested grid content, 24 text and transform updates every 100 ms, with a modal over the live board | Pause / Resume, Details / Close |
| `orbit-wall.html` | 64 clipped scenes, 128 nested CSS transform animations and overlapping labels | Pause / Resume |
| `order-book.html` | 96 instruments, 288 quotes and depth fills, updating 72 quotes and transforms at 20 Hz | Pause / Resume, Details / Close |
| `canvas-atlas.html` | 48 clipped canvas panels, 384 transformed paths, 48 gradients and blurred shadows per frame, at 2× backing resolution | Pause / Resume |
| `reflow-cards.html` | 72 gradient cards with shadows; 12 text, progress-width and clipped-height changes every 100 ms | Pause / Resume, Expand all / Animate height |
| `clipped-ticker.html` | 120 clipped gradient tracks, 30 changing readings per frame and continuous grid-width changes | Pause / Resume, Lock width / Resize |
| `phase-grid.html` | 144 clipped scenes, 288 overlapping gradient/text tracks, fractional clip origins and translations, width changes and alternating stacking order | Pause / Resume, Lock width / Resize |
| `contained-ticker.html` | 96 fixed-size translated tracks inside resizing ancestors, with 24 changing readings per frame | Pause / Resume, Lock width / Resize |
| `nested-clips.html` | 24–96 scenes (48 by default), three nested rounded clips and two overlapping tracks per scene, fractional movement, resizing and changing paint order | Pause / Resume, Lock width / Unlock width, Scene count, Freeze |
| `gradient-clips.html` | 24–96 cards (96 by default), 288 nested rounded clips, 192 moving tracks and 768 gradient segments; ordinary, reversed, alpha and diagonal gradients | Pause / Resume, Lock width / Unlock width, Card count, Freeze |
| `decoration-grid.html` | 24–96 fixed flex panels (96 by default), 576 rounded decorations, 96 moving indicators and 24 changing readings per frame; opaque, alpha, clipped and rotated cards inside a resizing grid | Pause / Resume, Lock width / Unlock width, Panel count, Freeze |
| `tile-crossings.html` | 12–48 panels (24 by default), 1025×513 scroll content, three rounded clips and two overlapping alpha/text tracks per panel; deterministic integer/fractional phases, cross-tile scrolling and owner churn | Pause / Resume, Width lock, Panel count, Phase mode, Freeze, Step, Reset owners |
| `clipped-panels.html` | 12–48 panels (24 by default), 1537×769 translucent content behind small rounded viewports, up to 6,144 text cells, resizing and translated tracks | Pause / Resume, Panel count, Reveal distant / Return, Reset, Freeze |

Build from the repository root:

```sh
swift build --package-path tools/perflab/TwidgetLab --scratch-path /tmp/widget-stress-build -c release
```

Run three serial rounds in native and WebKit:

```sh
python3 tools/perflab/widget-stress/run.py \
  --lab /tmp/widget-stress-build/release/TwidgetLab \
  --out /tmp/widget-stress-results
```

The runner saves screenshots, logs, individual measurements, ranges, medians and binary/fixture hashes. Renderer order reverses on alternate rounds. It fails on a renderer error, sandbox death, missing render or missing measurement. Run on an unlocked Mac with builds and other benchmarks stopped. CPU includes the host and its WebKit helpers, expressed as a percentage of one core. WindowServer measurements are logged separately because other applications affect them. Host callback counts are **not display FPS**: CSS animations can run entirely in Core Animation with zero host callbacks.

Both variants use QuickJS and the same sandbox policy. The comparison is against sandbox-backed WebKit, matching the two comparison chats. It is not a raw HTML/JavaScriptCore browser comparison. Full transport tracing is opt-in with the harness's `--record-ops`; `--logs` retains sandbox diagnostics without accumulating DOM payloads. Older measurements below used transport tracing, which stored full WebKit JSON but only native typed-operation counts. Prefer the corrected measurements for current cross-renderer comparisons. Use the runner's `--visible` option for an opaque window; the default timing window is almost transparent, with WebKit occlusion detection disabled. Neither mode alone measures scanout or proves hitch-free presentation.

Preserve a baseline executable before changing the renderer, and run the same fixtures through both executables. `--renderers lite` skips WebKit when only the native implementation changes. `--fixtures order-book canvas-atlas reflow-cards` selects the harder second set. Compare `summary.json` files and inspect the logs for layout counts, tile work, promotions, errors and memory.

Interactive preview:

```sh
/tmp/widget-stress-build/release/TwidgetLab interactive \
  tools/perflab/widget-stress/live-board.html \
  --renderer lite --width 480 --height 800 --max-height 6000 \
  --scroll-content --theme dark --seconds 3600
```

Use `--renderer web` for the comparison window. Add `--background` to the native command to exercise the production background executor. The preview host scrolls the page; `tile-crossings.html` also scrolls its nested panels programmatically. Check Pause / Resume, repeated modal open / close, Expand all / Animate height, and scrolling down and back while the widgets update.

For repeatable screenshots, append `<script>setTimeout(function(){window.stress.freeze();},1000);</script>` to a temporary copy and capture after at least three seconds. The delay exercises updates and layer handoffs before freezing. This selects the same chart and board state and the same static transforms in both engines. `window.stress.resume()` restores motion. Do not compare screenshots taken at arbitrary animation times as pixel-equivalence tests.

Renderer regression coverage is in `CanvasReuseTests`, `DenseOverlapCompositingTests` and `ScrollLayerTests`, alongside the existing canvas, clipping, animation, handoff and compositor suites.

For an equal-work renderer-component comparison, build the release renderer tests and run:

```sh
swift test --package-path third-party/twidget -c release --filter LocalPaintWorkloadTests
python3 tools/perflab/widget-stress/run-fixed-work.py --out /tmp/widget-fixed-work --rounds 3
```

This repeats 60 completed mutation states for 120 contained tracks with local paint reuse disabled and enabled. Every state waits for renderer work and expected scroll-tile installations; mutation and installed-pixel checks run outside the measured interval. The report includes process CPU per completed state, elapsed time, raster counts and per-state completion counters. Elapsed time includes test barriers and queue draining. This measures the renderer component, not WebKit, full-host throughput or presented frames. Separate tests exercise integer and fractional widths while scroll layers retain ownership.

For source changes that cannot be toggled in one executable, preserve the release XCTest bundle before editing, build the candidate, and compare the two bundles:

```sh
python3 tools/perflab/widget-stress/run-renderer-pair.py \
  --before-bundle /tmp/widget-before/twidgetPackageTests.xctest \
  --after-bundle /tmp/widget-after/twidgetPackageTests.xctest \
  --out /tmp/widget-renderer-pair --rounds 3
```

Build both bundles from the same `LocalPaintWorkloadTests.swift`. Preserve each bundle's original basename so XCTest can locate its executable. The runner records hashes, uses the same optimization settings in both processes, reverses order on alternate rounds, and requires matching completed work counts before reporting a CPU reduction. Keep builds, other benchmarks and interactive previews stopped during measurement.

The same HTML is bundled into both comparison chats. Synchronize the corpus after editing fixtures, then verify it:

```sh
python3 tools/perflab/widget-stress/sync-fixtures.py
python3 tools/perflab/widget-stress/sync-fixtures.py --check
```

The shared `widget-sandbox/showcase/stress/perflab-*.html` fixtures live in `packages/HTMLBubbles/Tests/HTMLBubblesTests/Fixtures` and ship only with the HTMLBubbles tests. Since 2026-10-26 the app has no `All Widgets` chats, so the app-driven runs below need a local build that sets `HTMLDemoCatalog.fixturesRoot`.

## Measured results — 2026-10-14

Three serial runs per case on macOS arm64, 480 CSS pixels wide, dark theme, eight seconds per run with two seconds excluded for warmup. Values below are median CPU percentages of one core, including WebKit helpers and excluding WindowServer. Full measurements are in `results-2026-10-14.json`.

| Workload | Native before | Native after | WebKit | Outcome |
| --- | ---: | ---: | ---: | --- |
| Canvas market | 38.86% | 32.62% | 48.89% | 16.1% less native CPU; 60 host frames/s retained |
| Live board | 21.94% | 23.09% | 29.22% | No targeted improvement; overlapping run ranges |
| Orbital wall | 61.77% | 0.27% | 20.37% | 99.6% less application CPU; all 128 animations driven by Core Animation |

These are workload measurements, not a claim of the same improvement across all widgets or total system energy. Core Animation and WindowServer still perform display work.

The orbital wall previously promoted only 24 overlapping labels. This left most nested animations on software repainting. The compositor now uses remaining capacity in its existing 256-layer budget to admit these labels, while retaining the existing pixel budget and overlap/clipping checks. Promotions increase from 72 to 192 layers; eight-second runs fall from roughly 495 layouts to 7 startup layouts, with no continuing native animation ticks.

Canvas profiling found repeated Core Text shaping and repeated gradient construction. Short text lines are now reused with a 1,024-entry limit and a maximum combined text/font key length of 256 UTF-8 bytes. Gradients reuse their compiled representation until a stop changes or the handle is redefined. The canvas stress case's median process footprint rises from 107.1 MB to 108.8 MB. Sandbox CPU quotas, operation validation and object limits are unchanged.

Validation: 91 related renderer tests passed; additional text paint/alignment variations passed; Telegram Debug built successfully. All three deterministic native screenshots have zero changed RGBA bytes versus the baseline. Native/WebKit snapshots have matching dimensions, with mean absolute RGB differences of 0.144, 0.008 and 0.328 out of 255 respectively. Animation regression tests compare composed pixels against software rendering at fixed timestamps and retain antialiasing tolerance.

Manual checks used both native and WebKit previews: pause/resume for all three fixtures, scrolling through the board and orbital wall, and modal open/close over the updating board. The fixture modal is positioned near the top so it remains visible in a tall chat widget.

## Harder workloads and resizing clips

The second set separates dense text/transform updates, canvas effects and repeated grid reflow. Profiling the capacity planner found scroll-layer admission, tile regeneration and an additional exclusion-layout pass for expanding and collapsing `overflow:hidden` details.

Clipped regions that change height at a stable width now use ordinary clipped painting until explicitly scrolled. Stable clips keep their cached surfaces. Width changes alone do not disable these surfaces. A first scripted scroll restores eligibility once, including an explicit zero offset; subsequent scroll-only updates still avoid layout. Wheel-enabled containers retain their normal behavior. The remembered set is pruned when regions disappear.

For a matched A/B run with the optimization disabled:

```sh
TW_NO_RESIZE_AWARE_CLIPS=1 python3 tools/perflab/widget-stress/run.py \
  --lab /tmp/widget-stress-build/release/TwidgetLab \
  --out /tmp/widget-stress-before --renderers lite
```

This diagnostic switch preserves the normal scroll implementation. Disabling all scroll layers is not an equivalent baseline: it helps the capacity planner but increases repainting in the order book. Sandbox quotas and rendering budgets remain unchanged.

The initial clipping-only experiment used three serial matched A/B rounds, with native order reversed in the second round. After correcting and caching scripted transform origins, all six native cases were run three more times with the same dimensions and timing. The table uses those final native measurements and the original baseline and WebKit measurements. Raw measurements, the intermediate clipping-only phase and ranges are in `results-2026-10-14-round2.json`.

| Workload | Native before | Native after | WebKit | Interpretation |
| --- | ---: | ---: | ---: | --- |
| Canvas atlas | 77.17% | 76.77% | 90.24% | No targeted change; native already uses less application CPU |
| Order book | 42.95% | 42.57% | 36.08% | Overlapping native ranges; WebKit still wins |
| Reflow cards | 50.49% | 34.95% | 40.78% | 30.8% less native CPU; 14.3% below WebKit |
| Canvas market, control | 33.36% | 31.43% | — | Overlapping run ranges |
| Live board, control | 21.07% | 19.75% | — | Overlapping run ranges (20.91–22.48% versus 19.05–25.09%) |
| Orbital wall, control | 0.26% | 0.25% | — | Animations remain on Core Animation |

The reflow case's median layout count fell from 242 to 171 over each eight-second run, and process footprint fell from 105.6 to 86.3 MB. The live-board control's footprint increased from 75.8 to 82.2 MB; canvas atlas and order book footprints stayed approximately unchanged. Host callbacks remained approximately 60/s. These figures measure CPU work and memory, not end-to-end display latency or guaranteed performance in every widget.

The new canvas workload spends most native rendering time in Core Graphics gradient filling and path/shadow rasterization. Its transforms, clipping, paths and effects do not qualify for the current Metal canvas fast path. The order book remains a useful regression target for dense text, transforms and layer-admission costs. These remaining bottlenecks are not solved by the clipping change.

Deterministic captures after one second of live updates showed zero changed RGBA bytes for the canvas atlas and order book. The reflow capture kept matching dimensions and geometry; differences were confined to text edges in formerly tiled details (mean absolute RGBA difference 0.080/255). Native/WebKit mean absolute RGB differences were 0.338, 1.064 and 0.342/255 respectively. The delayed freeze exercises layer removal before comparison.

Manual checks also found a preexisting scripted-transform bug: stylesheet `transform-origin` was omitted during promotion, so right-anchored depth bars could scale around their centers after closing a modal. The compositor reads and caches this property separately from the animation declaration scan, and scripted promotions use its cascaded value. A regression checks both stylesheet origins and a subsequent inline-origin change; it failed before the fix. Native modal open/close and pause/resume were checked again with the corrected build.

Validation: 72 related renderer tests passed in a combined run; the subsequent origin-cache refinement passed 18 relevant tests, including clipping, pixel samples, zero-height expansion, programmatic/wheel scrolling, script promotion, animation overlap and canvas reuse. The release harness built. All three new fixtures passed manual pause/resume checks in native and WebKit; the grid also passed expansion and host scrolling, and the order book passed repeated modal open/close. Rerunning this suite requires only the standalone harness and renderer package tests, without building the full app.

## Scoped snapshots and conservative transformed clipping

Element and scroll snapshots now resolve paint exclusions within the requested subtree, except when a backdrop filter needs to sample outside it. Full-page drawing and paint-order queries resolve the whole document. Four bounded membership caches avoid rebuilding unchanged exclusion sets for every small surface; they retain strings, not pointers into an old layout. Tests cover switching roots, changing and clearing exclusions, temporary overrides, nested scrolling and offsets. Review found and reproduced two edge cases before publication: paint-order queries inherited partial scroll exclusions, and cached backdrop traces could admit an excluded sibling. Both now have regression coverage, including cold and primed backdrop traces.

The shared C++ renderer inverse-maps the outer clip through affine groups and passes a conservative local bounding box to descendants. The calculation expands the clip, rounds outward and falls back for filters, singular matrices or numerically extreme coordinates. This preserves culling through translation, rotation, skew and scale instead of abandoning the clip. Pixel tests exposed an existing text-shadow bound that omitted displaced shadows; the text draw guard now includes shadow offset, blur and spread. Nested transform tests compare 576 clipped renders byte-for-byte with unculled traversal, and a dedicated test compares isolated shadow tiles with full-image crops.

The initial three-round native A/B used identical transport recording in both binaries. Order-book median CPU fell from 48.10% to 35.80% with about 60 host callbacks/s. The new clipped ticker used more CPU (147.53% to 158.24%) and advanced more often (52.3 to 54.5 callbacks/s). In the first paired ticker run, tile jobs per callback rose from 40.08 to 51.20 while raster time per job fell from 0.176 to 0.167 ms. These time-driven runs do not hold completed paint work constant; the ticker remains an unresolved performance case. Do not describe its higher throughput as a CPU reduction or its callbacks as display FPS.

## Final comparison — 2026-10-15

After the backdrop and paint-order fixes, all seven workloads were run again in both engines, three times each, with transport recording disabled. The 42 serial captures used the same binary, fixtures, sandbox limits, 480 CSS-pixel width and eight-second duration with two seconds excluded for warmup. [Raw runs, ranges, binary and source hashes, rejected probes and validation](results-2026-10-15-round3.json) are retained together. The binary includes preexisting local SVG changes outside this patch; their hashes are recorded, and those changes are not part of this optimization commit.

| Workload | Native CPU | WebKit CPU | Native CPU relative to WebKit | Host callbacks/s, native / WebKit |
| --- | ---: | ---: | --- | ---: |
| Canvas atlas | 75.13% | 86.92% | 13.6% lower | 59.9 / 60.1 |
| Canvas market | 33.31% | 46.89% | 29.0% lower | 60.0 / 60.0 |
| Clipped ticker | 158.62% | 129.48% | 22.5% higher | 54.4 / 49.1 |
| Live board | 23.89% | 30.58% | 21.9% lower | 60.0 / 60.0 |
| Orbital wall | 0.30% | 21.18% | 98.6% lower application CPU | 0.0 / 0.0 |
| Order book | 35.73% | 39.23% | 8.9% lower | 60.0 / 60.1 |
| Reflow cards | 37.64% | 40.62% | 7.3% lower | 60.0 / 59.9 |

These medians show lower native application CPU in six workloads, not a universal speedup. Orbital animations use Core Animation; their display work is not represented by zero host callbacks. The clipped ticker triggered rendering-budget coalescing in two of three native runs and still needs further work. A fixed-work completion benchmark and visible presentation trace are required before making stronger throughput or smoothness claims.

Validation after the final correctness refinements: 65 renderer tests passed, following the earlier broader 75-test run; both portable CMake suites passed. All seven frozen native captures have zero changed RGBA bytes against the baseline. The ticker's native and WebKit captures both measure 960 × 6340 pixels, with mean absolute RGB difference 0.566/255. Repeated modal open/close and pause/resume were checked in both standalone renderers, as were ticker width locking, resizing, and scrolling down and back. These UI checks inspect controls and resulting states; they do not establish that every presented frame is hitch-free. All seven bundled chat resources match their source fixtures byte-for-byte. Only the renderer package and standalone harness were built; the full Telegram app was not built.

## Research experiments and next gates

Three research reviews examined vector rasterization, mathematical reuse and measurement fairness. The next CPU-oriented opportunity is to separate local paint identity from outer placement and clipping. The current compositor hashes ancestor declarations, so changing an ancestor's width can invalidate a fixed-size descendant's raster. A safe replacement must hash resolved root-local commands, preserve group/clip boundaries and paint order, include raster scale and sampling phase, and track font/resource generations. It must compare canonical commands after a hash match. Simply omitting ancestor declarations would miss inherited styles, selectors and wrapping. Changing a descendant transform still changes the enclosing scroll surface and cannot be ignored.

Two controlled probes were rejected from the production patch:

| Experiment | Evidence | Decision |
| --- | --- | --- |
| Evaluate axis-aligned CSS gradients as a one-dimensional strip, then replicate samples | 480 direct-raster comparisons, 145,595,200 channel values, maximum difference 1/255; ticker CPU 158.47% versus 158.52% in the probe | No demonstrated CPU win; retain the existing path |
| Demote overflow-hidden surfaces after three width changes within 250 ms, retaining explicit scrolling | 58 related tests passed; ticker CPU 158.31% to 57.28%, but callbacks fell from 54.4 to 42.6/s and renderer throttling appeared | Reject the lower CPU result as a smoothness improvement; retain existing admission |

The mathematical direction is reuse of geometry coverage independently from paint. [Vello's Sparse Strips architecture](https://github.com/linebender/vello/blob/main/ARCHITECTURE.md) shares a CPU-side coverage representation between CPU and GPU backends, storing boundary coverage separately from compact interiors. That supports exploring a portable CPU representation; it does not establish a speedup for this renderer. Coverage-cache keys must retain transform scale, subpixel phase, fill rules and mutable-path revisions. Analytical rectangular Gaussian shadows are another candidate, but matching the existing blur response is a prerequisite to enabling them.

A fixed-work benchmark should execute an identical finite sequence with one completed render state in flight. Report CPU milliseconds per completed state, elapsed throughput and latency percentiles alongside the free-running test. Native completion needs a generation-aware barrier covering held operations, deferred render work, background raster batches and pending layer installations. A geometry query or a single raster-queue fence is insufficient. WebKit needs an acknowledgement after its ordered operation batch and a subsequent rendering opportunity, following the distinction between synchronous and deferred work in [Speedometer 3](https://webkit.org/blog/15131/speedometer-3-0-the-best-way-yet-to-measure-browser-performance/). These are completed-render measurements; actual presentation still needs a visible frame-lifetime trace.

## Scroll raster lifetime and installation — 2026-10-15

Asynchronous scroll jobs now check cancellation and document ownership after acquiring the document lock. A consumed source is rejected without reconstructing its old HTML and layout. Rejection retains the last painted pixels, leaves the tile invalid, and retries only when a newer source is available. The renderer refreshes scroll sources after its final ordinary layout, including the additional exclusion-layout pass. Silent geometry queries continue to defer presentation. Unchanged tiles remain cached; synchronous first fill and explicit old-document snapshots retain their previous behavior.

Async tile installations join the main thread's implicit Core Animation transaction instead of starting a transaction for every result. Tile geometry, sampling and contents actions are explicitly disabled. First-fill installation remains synchronous. Both changes can be disabled for comparison with `TW_SCROLL_BATCH_COMMITS=0 TW_SCROLL_SKIP_OBSOLETE=0`.

Three serial rounds per affected workload used one release binary, the same fixtures and sandbox policy, and the corrected transport-recording settings described above. The baseline disables both changes; the selected path enables both. Variant order reverses in the second round. CPU is percent of one core, including WebKit helpers and excluding WindowServer. [Measurements, logs, hashes, experimental probes and validation](results-2026-10-15-round4.json) are retained together.

| Workload | Native before | Native after | WebKit | Native CPU change | Host callbacks/s, before / after / WebKit |
| --- | ---: | ---: | ---: | --- | ---: |
| Clipped ticker | 157.98% | 154.38% | 129.42% | 2.3% lower | 54.8 / 55.3 / 48.2 |
| Order book | 35.73% | 33.44% | 39.06% | 6.4% lower | 60.0 / 60.1 / 60.1 |
| Reflow cards | 38.08% | 37.94% | 40.57% | Effectively unchanged | 59.9 / 59.9 / 60.0 |

The ticker still uses more application CPU than WebKit and remains below 60 host callbacks/s. Callback counts do not measure display FPS or hold completed paint work constant. These results do not establish a universal speedup or hitch-free presentation.

An IOSurface experiment was rejected. Surface preparation alone increased ticker CPU from 159.08% to 163.76% in its probe. Combining it with cancellation and batching reduced ticker CPU from 158.13% to 145.58%, but callbacks fell from 54.8 to 52.6/s and order-book CPU rose from 35.35% to 39.68%. The selected implementation retains the original CGImage format. Cancellation alone showed no free-running CPU improvement in the isolated probe; its regression tests establish that obsolete work is skipped without clearing presented pixels or stranding pending tiles.

Validation: 118 renderer tests passed, including cancellation during document-lock contention, consumed-source retries, unchanged tile reuse, final-layout completion without another frame, silent scroll-content queries, and a 24-state completed resize trace at 1×/2× scale. All seven frozen full-widget images and all seven visible 960 × 1800 window captures have zero changed RGBA bytes against the published baseline. Native and WebKit previews passed ticker pause/resume, width locking, continuous resizing, scrolling down and back, and window narrowing/restoration. The seven shared chat fixtures remain byte-identical. Only the renderer package and standalone lab were built; no full Telegram build was run.

## Resolved paint reuse and harder phase tests — 2026-10-15

Two additional fixtures extend the shared corpus to nine: 144 clipped scenes with 288 overlapping tracks, fractional origins and changing paint order; and 96 contained tracks whose ancestors resize continuously. Both are bundled for the native and WebKit comparison chats. They retain normal sandbox quotas and the renderer's existing layer and pixel budgets.

The compositor now compares bounded, resolved paint commands before invalidating a translated element's raster because an ancestor changed. The key retains local geometry, raster scale and sampling phase, immutable font identity, text, colors, gradients, borders, clips and paint order. It compares complete command bytes, not only hashes. Unsupported paint, changed fractional phase, effects and scroll-owned descendants retain the existing rendering path. The key and exact alpha-bounds scan are portable C++; the integration measured here is macOS-specific.

Compact shadow masks now reuse their actual raster dimensions during resizing; the large-shadow fallback retains full geometry in its key. Alpha bounds use exact block scans, and layer sorting avoids repeated sibling scans while still updating order when retained elements change z-index. Tests also caught and fixed a first-frame capture hole when a promoted ancestor contained a separately rendered scroll subtree. Scoped captures now include that subtree and restore all exclusion state, preserving unrelated scroll owners and backdrop behavior.

The fixed-work comparison uses one release test binary with reuse disabled/enabled in separate processes, three runs each with reversed order in round two. Each run completes the same 60 mutation states across 120 tracks, waiting for document and scroll-tile installation. CPU falls from **43.546 to 37.042 ms per completed state (14.9%)**. Compositor rasters fall from **7,200 to zero after warmup**. Test elapsed time falls from 8.112 to 7.840 seconds, but includes completion barriers and is not display latency. Applied-state, fresh tile and installed-tree pixel checks run outside measured intervals. This is a renderer-component result, not a WebKit comparison.

The free-running comparison below uses the published round-four native binary, the final native binary and WebKit, three serial runs per workload. All 81 runs use the same HTML, sandbox policy, 480 CSS-pixel width and eight-second duration with two seconds excluded for warmup; variant order reverses in round two. CPU is percent of one core, including WebKit helpers and excluding WindowServer. [Raw runs, ranges, source and binary hashes, validation and rejected experiments](results-2026-10-15-round5.json) are retained together.

| Workload | Native before | Native after | WebKit | Host callbacks/s, before / after / WebKit |
| --- | ---: | ---: | ---: | ---: |
| Order book | 33.28% | 32.87% | 36.86% | 60.0 / 60.0 / 60.0 |
| Clipped ticker | 154.84% | 153.47% | 129.34% | 55.6 / 54.9 / 48.0 |
| Reflow cards | 37.48% | 35.56% | 40.01% | 59.9 / 60.0 / 60.1 |
| Canvas market | 33.32% | 33.31% | 46.98% | 60.0 / 60.0 / 60.0 |
| Live board | 22.96% | 22.79% | 29.04% | 60.1 / 59.9 / 60.1 |
| Orbit wall | 0.30% | 0.29% | 19.90% | 0.0 / 0.0 / 0.0 |
| Canvas atlas | 73.89% | 74.67% | 87.70% | 59.9 / 60.1 / 60.0 |
| Phase grid | 143.31% | 150.24% | 129.60% | 49.9 / 51.9 / 21.9 |
| Contained ticker | 49.82% | 94.89% | 68.97% | 43.7 / 58.3 / 60.0 |

These results do not establish a universal CPU reduction or display-frame improvement. In particular, the contained ticker accepts more updates instead of coalescing them, increasing callback throughput and total CPU together. The fractional phase grid still reaches the rendering budget, and the clipped ticker remains more expensive than WebKit. Callback counts are not display FPS; the zero-callback orbital animation continues in Core Animation. The equal-work comparison above isolates raster reuse without conflating lower work with lower CPU.

An aggressive scroll-owned sprite experiment remains disabled by default (`TW_SCROLL_COMPOSITOR_TAKEOVER=1` is experimental). It reduced ticker CPU in a probe but changed fractional sampling beyond small antialiasing differences and delivered fewer callbacks. A separate canonical-origin experiment reduced raster count but changed text and solid edges; that implementation was removed. The next conservative experiment is reuse within the existing scroll-tile coordinate system, retaining exact effective sample phase and falling back when fractional translation changes it. No benefit is assumed until measured.

Validation: 338 renderer/shadow tests passed, with four optional benchmarks skipped; all four portable/Apple CMake suites passed. The alpha scanner passed 181,290 cases plus AddressSanitizer and UndefinedBehaviorSanitizer checks. All nine frozen full-widget images and all nine visible window captures have **zero changed RGBA bytes** against the published baseline. The six fixed-work runs each completed 60 states and seven installed-tree pixel checks; control scroll tiles were checked byte-for-byte on every state. Manual native/WebKit controls, host scrolling, window resizing and modal checks are recorded in the result file. All nine bundled fixtures match their source HTML byte-for-byte. Only the renderer package and standalone lab were built; **no full Telegram build was run**.

## Cached paint exclusions — 2026-10-15

Tile draws now reuse the resolved sets of elements painted by another layer. Previously, every tile could repeat the same tree scans. The bounded portable C++ cache stores independent canonical sets for normal full-document tiles and full-document snapshots; the macOS integration invalidates them on tree, style, layout or exclusion changes. Captures still restore mutable drawing state. Only the full document root is admitted, retaining at most two entries and 4,096 set-member references per document. Scoped captures use the existing resolver. Oversized entries use the original resolver without copying into the cache. `TW_PAINT_EXCLUSION_CACHE=0` disables reuse for comparison.

Three alternating cache-off/cache-on runs use the same release test binary and complete 60 mutation states each. Every mode matches state, layout, document job, document installation, scroll raster, tile job and compositor raster counts exactly. Pixel checks run outside timing. These are renderer-component CPU measurements, separate from the WebKit comparison below.

| Fixed workload | Cache off, CPU ms/state | Cache on, CPU ms/state | Median CPU reduction |
| --- | ---: | ---: | ---: |
| Integer resizing | 39.927 | 38.670 | 3.1% |
| Fractional resizing | 39.427 | 39.636 | -0.5% |
| Contained tracks | 36.563 | 31.508 | 13.8% |

The gains are incremental, and timing ranges should be considered alongside the medians. Fractional resizing is effectively unchanged within variation (0.5% higher median CPU). Elapsed test time includes completion barriers and is not display latency. [Raw results, ranges, source/binary hashes, per-state work counts and validation](results-2026-10-15-round6.json) accompany the measurements.

The live comparison uses the published baseline, the final native binary and WebKit, three serial runs each with reversed order in round two. HTML, sandbox quotas, 480 CSS-pixel width, eight-second duration and two-second warmup are identical. CPU includes WebKit helpers and excludes WindowServer. Callback counts measure sandbox scheduling, not displayed frames or equal completed painting.

| Workload | Native before CPU | Native after CPU | WebKit CPU | Host callbacks/s, before / after / WebKit |
| --- | ---: | ---: | ---: | ---: |
| clipped-ticker | 154.21% | 158.95% | 129.32% | 55.4 / 55.9 / 48.1 |
| phase-grid | 150.86% | 140.75% | 130.14% | 51.8 / 49.9 / 21.8 |
| contained-ticker | 95.78% | 78.61% | 68.89% | 57.5 / 60.0 / 60.0 |
| order-book | 33.30% | 33.48% | 38.95% | 59.9 / 59.9 / 60.0 |

The clipped ticker performs more rendering after the change: median layouts across the whole capture rise from 229 to 259; tile jobs per measured host callback rise from 50.65 to 55.86. Median tile draw cost falls from 0.165 to 0.122 ms/job. Its higher total CPU is not a matched-work regression measurement, but it also is not a total-CPU saving. The clipping-heavy workloads remain more CPU-intensive than WebKit.

Validation: 343 renderer/exclusion/shadow tests passed, four optional benchmarks skipped; five portable/Apple CMake suites passed. The cache passed 108 standalone checks with AddressSanitizer and UndefinedBehaviorSanitizer. All nine full-widget captures and all nine installed-window captures have zero changed RGBA bytes against the baseline. Manual standalone controls, scrolling, resize and modal checks are recorded with the results. The nine existing fixtures remain byte-identical in both comparison chats. Only the renderer package and standalone lab were built; no full Telegram build was run.

An earlier version also cached one-off scoped captures, retaining 59 entries in the fixed workload and reducing contained-work CPU by only 6.7%. Full-root-only admission retains one entry there and reduces CPU by 13.8%. The earlier measurements remain in the result file. Live CPU alone was not used to infer overhead because completed rendering work differs.

Viewport-based paint deferral was investigated but not enabled: fresh first exposure requires a coordinated handoff with host scrolling. Retaining old images and asynchronously catching up would risk stale content. The renderer still has heavy workloads to improve; these results do not establish a universal advantage over WebKit or 60 displayed frames per second.

## Combined exclusion matching and nested clips — 2026-10-15

Paint, layer, background and scroll exclusions now share one subtree traversal. Rules using the same attribute share one lookup and combine their results with category bits. Snapshot-specific category masks and global text exclusions retain their previous behavior. Compiled rules own strings and are invalidated when configuration changes; they do not retain node pointers. Scoped captures skip a separate recursive backdrop search when the document has never computed a backdrop filter. Tests cover filters being introduced later through hover, inline styles, stylesheet replacement and consumed-document restoration.

The new `nested-clips.html` fixture selects 24, 48 or 96 scenes. The default has 144 rounded clips, 96 overlapping tracks and 384 gradient/text segments. It continuously changes fractional positions, nested widths, readings and paint order. Pause, width locking, scene count and deterministic freeze controls are shared by both renderers. All ten fixtures are bundled for both comparison chats.

Three serial before/after runs use separately preserved release XCTest bundles with identical workload source and optimization settings. Every mode completes the same 60 mutation states and exactly matches layout, document job, document installation, scroll raster, tile job and compositor raster counts. Pixels are checked outside the timed interval. The portable shared-attribute test reduces reads from 480 to 120 for 120 nodes in normal mode, and from 240 to 120 in snapshot mode; this count reduction is not an end-to-end speedup measurement.

| Fixed workload | Before CPU ms/state | After CPU ms/state | Median CPU reduction |
| --- | ---: | ---: | ---: |
| Integer resizing | 39.838 | 40.297 | -1.2% |
| Fractional resizing | 39.411 | 39.168 | 0.6% |
| Contained tracks | 34.199 | 32.777 | 4.2% |

These changes are modest and the run ranges overlap. Integer and fractional resizing remain effectively unchanged within variation; the contained-track median is lower. Elapsed test time includes completion barriers and is not display latency. [Raw measurements, ranges, work counts, source/binary hashes and validation](results-2026-10-15-round7.json) are retained.

The live comparison uses the published baseline, the candidate native binary and sandbox-backed WebKit with identical HTML and sandbox settings. Three serial rounds reverse variant order in the second round; each uses 480 CSS pixels, eight seconds and a two-second warmup. CPU includes WebKit helpers and excludes WindowServer.

| Workload | Native before CPU | Native after CPU | WebKit CPU | Host callbacks/s, before / after / WebKit |
| --- | ---: | ---: | ---: | ---: |
| nested-clips | 109.16% | 109.26% | 117.38% | 56.7 / 56.5 / 60.0 |
| clipped-ticker | 159.33% | 159.62% | 129.46% | 55.7 / 55.4 / 47.8 |
| phase-grid | 141.42% | 141.93% | 129.90% | 49.7 / 49.7 / 21.6 |
| contained-ticker | 79.67% | 79.17% | 68.81% | 60.0 / 59.8 / 60.0 |
| order-book | 34.10% | 33.60% | 38.70% | 60.0 / 60.0 / 60.0 |

Free-running callbacks are sandbox scheduling measurements, not displayed frames or equal completed painting. The new fixture still stresses the native renderer below 60 callbacks/s. The clipped ticker and phase grid remain expensive; these results do not establish a universal advantage over WebKit.

Validation: 349 renderer/exclusion/shadow tests passed, with four optional benchmarks skipped; all six portable/Apple CMake suites passed. The new predicate matcher passed 20,930 standalone checks with AddressSanitizer and UndefinedBehaviorSanitizer, including an independent separate-walk oracle. All ten frozen full-widget images and all ten installed-window images have zero changed RGBA bytes against the baseline. Manual native/WebKit controls, scrolling, resizing and modal checks are recorded in the results. Only the renderer package and standalone lab were built; no full Telegram build was run.

## Width-only restyling and gradient clips — 2026-10-15

A guarded width-only update now recomputes the container's CSS without recursively restyling unchanged descendants. Normal layout still runs, including wrapping and percentage geometry. Independently changed descendant text, transforms and background colors still update; explicit width inheritance, variable-dependent styles, tables, SVG, ambiguous declarations and structural changes retain the existing path. Ordered non-width declarations must remain identical, preserving shorthand precedence. `LH_NO_SHALLOW_WIDTH_PATCH=1` disables the optimization for comparison.

The parity tests also exposed stale selector and generated-content results in the previous fallback: changes to an inline style could reach a second shortcut without rematching `[style]` selectors or rebuilding `content:attr(style)`. Guarded edits now request a fresh document before mutation, and the structural shortcut respects that decision. Tests cover the template path both enabled and disabled.

The new `gradient-clips.html` fixture defaults to 96 cards with 288 nested rounded clips, 192 moving tracks and 768 gradient segments. It combines resizing, fractional movement and changing readings with ordinary, reversed, alpha and diagonal gradients. Pause, width locking, card count and deterministic freeze are shared by both renderers. The same eleven fixtures are bundled for both comparison chats.

Three serial before/after runs use the unchanged 120-track renderer workload and separately preserved release XCTest bundles. Each run completes 60 mutation states in each mode, with identical layout, document job, document installation, scroll raster, tile job and compositor raster counts. State and pixel assertions run outside the measured intervals. CPU includes all process threads; elapsed test time includes completion barriers and is not display latency.

| Fixed workload | Before CPU ms/state | After CPU ms/state | Median CPU reduction |
| --- | ---: | ---: | ---: |
| Integer resizing | 40.571 | 38.465 | 5.2% |
| Fractional resizing | 40.276 | 39.778 | 1.2% |
| Contained tracks | 34.260 | 32.945 | 3.8% |

The gains are incremental; integer and contained-track run ranges overlap. An initial candidate unnecessarily excluded batches containing background-color changes and showed no equal-work improvement. The final admission rule accepts that existing update category while retaining its inheritance checks. [Raw measurements, ranges, work counts, source/binary hashes and validation](results-2026-10-15-round8.json) retain both the final results and the superseded diagnostic experiment.

The live comparison uses the same HTML, sandbox policy and prebuilt baseline/candidate binaries for three serial rounds, reversing order in round two. Each capture uses 480 CSS pixels, eight seconds and a two-second warmup. CPU includes WebKit helpers and excludes WindowServer.

| Workload | Native before CPU | Native after CPU | WebKit CPU | Host callbacks/s, before / after / WebKit |
| --- | ---: | ---: | ---: | ---: |
| clipped-ticker | 160.09% | 163.89% | 129.98% | 55.6 / 54.7 / 48.4 |
| gradient-clips | 113.64% | 113.44% | 153.24% | 49.2 / 47.9 / 44.2 |
| nested-clips | 109.15% | 109.16% | 119.26% | 55.8 / 55.3 / 60.0 |
| contained-ticker | 78.93% | 71.75% | 69.45% | 59.8 / 59.2 / 60.0 |
| order-book | 33.76% | 33.40% | 39.03% | 60.0 / 59.9 / 60.0 |

Contained-ticker native CPU falls by 9.1%, with the same median 481 layouts across each capture. Its mean style-patch time per layout falls from a median 1.561 to 0.504 ms. The clipped ticker's style-patch stage also becomes cheaper (2.328 to 0.744 ms), but its total native CPU rises by 2.4%: layouts rise from 259 to 273 and tile jobs per callback from 56.85 to 60.83. That case is not a total-CPU improvement. These live runs do not hold completed painting constant, and callback counts are not displayed FPS. The new gradient fixture already favored native application CPU before this change; it is not evidence of a new optimization gain. Heavy clipping still exceeds WebKit CPU in some cases.

A gradient-strip experiment was rejected and removed. It replaced repeated axis-gradient drawing with exact-phase one-pixel strips, with and without a bounded cache. The gradient matrix covered 1,440 cases with at most one channel value of difference; additional nested rounded-clip cases allowed a difference of two only near an antialiased edge. Three repeated fixed-work raster runs each completed 60 pre-laid-out states and checked every state outside timing. Direct Core Graphics rasterization used a median 6.623 CPU ms/state, strips 8.084 ms/state and cached strips 7.018 ms/state: approximately 22% and 6% regressions. Correct pixels alone did not justify keeping a slower path.

Validation: 406 renderer tests passed, including ten focused width-update tests; four optional tests were skipped and all six portable/Apple CMake suites passed. All eleven frozen full-widget images and all eleven installed-window images have zero changed RGBA bytes against the baseline. The gradient fixture has identical 960 × 7120 image dimensions in native and WebKit; its mean RGB difference is 0.225 out of 255. Manual checks in both standalone renderers covered pause/resume, count changes, width locking, freeze, scrolling and narrow-window layout, followed by repeated live-board modal opening and closing. Native manual previews used the detached background executor; capture benchmarks used the lab default executor. These interaction checks do not establish displayed FPS or exclude every transient hitch. Only the renderer package, portable CMake targets and standalone lab were built; no full Telegram build was run. The new shared fixture reaches both comparison chats on the next app build.


## Resolved fixed-flex layout and decoration stress — 2026-10-15

A clean, fixed-size flex subtree can now retain its layout when an ancestor resizes but its resolved containing-block inputs remain identical. The shared C++ path requires fixed pixel dimensions and outlines, normal sizing, a static bounded subtree, and no explicit owner min/max constraints, floats, positioned descendants or external intrinsic sizes. Existing dirty flags and viewport epochs still invalidate reuse. The normal layout path handles every excluded case. `LH_NO_FIXED_LAYOUT_REUSE=1` disables this addition; omit the variable to enable it.

The new `decoration-grid.html` fixture defaults to 96 panels with 576 rounded decorations, 96 moving indicators, 24 rotating panels and 24 reading changes per callback. It mixes opaque, transparent, clipped and rotated panels under continuous ancestor resizing. Pause, width locking, 24/48/96 panel selection and deterministic freeze are shared by both renderers. Its positioned descendants deliberately exercise the fallback; the test is not tailored to the new fast path. All twelve fixtures are bundled for both comparison chats.

The isolated document/layout benchmark runs 120 static tracks through the same 60 measured states after 12 warmup states, using one release test bundle with the addition disabled/enabled. Three serial runs alternate ABBA, BAAB and ABBA, giving six observations per mode. Median CPU falls from **67.851 to 30.872 ms per 60 states (54.5%)**; ranges are 66.516–70.576 and 29.977–31.369 ms. Layout misses fall from 129,720 to 28,920 and hits rise from zero to 14,400. All 60 measured states match exact full-widget pixels at 2× scale, layout signatures and visual bounds outside timing. This measures document construction and layout, not rasterization, complete widget CPU or display FPS.

The existing integrated fixed-work benchmark uses absolutely positioned tracks, which are excluded from this addition. It remains unchanged as a regression control. Each before/after run completes identical counts for all 60 states, layouts, document jobs, installs, scroll rasters, tile jobs and compositor rasters. Three serial rounds reverse order in the second round; CPU includes worker threads and pixel checks run outside timing.

| Fallback control | Before CPU ms/state | After CPU ms/state | Median CPU reduction |
| --- | ---: | ---: | ---: |
| Integer resizing | 40.029 | 41.139 | -2.8% |
| Fractional resizing | 40.125 | 39.230 | 2.2% |
| Contained tracks | 33.792 | 33.103 | 2.0% |

The ranges overlap, and these changes do not establish a general CPU improvement. The integer control has a higher median. [Raw results, ranges, per-state work, source/binary hashes and rejected experiments](results-2026-10-15-round9.json) retain the evidence, including the superseded early-guard comparison.

The live comparison uses identical HTML, sandbox policy, 480 CSS-pixel width, eight-second captures and two-second warmup. All 45 serial runs completed; variant order reverses in round two. CPU is percent of one core, includes WebKit helpers and excludes WindowServer. Callbacks measure host scheduling, not displayed frames or equal completed painting.

| Workload | Native before CPU | Native after CPU | WebKit CPU | Host callbacks/s, before / after / WebKit |
| --- | ---: | ---: | ---: | ---: |
| Decoration grid | 141.87% | 140.11% | 107.67% | 49.3 / 49.9 / 26.5 |
| Contained ticker | 71.87% | 71.54% | 68.40% | 59.2 / 59.7 / 60.0 |
| Clipped ticker | 162.16% | 164.90% | 130.01% | 54.7 / 54.3 / 48.8 |
| Live board | 22.97% | 23.06% | 29.35% | 60.0 / 59.9 / 60.0 |
| Reflow cards | 35.84% | 36.30% | 41.36% | 60.0 / 60.1 / 60.0 |

Median layout-stage wall time per call falls from 0.522 to 0.260 ms for contained tracks and from 1.477 to 0.710 ms for clipped tracks. This stage also includes scroll-offset restoration. Contained layouts are nearly equal (480 versus 481), while clipped layouts rise from 276 to 286. The clipped ticker's total CPU rises 1.7% despite its cheaper layout stage; this is not a total-CPU win. Rasterization and tile delivery remain substantial costs. Decoration-grid's main panels do not use the new reuse path. Neither its callback advantage nor any row here establishes 60 displayed FPS or universal superiority over WebKit.

Two prototypes were removed after adversarial tests:

| Rejected experiment | Favorable case | Regression that prevented shipping |
| --- | --- | --- |
| Cache combined rounded fill, border and shadow bitmaps | Repeated warm decorations used about 85% less raster CPU at 1× | Unique changing decorations used about 84% more CPU at 1× and 60% more at 2×; unique warm 2× decorations exceeded the 32 MiB cache and used about 57% more CPU |
| Convert scroll images to the display profile on the worker | Main-thread CPU fell about 57%; pixels remained exact | Equal-work total CPU rose about 24% and elapsed time about 65%; extra display buffers would also retain more memory |

The decoration probe checks all 192 measured states exactly except for a maximum two-byte difference confined to rounded antialiasing/shadow edges. The scroll probe compares canonical and destination pixels exactly. Correct pixels did not justify keeping either slower implementation.

Validation: 411 distinct functional renderer tests passed across the broad run and final focused run; five optional benchmarks were skipped in the broad run and the final fixed-layout benchmark was then run separately three times. All six portable/Apple CMake suites passed. Fixed-viewport descendant text, font and width mutations force invalidation, match fresh rendering, and permit reuse again after the mutation settles. All twelve full-widget captures and all twelve installed-window captures have zero changed RGBA bytes against the baseline. Manual native/WebKit checks passed panel-count changes, pause/resume, width locking, deterministic freeze, 480-to-390 CSS-pixel resizing, scrolling to the final panels and back, and repeated live-board modal opening/closing. Native manual previews used the background executor; timed capture runs used the lab default. These checks do not measure displayed FPS or exclude every transient hitch. Tall offscreen WebKit snapshots showed some lower alpha-panel backgrounds incorrectly, while manually scrolling to those panels showed the matching translucent blue appearance. Only renderer components, portable tests and the standalone lab were built; **no full Telegram build was run**. The new fixture appears in both comparison chats on the next app build.


## Scroll executor safety and tile-crossing stress — 2026-10-15

The reported `WidgetScrollLayer.ensureTiles` crash exposed a data race: rendering on the widget prepare executor modified the tile dictionary and pending set while asynchronous raster completions modified them on the main queue. Completions now return through the renderer's current executor, including stale-generation retries and installation. The raster queue only produces the image. Tests hold completions on a tagged serial executor and cover migration, consumed-document replacement and teardown.

A long background-executor run rejected an earlier performance candidate: JavaScript callbacks advanced while paint operations accumulated behind the existing rendering budget. Callback rate therefore overstated visible progress, and the process temporarily retained substantial queued work. The final renderer waits to post another animation callback while paint operations are held, with an exception for answering user input. It preserves the outstanding request and resumes after the queue drains. CPU limits are unchanged. A regression test verifies both the wait and automatic resume, and existing compositor/input-frame tests still pass. The final background snapshot and installed window at state 5168 are byte-identical to the settled reference obtained with throttling disabled for diagnosis. The earlier candidate measurements are retained as superseded evidence, not accepted presentation improvements.

A strict coverage test also found a resize bug: changing the number of tile columns could leave an old tile at the wrong position, overlapping visible content. Tiles whose stored frame disagrees with the new grid are retired. If that empties the grid, visible tiles are filled immediately, including when an earlier generation still has pending work. A delayed-worker test failed with zero visible coverage before that follow-up and now passes with exact pixels.

The new `tile-crossings.html` fixture has 12, 24 or 48 panels, each with 1025×513 scroll content, nested rounded clips, two overlapping alpha/text tracks and 192 text lines. At 48 panels it contains 9,216 lines and stays within normal sandbox quotas. Integer, fractional and paint-churn phases cross both tile axes; separate controls replace owners, resize, freeze and advance a deterministic state. Source and bundled copies are identical. All thirteen fixtures are available to both comparison chats on the next app build. State labels describe requested state, not independently acknowledged presentation.

Profiling the new fixture found repeated descendant-geometry enumeration after each individual scroll-position property. Contiguous position requests now share one final geometry refresh. Offsets and clamping still apply in order; `scrollIntoView` flushes the pending group before revealing its target. Individual user scrolling retains immediate refreshes. No geometry cache survives a layout change.

Three independent ABBA component runs apply 48 position requests to 24 owners and 48 descendant clips per state, after 12 warmup states. Each run completes the same 60 states and checks exact geometry, offsets and hit regions outside timing. Geometry CPU falls from a median **303.637 to 8.386 ms per 60 states (97.2% less)**. Whole-document scroller reads fall from 2,821 to 60. This component measurement excludes rasterization and presentation.

Two smaller raster changes are retained. Scroll capture uses the existing text batcher only for bounded subtrees without text shadows, preserving paint and clip barriers. Its 216 pixel cases cover fractional tile phases, overlapping alpha text, transforms, positioned groups, decorations and fallback glyphs at 1×, 1.5× and 2×. In a single ABBA raster probe, dense text CPU falls about 16.5%; the sparse ticker shows no improvement. A private completed BGRA bitmap also transfers immutable buffer ownership to its image provider. The consumed-image probe draws retained images before reading their bytes, so both the original snapshot and new path incur their real memory cost. For 1025×513 dense images, median capture-plus-consumption CPU falls from 67.140 to 55.827 ms; both paths show the same 34.531 MiB post-draw footprint increase in that probe. Tiny sparse images can be slightly slower. These are component results, not whole-renderer speedups or memory savings.

The fixed renderer control uses preserved before/after release test bundles and unchanged workload source. Three serial rounds reverse variant order in round two. Each mode completes 60 states with identical layout, document job, installation, scroll-raster, tile-job and compositor-raster counts; pixels are checked outside timing.

| Fixed workload | Before CPU ms/state | After CPU ms/state | Median CPU reduction |
| --- | ---: | ---: | ---: |
| Integer resizing | 39.095 | 38.314 | 2.0% |
| Fractional resizing | 40.485 | 38.701 | 4.4% |
| Contained tracks | 31.709 | 32.892 | -3.7% |

The fixed-work measurements are incremental and their ranges overlap. Integer and fractional resizing use about 2.0% and 4.4% less CPU; contained tracks use about 3.7% more in this run. They do not establish a benefit for every workload. The live comparison uses identical HTML, normal sandbox policy, 480 CSS pixels, eight-second captures and two-second warmup. All 45 runs execute serially, reversing order in round two. CPU is percent of one core, includes WebKit helper processes and excludes WindowServer. Host callbacks are not displayed frames, and these runs do not hold completed painting constant.

| Workload | Native before CPU | Native after CPU | WebKit CPU | Host callbacks/s, before / after / WebKit |
| --- | ---: | ---: | ---: | ---: |
| tile-crossings | 73.16% | 8.14% | 101.83% | 24.2 / 0.2 / 60.1 |
| clipped-ticker | 164.55% | 162.64% | 130.02% | 54.0 / 38.1 / 48.3 |
| contained-ticker | 72.63% | 72.47% | 68.90% | 59.7 / 59.8 / 60.0 |
| live-board | 24.48% | 24.50% | 30.76% | 60.0 / 60.1 / 60.0 |
| reflow-cards | 36.37% | 36.70% | 41.31% | 59.9 / 60.0 / 59.9 |

These live CPU figures cannot be read as an equal-work speedup. The final renderer deliberately stops producing animation callbacks while paint operations are held, so the callback rate changes with backpressure. The clipped ticker remains expensive; this round does not establish a universal advantage over WebKit or 60 displayed FPS.

| Workload | Before footprint MiB | After footprint MiB | WebKit footprint MiB |
| --- | ---: | ---: | ---: |
| tile-crossings | 446.0 | 475.3 | 277.9 |
| clipped-ticker | 129.8 | 137.3 | 262.0 |
| contained-ticker | 122.5 | 130.3 | 287.6 |
| live-board | 78.3 | 78.3 | 230.3 |
| reflow-cards | 85.3 | 85.5 | 358.6 |

Memory depends on the workload and completed updates; some cases retain more than before. Do not substitute the isolated bitmap ownership result for the whole-process figures above. [Raw observations, ranges, work counts, hashes, component probes and validation](results-2026-10-15-round10.json) include the initial pilots and final comparisons.

Validation: **633 package tests passed, eight optional benchmarks skipped, zero failures**; the geometry benchmark ran separately three times. All six executor/coverage tests pass. All 13 frozen full-widget images and all 13 installed-window images have 0 and 0 changed RGBA bytes respectively against the baseline. Manual native/WebKit checks covered live animation, pause/freeze/step, panel-count changes, owner replacement, 480-to-390 CSS-pixel resizing and scrolling through all 48 panels. The native standalone app used its background executor; timed captures used the lab default executor. The extreme tile-crossing case still reaches the renderer CPU budget and is not smooth at its default load. Backpressure bounds its animation work rather than relaxing quotas or claiming a display-speed win. Only the renderer package and standalone lab were built; **no full Telegram build was run**. The paused Telegram process continues to contain its previously built renderer until the next app build.

## Bounded clipped rasters and dense panels — 2026-10-15

Unscrolled `overflow:hidden` subtrees with at most 64 DOM nodes now rasterize a bounded area around their viewport. Raster capacity includes 25% headroom, rounded to 64 CSS pixels, and shrinks only below half capacity. Small animated resizes reuse the existing tile dimensions. Capacity changes and the first scripted scroll fill visible coverage immediately, even when an older raster job is pending. Wheel scrollers, previously scripted scrollers, and dense subtrees keep full coverage. `TW_CLIP_UNSCROLLED_RASTERS=0` disables the addition. Sandbox and renderer CPU limits are unchanged.

The new `clipped-panels.html` fixture contains 12, 24 or 48 large translucent text panels, each with 1537×769 content behind a small rounded viewport. It combines ancestor resizing, translated gradients, text replacement and rotated shadowed overlays. Controls pause, rebuild, reveal distant content and select a deterministic state. Building 48 panels in one event exceeded the normal JavaScript event quota during manual testing; that control now builds four panels at a time. Both comparison chats receive identical HTML on the next app build.

The fixed-state raster benchmark uses one release test bundle, three ABBA/BAAB/ABBA runs, 12 warmup states and 60 completed states per mode. Process CPU includes the raster worker. Document construction, layout and installed-pixel comparisons occur outside timing. Median raster CPU falls from **489.879 to 132.089 ms per 60 states (73.0% less)**; ranges are 487.842–535.297 and 127.910–157.108 ms. Raster jobs fall from 120 to 60, and total raster area from 15,728,640 to 2,211,840 CSS pixels squared. This is a component saving, not whole-widget CPU or display speed.

```sh
TW_SCROLL_VIEWPORT_BENCH=1 swift test --package-path third-party/twidget -c release --filter ScrollViewportRasterTests/testViewportRasterBenchmark
```

Three serial live rounds compare the preserved baseline, final native candidate and sandbox-backed WebKit at 480 CSS pixels, eight seconds with two seconds of warmup. Variant order reverses in round two. CPU includes WebKit helpers and excludes WindowServer; callbacks are host scheduling counts, not displayed frames or equal completed painting.

| Workload | Before CPU | After CPU | WebKit CPU | Callbacks/s before / after / WebKit |
| --- | ---: | ---: | ---: | ---: |
| Clipped ticker | 161.52% | 151.23% | 130.50% | 37.0 / 39.3 / 48.1 |
| Live board | 20.32% | 17.76% | 26.25% | 60.1 / 60.0 / 59.9 |
| Dense clipped panels | 47.75% | 140.90% | 90.69% | 1.5 / 4.4 / 60.0 |

The ticker uses **6.4% less CPU**, advances **6.2% more callbacks**, and its median footprint falls from **137.4 to 118.3 MiB**. The live-board ranges overlap substantially. Dense panels use the unchanged full-raster path and remain slow: native callbacks range from 1.3–4.6 before and 3.4–4.5 after as the existing sustained budget changes throttle state. Their different medians are not attributed to this optimization. Single-run controls retain approximately 60 callbacks/s: contained ticker CPU 71.52→73.85%, order book 29.98→28.45%, reflow cards 34.75→33.24%. These controls do not establish precise CPU gains or universal regression freedom.

Two wider experiments were rejected. Direct IOSurface scroll tiles shifted work toward WindowServer without a clear total saving. Unrestricted viewport cropping reduced raster cost and memory but made the dense panels advance more slowly under the unchanged throttle policy. Spare capacity fixed repeated synchronous refills at size boundaries; the 64-node admission limit excludes the remaining dense scheduling regression. The heavy fixture remains as a reproducible bottleneck, not a claimed WebKit win.

Validation: **639 package tests passed, nine optional tests skipped, zero failures**; the raster benchmark ran separately three times. The 21 scale/resize pixel cases have no flat-interior differences, with maximum channel delta 8/255 confined to changing edge pixels. All 14 full-widget captures and all 14 installed-window captures have zero changed RGBA bytes against the baseline. Manual native/WebKit checks covered panel-count changes, pause/resume, reset/freeze, distant content, resizing, and scrolling through all 48 panels and 120 ticker rows. The final batched 48-panel control also passed a separate frozen comparison; live timings used the unchanged default 24-panel workload before that control revision. Dense native panels still advance slowly and can show different tile generations during motion. The earlier integrated fixed-work attempt completed all states and pixel checks, but one control varied between 60 and 61 layouts; its runner rejected equal-work attribution for that mode. [Raw observations, hashes, ranges, rejected experiments and manual checks](results-2026-10-15-round11.json) retain these limitations. Only renderer components and the standalone lab were built; **no full Telegram build was run**.
