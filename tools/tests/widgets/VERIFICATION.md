# Local widget review — 28 October 2026

The fixes restore behavior already specified by widget profile 1. The review covers both submodules and the macOS integration. Everything is committed locally; nothing was pushed. Existing unrelated changes and the sandbox's three untracked `.html.orig` files were preserved.

## Latest rebase review

Our nine twidget commits were rebased onto the fetched `origin/main` at `538e420`. The eight production/test patches remain identical; the verification documentation commit was refreshed with these new results. The incoming portable canvas change is compatible with the pinned sandbox v0.2.3 shim, which already converts text arguments. The sandbox source and bundles did not change during this rebase. Host history now references the corresponding rebased submodule commits; older commits and unrelated working changes are preserved.

**Our changes pass the scoped README/AGENTS/CONTRIBUTING/docs audit. The rebase is complete, and our production/test patches remain unchanged.** Broader runtime checks below are not fully green; those observations occur in unchanged paths and are not established regressions from our changes.

| Fresh check | Result |
|---|---|
| Affected native tests | 24/25 pass. Packing in-flight checkbox ink height is 13 px against the unchanged 18 px minimum. All 12 gesture/input cases pass. |
| Isolated packing capture | Pixel and geometry assertions pass; one sample arrives 30.4 ms after its target against the unchanged 25 ms allowance. The failed broad capture was not recorded, so its cause remains unproven. |
| Rebuilt TwidgetLab | 12/12 gates pass: 1,142 fresh-render frames, 285 fresh-parse patches, 108 replay frames (98 patched); zero differences. |
| Portable Release core | CMake build and CTest pass; 329 assertions pass, zero failures. |
| Native automatic conformance | 53/53 runs complete without runtime errors; 608 checks pass, one fails, two skip. Upstream judge: 173 in-profile features pass, one partial, 14 host features untested. |
| Theme contract observation | In `auto/20-client-behaviour`, `themeChanged` sees the dark palette (`#212121`) while its immediate CSS query still reads light (`#ffffff`). Its theme paths and the runner's theme actions are unchanged by our patches and rebase. Exact attribution remains open. |

Post-click packing sampling/assertions are unchanged by our patches; the size-adoption correction only affects initial setup. Possible coordinate/raster generation mismatches are diagnostic hypotheses, not established causes or reasons to waive the failure. Existing host/shim ordering can explain stale theme queries, but was not changed within this review. No deadline, pixel threshold, invariant or shared policy was relaxed.

Fresh raw logs, captures, upstream judgments, coverage audit, range-diff and commit mapping are retained under `rebase/`. Earlier green results remain separately available. The previous full Telegram app build predates this rebase; the fresh builds above validate the Lab and portable core. These results do not establish release or distribution readiness.

## Changes and contract audit

| Task | Local commit | Contract and regression |
|---|---|---|
| Clear widget storage in order with reads/writes | Host `f28e267b8` | Clearing could reload old disk state before queued deletion. Same reproduction fails before and passes after; three native storage tests cover clear/reload, subsequent writes and peer/session isolation. |
| Include `<html>` in gesture claims | twidget `3884569` | Aligns the Swift ancestor walk with the existing shared GesturePolicy and portable C++ renderer. Vertical drags retain the existing chat ownership rule. |
| Preserve accumulated pointer movement | twidget `df2e074`, sandbox `ebe293e` | Retains latest coordinates and sums all coalesced deltas. Portable C++ already does this; shared JS is rebuilt into all native renderer bundles. Positive/negative bursts and frame/release flushes have regressions. |
| Preserve native click detail | twidget `3a0199a` | Uses native click counts and the existing shared double-click verdict. Gesture thresholds are unchanged. |
| Preserve pointer/mouse event order | twidget `b56fbb6` | Uses insertion order as the shared JS and portable C++ renderer do. The old dictionary delivered reversed events in 5 of 12 reproduced sessions. |
| Configure conformance message context | twidget `c734e69` | Passes the manifest context/data/viewer and mock bot answers. The private context case had five failures with the old runner and passes with the corrected setup. |
| Correct stale transform-promotion expectation | twidget `68656be` | Baseline `f771eca` already documents promotion on the first update. The test now checks that behavior while retaining pixel and demotion checks. Production promotion behavior is unchanged. |
| Add an explicit fixture-initialization diagnostic boundary | twidget `f1ea2c9` | An end-of-HTML marker reaches the rendered document before initial ink assertions. It is diagnostic: the marker alone did not resolve the packing ink failures; the measured size-adoption correction below does. |
| Wait for measured height adoption before initial pixel capture | twidget `ac80728` | Captures could crop a 418 px document to the view's 50 px placeholder height. Setup now requires the diagnostic and adopted view heights to match current clamped document height. The exact seven-test failing sequence passes; every ink threshold and post-click deadline remains unchanged. |
| Stabilize clock differential fixture | sandbox `fff9074` | Freezes dates only inside test fixtures; binary/JSON equality assertions and production clocks are unchanged. |
| Capture the conformance drag target | sandbox `1702905` | Mouse release previously landed outside the small element, leaving two checks pending. Uses existing pointer capture; four checks pass on native, iframe and shadow. Only this authored fixture and builder-generated metadata changed. |
| Restore TwidgetLab build | Host `953b9aa8e` | Adapts Lab-only preparation calls and comparisons to the existing typed theme API. |

