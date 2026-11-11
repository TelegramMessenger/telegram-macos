# Widget review harness

Run from any directory. Builds and module caches persist under `.build/widget-review/cache`; each run gets fresh logs, payloads, revision/dirty-state metadata, timings, and a machine-readable verdict. No app launch, account access, or messages are part of these commands.

```sh
python3 tools/tests/widgets/run.py
python3 tools/tests/widgets/run.py --suite core
python3 tools/tests/widgets/run.py --suite native --suite host --suite conformance
python3 tools/tests/widgets/run.py --suite all
```

| Layer | Checks |
|---|---|
| `fast` (default) | Harness verdict and packaging regressions; real Swift payload decoding, sizing and resize-anchor code in Debug; deterministic bot probe and five local chat fixtures |
| `core` | All three TypeScript projects; core and web unit suites through QuickJS; conformance widget payload sizes; the review probe's counter/storage/resize/theme/data behavior |
| `native` | WidgetSandbox and twidget Swift package tests, including the actual native renderer; ArenaSlab's process-wide counters run in a separate fresh test process; opt-in conformance/visual tests remain separate |
| `host` | HTMLBubbles storage, state/theme mapping, action gating and resize/recreation regressions; links the app's prebuilt arm64 mozjpeg library |
| `conformance` | Every automatic widget and declared theme at width 390 through the native renderer; pixel judging against upstream references; complete-run audit |
| `stress` | All 127 upstream stress widgets in measure and production passes through the native renderer; upstream run files and report. `--stress-smoke` shortens warmup/measurement for integration checks. |
| `web` | Headless Chromium attacks, activation, SDK, lifecycle and gestures on iframe and Shadow DOM renderers |

Install the sandbox's dependencies following its [README](../../../third-party/widget-sandbox/README.md). Core checks use `node --import tsx` directly to avoid tsx's IPC listener and package-manager startup. Unit files run sequentially because concurrent QuickJS/browser processes can consume a test widget's CPU quota and create false timing failures. Web checks require the repo's pinned `corepack pnpm`, installed Playwright Chromium, and permission to start local servers/browser processes. Native checks require Xcode/macOS. Failed or unavailable commands stay red and independent steps continue. Each command has a 30-minute timeout; `--timeout SECONDS` changes it.

The web unit files test optional Blitz/litehtml WASM prototypes. Without their built assets Node can report zero tests with a zero exit code; the runner rejects that result. Build those prototypes using the sandbox's instructions when testing them, or record this coverage gap separately from the native Mac renderer's results.

ArenaSlab's exact reclamation assertions measure the whole process's tagged memory. They can fail when unrelated runtimes from earlier tests are freed and the total drops below its initial baseline. The native layer partitions the suite and runs ArenaSlab separately, with its assertions unchanged; those tests are executed, not omitted.

`steps.json` is updated after each step; `summary.json` is the final verdict, also retained on interruption. A zero exit status means the selected automated layers passed. Other platforms, bot/server delivery, manual visual review and accessibility remain explicitly outside that verdict. Test skips in native package logs still need review. `conformance` independently rejects absent/duplicate runs, unexpected deaths/unloaded widgets, skipped/unknown/unfinished or missing declared checks, missing pixels, undelivered actions, runtime errors, and unexpected passes. The upstream pixel report additionally fails on in-profile failures or partial results. Expected fatal-limit cases require the manifest `stops` prefix in the death reason; their pre-stop load/status/checks are not completion criteria. The XCTest writing a run file is insufficient by itself. Web checks force strict policy, require their own server instead of reusing another checkout, and reject skipped or missing suites in the JSON report.

`--output DIR` selects a new report directory (an existing directory is refused to prevent stale evidence). `--cache DIR`, `--renderer-scratch DIR`, `--sandbox-scratch DIR` and `--host-scratch DIR` allow reusing a previous build. Do not share a scratch directory with an active Swift build. `--suite` can be repeated; `all` selects every layer. A failed layer can be rerun alone after reading its log.

The manifest's check names come from a plain browser without the SDK. Six context widgets take a different branch in a sandbox: `sandbox-checks.json` records that branch's exact assertions, derived from each widget's `E` JSON and its request checks, and pins the HTML SHA-256. A changed fixture makes the audit fail until those expectations are reviewed. Pixel-only widgets need every declared pixel stage, without invented self checks.

## Real chat and bot check

The fast run writes `review.tgw` (zlib level 9), its SHA-256 manifest and the five synthetic-chat cards. To pack another widget:

```sh
python3 tools/tests/widgets/pack.py tools/tests/widgets/fixtures/review.html --output /tmp/widget-review.tgw
```

