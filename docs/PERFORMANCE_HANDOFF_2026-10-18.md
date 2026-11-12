# Performance engine handoff — 2026-10-18

## Start here

The user requested saving the work and goal for another model. Stop new optimization work at this handoff. Continue when the user gives this document to the next model.

Repository: /Users/renoir/projects/Telegram/telegrammacos
Branch at handoff: sam/qr-studio-prefetch (9 commits ahead of origin).
HEAD: 26081dabb (Record waveform layer validation and allocation evidence).
Working tree contains intentional UNCOMMITTED implementation and tests. No push was performed. Do not discard it or mistake it for fully validated code.

A recovery snapshot is in tools/perflab/HandoffSnapshot/results/2026-10-18/. It contains a binary Git patch, copies of changed/untracked files, ignored evidence directories, newly archived temporary diagnostics, a hash manifest, Git state and the persistent goal JSON. The source archive is a recovery backup, not something to apply over the live tree by default. Inspect differences first.

Read the root AGENTS.md instructions. No new code comments except task markers. Keep telegram-ios unchanged. Preserve unrelated concurrent changes. Use fresh isolated mini-app snapshots and honest correctness/performance evidence. No current authorization to push.

## Persistent goal

The user explicitly requested pausing for the handoff. The existing goal is PAUSED, saved verbatim in goal.json. Resume only when the user asks; do not create a duplicate goal or mark it complete. The recovery archive preserves the earlier pre-pause checkpoint; this live document and goal.json contain the updated status.

Objective: find similar improvements across the app, especially TGUIKit, chat, peer info, media and other screens; improve performance and reduce memory; validate carefully; look for further waste after each run. Chat scrolling and message rendering are especially important. The user previously requested sustained work until told to stop, for at least nine hours. That duration has already been exceeded. This handoff request takes precedence over starting more work now.

No reliable percentage of full ChatRowView migration is established. Do not invent one. We are migrating bounded pieces with native fallbacks, not claiming complete chat-row coverage.

## Execution state

All three reusable agents were completed at handoff and were told to make no further edits/builds:
- /root/waveform_review: inline emoji implementation, eligibility and performance fixes.
- /root/spoiler_lifecycle_review: reactions migration and pixel diagnostics.
- /root/formatted_date_review: avatar tracking reuse and profiling fixture.

User explicitly authorized parallel agents. Keep independent authoring/review parallel, but serialize builds, sanitizer runs and benchmarks. Never benchmark during another build. Root alone ran compilation. No known live root build/test remains: the last session 48881 terminated with exit 1.

macOS arm64, Swift 6.3.3, macOS 26.4, SDK 26.5. Some compiler/AppKit/process inspection operations need sandbox escalation. Use caffeinate -i for long tests (not protection against closing the lid). Preserve /tmp versus /private/tmp spelling for existing SwiftPM scratch paths: normalizing it caused duplicate Foundation module errors.

## Completed, committed improvements

### Waveform clipping layers

Commits:
- 530a24052 Replace waveform clipping views with lightweight layers
- 26081dabb Record waveform layer validation and allocation evidence

AudioWaveformView uses a SimpleLayer for foreground clipping, with updateForegroundClip(size:animated:) and seven migrated callers. Preserves full painter width, clamps negative dimensions, cancels obsolete animations even for unchanged targets, and handles retargeting to the current presentation bounds.

Frozen /tmp/WaveformClipCorrected: release, ASAN and TSAN each passed 15 functional tests (17 total, two optional skipped), 3,240 painter and 324 composite exact pixel pairs. Real dependency API typecheck passed. Corrected ownership count check in /tmp/WaveformClipCountCheck passed.

Quiet forward/reverse mini-app measurements:
- construction 44.1–45.3% less time
- configured construction 45.5–46.5% less
- changing progress 67.2–68.4% less
- animated retarget setup 37–38.2% less
- attached layout approximately unchanged (0.5–2.9% less)
- unchanged progress adds 0.003–0.006 microseconds due to cancellation checks
- 2,000 retained, unattached/unrasterized instances: incremental footprint 12.75–12.78 MiB to 7.5625 MiB; about 2.66–2.67 KiB saved per instance