The sandbox contribution rules were read before editing. Shared renderer changes include a failing-then-passing unit test, guide/changelog/CLAUDE updates, typechecks, unit tests, attacks on both web renderers, conformance, affected compatibility/gesture corpora, and regenerated iOS/macOS, Android and desktop bundles. Rebuilt sandbox/validator bytecode remained identical. No new profile feature or glue policy was introduced; native scrolling, TaskRenderer, runtime quotas and profile membership retain their existing behavior. Changes to the native renderer are platform implementation corrections, rather than changes to the five host-glue policies.

Final prescribed checks used cached pnpm 12.10.1 through a temporary `corepack` shim and Node 26.12.1. Typecheck, unit and all three native bundle build commands passed; all 15 generated JS/QBC files match both their pre-build hashes and committed sandbox HEAD. Existing installed dependencies were used, with implicit installation disabled and no package/lock changes. Earlier checks used a fallback pnpm 11.25.0 shim because `corepack` was absent; the final exact-manager rerun supersedes that tooling gap. These commands were repeated after the history correction at sandbox `1702905`; `compliance/pinned-verification.json` records the final results, output hashes and 388-word guide in each of the three behavior commits. The earlier `widget-sandbox-pinned-verification.json` and its logs remain as historical evidence.

## Compliance of our unpushed commits

The audit is limited to our changes after twidget `538e420`, sandbox `88285a3` and host `49e93cf8b`. Older commits and existing unrelated failures were not repaired as part of this audit.

The sandbox movement commit originally expanded the author agent block to 439 words, violating its enforced 420-word limit. Its later 388-word correction is folded into that same movement commit, together with the regression's use of real compatibility `MouseEvent` objects. Clock-fixture and conformance-capture behavior remain separate commits. The movement regression checks independent pointer IDs and the mouse path without a pointer ID, with both release and animation-frame flushes; it fails against the previous renderer and passes with the fix.

| Applicable rule | Evidence for our changes |
|---|---|
| Shared renderer source, regression, all native bundles together | Movement commit includes the test, iOS/macOS, Android and desktop renderer bundles; all three prescribed builders reproduce the committed outputs. Sandbox/validator bytecode is unchanged. |
| Author contract and release notes | Movement semantics are documented in the guide and its bounded agent block, `docs/changes.md` and `CLAUDE.md`; no profile feature was added. |
| Typecheck, unit, attacks, conformance and affected corpora | Pinned-manager typecheck and 723 core tests pass; both full web attack suites pass 126/126; native and web conformance, compatibility and gesture results are recorded below. |
| Every changed glue policy in every copy | No glue policy, protocol, SDK limit, native scrolling or TaskRenderer behavior changes. Swift renderer corrections match the existing portable implementation. |
| twidget exactness gate | Recorded TwidgetLab fresh-render, fresh-parse and replay checks all pass with zero differences; affected native tests pass. The macOS corrections and measured results are also recorded in twidget's own `docs/CONFORMANCE.md`. |

Only our local history and submodule references were adjusted. The original histories have local recovery branches; no remote ref was changed. This compliance assessment does not claim that unrelated baseline suites or manual product scenarios are fully verified.

## Earlier verification

This table preserves the earlier runs. The fresh post-rebase results and open failures are listed above; these historical passes are not a current push sign-off.

Environment: macOS 27.0.1 (26A434), Apple silicon, Debug app build 283403. Full app builds used `CODE_SIGNING_ALLOWED=NO`; these checks do not establish signing/distribution readiness.