The packer rejects invalid UTF-8, NUL, empty source and the server's 32 KiB raw / 4 KiB packed limits. These are authoring checks, separate from the client's payload decoder. Send the `.tgw` document to `@asmico_widget_bot`, then test the returned widget in Telegram. Compare its exported HTML hash with `htmlSha256` before attributing a result to this source. Sending a file and receiving a reply do not prove the controls work.

| Scenario | Expected result |
|---|---|
| Counter; scroll several screens away and back; restart app | Count persists for this message; another message/forward starts with its own storage |
| Reset counter | Count becomes zero and stays zero after reload |
| Toggle anchor, add/remove rows in the middle of a long chat | Chosen edge stays in place; no blank frames or jumps; repeat at chat boundaries |
| Click-drag blue track; wheel/trackpad vertically over it | Counter follows total horizontal movement; vertical input scrolls chat |
| Drag selected paragraph; Copy counter | Native copy works; button copies the counter text and shows a toast |
| Light/dark, chat font size, narrow/wide chat, Reduce Motion, RTL | Content remains legible and correctly clipped; theme/status updates |
| Forward, caption edit, deletion, clear cache, account switch | Correct author/context, independent storage, no stale state or cross-account data |

Use the upstream [client checklist](../../../third-party/widget-sandbox/docs/client-checklist.md) and [SDK visual set](../../../third-party/widget-sandbox/packages/conformance/visual/sdk/README.md) for bot state edits, requests, shared polling, denied requests, inline previews and the network marker; the probe does not ask the bot for data. Resource death/restart, off-screen pause, gestures and limits also have native/core tests, but should be exercised in a real chat before shipping. Record app build, OS, source hashes, exact steps and expected/actual results. UI automation requires the user's explicit permission; the local commands above do not control the user's Mac.

## Review loop

1. Read both submodule READMEs, sandbox CONTRIBUTING and the integration/profile docs at the pinned revisions.
2. Run `fast`, then the layer nearest the changed code. Reproduce a failure before fixing it and keep the regression.
3. Fix one behavior per commit. Shared sandbox changes require all glue copies, rebuilt native bundles and the checks specified in CONTRIBUTING.
4. Run `native` plus `conformance` for renderer/integration changes; add web attacks on both renderers for shared JS changes. Keep failures, skips and environment limitations visible.
5. Use the same payload for before/after real-chat checks. Commit only the task's files and submodule pointers; leave unrelated working changes alone. Do not push as part of a local review.

## Twidget exactness gate

The renderer README requires TwidgetLab, including fresh-render, fresh-parse and recorded-click replay checks. Keep this gate separate from CPU-sensitive native tests so compilation or capture does not contaminate their short frame deadlines.

Choose a fresh trace/output directory for each run; do not combine frames from earlier captures with a new replay.

```sh
swift build --package-path tools/perflab/TwidgetLab --scratch-path .build/widget-review/cache/lab --disable-sandbox -j 4
mkdir -p .build/widget-review/lab/morph/frames
TW_VERIFY=1 TW_PATCHCHECK=1 .build/widget-review/cache/lab/debug/TwidgetLab capture tools/perflab/TwidgetLab/widgets/morph.html --renderer lite --seconds 2 --width 390 --click '45,25;130,25;45,25' --dump .build/widget-review/lab/morph/frames --out .build/widget-review/lab/morph
.build/widget-review/cache/lab/debug/TwidgetLab replaycheck .build/widget-review/lab/morph/frames --width 390
```

Also capture `raf.html`, `scripted.html` and `cssanim.html` from the same widget directory in light/dark themes. Inspect the capture logs: rendering must complete without widget death/error, verification must process nonzero frames with zero mismatches, and patch checks must retain zero differences. Replay should include patched frames, not just an empty or initial document. Preserve logs and traces; a tool's zero exit status alone does not prove these gates ran.

## v0.3.0 native stress kit

```sh
python3 tools/tests/widgets/run.py --suite stress --stress-smoke
```

The smoke run uses 100 ms warmup and 1100 ms measurement per widget and skips cooldowns. Omit `--stress-smoke` for the kit's default 2 s warmup, 10 s measurement and cooldowns. The full two-pass kit takes about an hour and has its own `--stress-timeout` (7200 seconds by default). Both use the Debug package and the production binary-ops/canvas-words/morph feature set, with one live widget at a time; measure uses the kit's explicit compat configuration, production uses strict defaults. These runs do not provide optimized-build benchmark certification. Run files retain stops, errors and diagnostics. Unavailable render timing, refresh rate and dropped-frame measurements are null. No results are sent automatically.

The v0.3.0 desktop conformance audit permits only `auto/17-drag-hover`'s explicit no-touch-input skip and its hover-media branch skip, with exact checks, reasons and fixture hash pinned in `sandbox-checks.json`. The framework intentionally rewrites hover/pointer media queries to never match because they are outside profile 1; pointer event and drag checks still have to pass. All other skipped/unknown checks remain failures.