Both variants own four layers. Old raw benchmark connected-root-layer counts were misleading for disconnected AppKit backing layers; documentation and ownership tests correct that distinction. These are fixture measurements, not full-app FPS or memory results.

Evidence: tools/perflab/WaveformClipLayerLab/results and README.

### Earlier validated work

- c8ef94064: spoiler reentry and obsolete timer guards. /tmp/InkSpoilerReentry: 428 functional tests passed in release/ASAN/TSAN (446 total, 18 skipped). Evidence in InvisibleInkAllocationLab/results/spoiler-lifecycle.
- a451ef79e: waveform sample-cache and resize evidence; underlying production in 99d5a5d53.
- d0f0e1c67: formatted date rendering and native emoji immutable-color reuse evidence; underlying production in 99d5a5d53. 386 functional checks each mode; mini-app gains vary by operation.
- Unrelated concurrent commits include 51290b054 (CI output/crash notification), 41a9837ee and 04874de98. Do not revert or claim authorship of these.

## Pending slice 1: live inline emoji — NOT READY TO SHIP

Production files:
- packages/ChatUI/Sources/ChatUI/ChatLayerInlineEmoji.swift (new)
- ChatLayerMessageTextView.swift
- ChatLayerMessageText+Layout.swift
- ChatMessageView.swift
- ChatRowView.swift

Helper owns media layers per block with weak host/context, immutable account/source/tint/size/occurrence reuse, generation guards and cleanup. Native fallback remains for unsupported emoji policies, avatars, quote/folding mixtures, spoilers and streaming. Tiny measured entries follow native behavior. The .always fetching constructor is unchanged: visibility flags do not cancel fetching, and cleanup requires deallocation.

Initial implementation passed substantial correctness checks but FAILED the performance acceptance criterion. Latest optimizations have NOT been tested.

### Initial implementation validation (does not cover latest fixes)

Frozen /tmp/LiveInlineEmojiCorrected:
- release, ASAN, TSAN EACH passed 396 functional tests, 434 total with 38 optional skipped
- 618 compiler inputs verified unchanged
- actual stale fresh-body reentry leak fixed in ChatMessageView.updateText: prepareForRemoval on an unpublished stale host without clearing the new active host
- six exact placement pairs, source/tint/account/occurrence, selection/copy, caption reorder, observer lifecycle, fallback and synchronous constructor/body/caption reentry covered
- real helper API typecheck passed
- real Lottie decode, async fetching, player restart and live app behavior remain unproven

Evidence: tools/perflab/ChatLayerEngineLab/results/live-inline-emoji.
Temporary logs: /tmp/live-inline-emoji-full-{release,asan,tsan}.log.
Final input manifest: /tmp/live-inline-emoji-final-inputs.json.

Helper-only /tmp/InlineEmojiLayerFinal: 14 tests passed in all three modes.
Logs /tmp/inline-emoji-helper-final-{release,asan,tsan}.log.
These precede the latest visibility change.

### Fair benchmark revealed regressions

Lab: tools/perflab/InlineEmojiBindingLab.
Frozen initial implementation: /tmp/InlineEmojiBindingCheck; scratch /tmp/InlineEmojiBindingCheck-build.
Baseline is actual immediate pre-inline code captured from 41a9837eef539288e1319ca480012623d75b408c.
Both variants use actual shared current FoldingTextView/TGUIKit and identical deterministic bitmap media.

Preflight: 108 exact pixel comparisons, accounts/source/tint/size/frame/selection/copy/visibility. Fixture initially compared coordinates before attached layout completed; layout and CATransaction.flush fixed the fixture without loosening assertions. Explicit repair manifests record this.