| Check | Result |
|---|---|
| Full Telegram Debug build, including final ordered-input fix | Passed; `widget-review-app-build-ordered.log` |
| Focused macOS host package | 14/14 passed; storage and resize/recreation included |
| Core unit suite | 723/723 passed sequentially; all three TypeScript projects typecheck |
| Diagnostic widget | Light/dark counter, storage preload/commit/reset, row changes, resize anchor, data/theme updates and denied synthetic clipboard passed |
| Fast review harness | 17 harness regressions plus real Swift payload/resize checks, packaging and fixture preparation passed; warm run about one second |
| Shared JS security | Shadow 126/126; clean full iframe rerun 126/126, zero skips/retries/failures. All leak checks had zero canary hits/outside requests. The earlier iframe 125/126 run and isolated retry remain as historical evidence; no security assertion or policy was changed. Final rerun: `compliance/iframe-attacks.json` and `.log`. |
| Affected corpora | Compatibility 20/20; gesture corpus 8/8 |
| Web gesture suite | Clean full rerun 28/28 on iframe and shadow, zero skips/retries/failures; original thresholds and assertions retained. Earlier 27/28 run and isolated retry remain in the evidence. Final rerun: `compliance/gestures.json` and `.log`. |
| Owned strict browser harness | Six representative activation, lifecycle, resize, storage and locale checks passed, zero skipped; fresh app server and no reuse of another checkout |
| Native automatic conformance | 53/53 completed without death/runtime errors; 609 checks pass, two optional checks skip. Upstream report: 174 in-profile features pass, zero partial/fail, 14 host features untested. |
| Native input exactness instrumentation | `TW_VERIFY=1 TW_PATCHCHECK=1`: 11 gesture/interaction tests passed without mismatch messages |
| Broad twidget native suite | 759 cases, 11 skipped; the last unpartitioned run recorded three failed cases/six assertions. Two packing cases were traced to initial capture before height adoption and corrected; all seven combined Arena/InFlight/Stable cases then passed. The exact one-case Arena class separately passed in a fresh process (0.388 s), retaining every assertion. Earlier failures remain in the evidence; no later fully green unpartitioned run is claimed. |
| TwidgetLab capture/replay exactness | 12/12 steps passed: 1,146 fresh-render frames, 289 fresh-parse patch checks, 108 replay frames including 97 patched frames; zero differences. Raf, scripted motion, CSS animation and morph clicks cover both themes. |

Broad runs and isolated retries are retained together. Early restricted runs produced AppKit/WebKit permission failures; native rendering checks passed outside that restriction. Early concurrent runs also produced timing/query-budget failures; runtime quotas were retained, and the quiet automatic conformance run completed cleanly.

The packing diagnosis was measured directly: documentView was 440×50, document height 418, and the checked box began at y=124.97. Computed and freshly parsed green colors were correct; the snapshot clipped the box. A script-completion marker alone did not fix this, and its earlier causal explanation was corrected. Requiring actual height adoption fixes that initial capture boundary without changing production layout or polling for a passing pixel value.

The arena test compares a process-wide VM tag to its initial byte count. In the broad sequence, unrelated runtime reclamation lowered the count from 3,129,344 to 1,409,024 bytes and invalidated the exact-baseline assumption. No allocator or memory assertion was changed. The harness runs the other renderer cases and this exact one-case class in separate processes, so all cases still execute with their original assertions.

## Coverage still open

- `WidgetSandbox`'s full native suite ran 268 tests and retains the documented macOS 27 JavaScriptCore/CLDR plural-reference mismatch. Three other timing/differential cases passed isolated. This review does not change correct plural rules to match that OS reference.
- The optional Blitz/litehtml WASM unit files execute zero tests because their prototype assets are absent. The harness now rejects that zero-test exit instead of labeling it a pass.
- Web automatic conformance retains three documented partial features: animation event metadata, off-DOM canvas drawing, and computed-style shorthands. Both web renderers load all 53 runs without runtime errors.
- Native strict coverage audit retains two fixture skips, visible in `coverage-audit.json`: the hover capability query returns false despite separate passing native hover interaction tests; the touch-event check has no native touch input. The 14 host features outside automatic conformance still need their client/bot scenarios.
- The generated `.tgw` is ready, but no live `@asmico_widget_bot` round trip was performed. Manual Telegram UI review, accessibility, forwarded/inline/server state scenarios, and iOS/Android/desktop device execution remain unverified. No computer-use tools were used.

## Reproduce and inspect

Run the commands in [README.md](README.md). The fast entry point is `python3 tools/tests/widgets/run.py`; broader layers are selected explicitly. A broad selected layer stays red when tests are missing, skipped unexpectedly, incomplete or failed.

Local evidence is under `.build/widget-review/evidence/`, including raw/before conformance runs, upstream judged reports, failed broad logs, isolated retries, strict coverage audit, host tests, build logs and the independently owned browser configuration. Individual harness runs retain commands, revisions, dirty state, elapsed times, logs and manifests under `.build/widget-review/runs/`.

The probe source is [fixtures/review.html](fixtures/review.html); `pack.py` writes level-9 zlib and raw/packed SHA-256 manifests. Follow the manual/bot matrix before calling the widgets fully verified or shipping them.