Authoritative quiet sequence: /tmp/InlineEmojiBindingQuiet/measurements.json.
Four fresh processes native/layer/layer/native, nine samples, 120 iterations, 20 warmups.
- body construction 6–17% faster; caption construction 1–8% faster
- same binding 2.4–2.7 TIMES SLOWER
- edited body 39–62% more time; edited caption 78–90% more
- changed sources 15–26% more
- visibility 23–182% more
- caption reorder 115–148% more
- body view counts 3/6/14 to 2; caption 5/11/27 to 4/7/15

Do not accept reduced view count or construction wins as evidence this implementation is faster overall.

Archive: tools/perflab/InlineEmojiBindingLab/results/initial-regression.
One other complete sequence (/tmp/InlineEmojiBindingMeasured) was excluded because a compiler appeared at the final boundary check. Another attempt failed due to /tmp path normalization. Both failures are archived. Runner checks boundaries, not continuous absence of competing workloads.

Lab README still starts with stale “Template only” text; update it after validating current changes, preserving negative evidence.

### CPU sample and latest UNVALIDATED fixes

Successful direct sampling used /tmp/profile-inline-emoji-direct.py and the exact xctest process PID. SwiftPM buffers stdout and spawns discovery processes; earlier attempts sampled the wrong process or found no PID and must not be cited.

Successful files:
- /tmp/inline-emoji-direct-layer-sample.txt
- /tmp/inline-emoji-direct-native-sample.txt
- matching .log and -sample-command.log files

In the initial layer sample, about 2,175 of 4,164 binding samples were in supportsInlineEmoji's Swift attributed-string dictionary bridging. This is diagnostic attribution, not a benchmark percentage speedup.

Latest changes, authored but UNBUILT/UNTESTED:
1. Coalesce visibility: helper update/attach accept refreshVisibility default true; live host passes false and refreshes once at the end. Preserve immediate pause/detach and all generation guards. Skip identical weak-host/media-superview assignments.
2. Fold custom emoji validation into the existing CFDictionary attribute scan in both simpleText and general preparation. Remove the redundant Swift enumerateAttributes/dictionary conversion. A per-block Set checks measured identities in O(n); keep source/file-ID/policy/geometry gates.
3. New helper deferred visibility test, live update playback-assignment count test, and InlineEmojiEligibilityTests.swift: malformed/raw/embedded mappings, wrong IDs, missing/unmeasured identities, avatars, trailing runs, 128 duplicate and distinct entries, rawless supported sources, fast/general parity.

Before/after records:
- /tmp/inline-emoji-deferred-visibility-{before,after}.json
- /tmp/inline-emoji-cf-eligibility-before.swift
- /tmp/inline-emoji-cf-eligibility-before.json
- /tmp/inline-emoji-cf-eligibility-after.json

Next: inspect those changes, generate FRESH helper/live/binding snapshots, run focused tests then full release/sanitizers, and rerun the same fair benchmark. Do not overwrite initial frozen benchmark evidence. Suggested new paths /tmp/InlineEmojiDeferredHelper, /tmp/InlineEmojiDeferredLive, /tmp/InlineEmojiDeferredBinding were not created at handoff.

If visibility remains slow, profile it separately. Potential shared per-refresh host/window/clip calculations were discussed but NOT implemented. Avoid persistent caches that miss geometry changes.

## Pending slice 2: reaction passive layers — PIXEL FAILURES OPEN

Production:
- packages/ChatUI/Sources/ChatUI/ChatReactionsView.swift
- new ChatReactionTextLayer.swift

Count/tag labels move from TextView to TextViewLayer with static-text accessibility children. Ordinary selected background moves from View to SimpleLayer; avatar container becomes lazy. Outer controls, media/effects and tag image background remain native. Removal animation was corrected to preserve native opacity/centered scale behavior and cancel old entrance springs.

Lab: tools/perflab/ReactionPassiveLayerLab.
Snapshot /tmp/ReactionPassiveLayerCheck; scratch /tmp/ReactionPassiveLayerCheck-release.
A fixture scale mismatch (native 2x window versus requested candidate scale) was corrected using a controllable window, but major failures REMAIN.

Latest diagnostic command FINISHED, exit 1:
REACTION_PASSIVE_DIAGNOSTICS=/tmp/reaction-passive-pixels caffeinate -i swift test --package-path /tmp/ReactionPassiveLayerCheck --scratch-path /tmp/ReactionPassiveLayerCheck-release -c release --filter PassiveReactionTests

Log /tmp/reaction-passive-diagnostic.log:
9 tests, 155 assertion failures. Selected-state pixels and selected effect stack fail. New text-free background test fails ordinary/full backgrounds for builtin/custom at all 1x/2x/3x scales; tag text-free backgrounds pass. This narrows the issue but does not prove whether production stacking or snapshot behavior is responsible.

PNG pairs/layer-tree JSON: /tmp/reaction-passive-pixels.
Initial run: /tmp/reaction-passive-release.log (197 failures before scale fixture fix).
Repairs: /tmp/reaction-passive-initial-provenance.json and /tmp/reaction-passive-diagnostic-repair.json.
Fresh generated diagnostic template also exists /tmp/ReactionPassiveDiagnostics.

Next owner must inspect PNGs and layer trees, diagnose background composition and mixed NSView/CALayer z-order. Do not blindly set zPosition=1: effect layers must cover the label. Do not weaken exact pixel comparisons. No sanitizer/benchmark acceptance for this slice yet.

## Pending slice 3: avatar tracking reuse — NEVER BUILT

Production packages/AvatarUI/Sources/AvatarUI/AvatarLayer.swift.
Reuse existing tracking area while window-attached; remove on detach, refresh in viewDidMoveToWindow. Preserve cursorUpdate, mouseEnteredAndExited, mouseMoved, activeAlways, inVisibleRect; disabled inner avatars must still forward events. Hover timer behavior unchanged.

Lab tools/perflab/AvatarTrackingLab:
seven functional tests plus optional benchmark, actual extraction of 13 methods with captured baseline.
Generated /tmp/AvatarTrackingCheck exists but NO build/test has run. The old queue stopped on reaction failure before reaching it.

Next: release then appropriate sanitizers, real complete AvatarUI API typecheck, quiet forward/reverse timing, and live hover/cursor checks including clipping, inactive windows and disabled inner AvatarStoryControl. Registered-owner event injection tests do not prove actual OS pointer dispatch. No performance claim yet.

## Recommended continuation order

1. Verify branch, working tree and recovery manifest; read goal.json and this document. Do not reapply the backup over existing changes.
2. Inspect reaction diagnostics, delegate its fix independently.
3. Validate new inline CF eligibility and visibility changes on fresh snapshots; compare with original fair baseline and preserve negative evidence.
4. Run avatar checks and production dependency typecheck when compiler slot is free.
5. Only commit slices that pass their correctness and performance gates. Force-add ignored results selectively when committing evidence; do not add every generated build artifact.
6. Continue broader migration only after these open regressions/build gates are resolved. Keep native fallback for unsupported behaviors.

Use tools/perflab/typecheck/tc.sh for real production dependency API checks as appropriate; it can print “exit N” while its shell wrapper exits successfully due to grep, so inspect logs. Use fresh TMPDIR to avoid stale stub module shadowing.

No claim that the full app currently builds, that all chat rows are migrated, or that real scrolling FPS improved is justified by these mini-app runs.

## Suggested prompt for the next model

“Continue the performance goal in /Users/renoir/projects/Telegram/telegrammacos. Read docs/PERFORMANCE_HANDOFF_2026-10-18.md and the saved goal/snapshot first. Preserve all local changes. Start by validating the latest inline emoji CF-scan/visibility optimizations and diagnosing reaction pixel failures; avatar tracking is still untested. You may use parallel agents for independent work, but serialize builds and benchmarks. Keep telegram-ios untouched. Require correctness tests and fair measured evidence before accepting or committing changes; do not push.”

