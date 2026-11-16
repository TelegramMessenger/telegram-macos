# Chat controller and chat scrolling optimization log

Overnight loop started 2026-10-01. Every loop picks one heavy operation in `ChatController`
or in chat row scrolling, measures it with a PerfLab harness, changes it without changing
behaviour, measures again (A/B against a copy of the previous build), and commits.

Measurements are Debug builds on an M5 Pro, 120 Hz display. "main %" is main-thread CPU time
divided by wall time during the scenario; "hitches" are frames that missed the display deadline.

Lab: `tools/perflab/run.sh chat-navigation <label> -PerfLabScenarios <list>` (see
`packages/ChatUI/Sources/ChatUI/ChatNavigationLab.swift`).

| Loop | Area | Change | Scenario | Before | After | Win |
|---|---|---|---|---|---|---|
| 0 | Reply / pinned jumps | Far animated scroll starts one screen before the target instead of animating through every row in between | 21 jumps over 10 chats | 0.28 s to visible, main 36.6 %, 0.93 cores, ~5600 px animated | 0.11 s, main 25.9 %, 0.68 cores, 735 px | 2.5× faster to visible, −29 % main, −27 % CPU |
| 0 | Near animated scroll | Rows of the start screen stay alive during the animation (`TGFlipableTableView.visibleRect` union) | pinned clicks within a screen | 27 blank frames | 0 | no blank band |
| 0 | Pinned bar | `tempPinnedMaxId` kept while its row is visible; forum wrap-around falls back to the newest pin in the current topic | INVEST ZONE, Changelogs, 33 ½ | bar stuck or vanished | cycles through every local pin | correctness |
| 1 | Group chat scrolling | Floating sender avatars are re-inserted into the table only when they are not already the top subviews in the right order (was: `addSubview` on every scroll event, which re-ran viewDidMoveToSuperview, tracking areas and listeners) | Telegram macOS Talk, 2 × 9 s wheel passes at 3500 px/s, 3 interleaved rounds | main 29.9 %, 0.551 cores | main 26.9 %, 0.512 cores | −10 % main thread, −7 % CPU |
| 2 | Every TGUIKit `View` (display cycle) | `View.wantsUpdateLayer` reads a stored flag kept in sync by the `_anchorPoint` / `_transformation` / `_sublayerTransform` setters instead of copying three optionals (two 128-byte `CATransform3D?`) on every AppKit layer-tree pass | same scroll scenario, 3 interleaved rounds | main 26.84 %, 0.514 cores | main 26.57 %, 0.497 cores | −1 % main thread, −3 % CPU (app-wide, every display cycle) |
| 3 | Group chat scrolling | The chat table inserts new row views below the floating avatars (`TableView.documentSubviewKeptAboveRows`), so the avatars stay on top without being re-inserted after every new row | same scroll scenario, 3 interleaved rounds; lab guard counts avatars below rows | main 27.1 %, 0.533 cores, 3.5 hitches / 34.8 ms hitch time, worst 21.0 ms | main 26.1 %, 0.504 cores, 2.0 hitches / 16.7 ms, worst 19.0 ms; avatars below rows 0 | −43 % hitches, −52 % hitch time, −4 % main, −5 % CPU |
| 4 | Video / GIF accessory label | `ChatMessageAccessoryView.updateText` reuses the measured `TextViewLayout` when text, colour, line limit and width are unchanged (autoplay refreshes it every 0.5 s per video and on every player status) | Time Profiler over the same scroll pass, base vs fix | `updateText` 33 ms, `updateVideoAccessory` 37 ms | 17 ms, 22 ms | −48 % in that path (small in absolute terms; scales with autoplaying videos on screen) |
| 5 | Group chat scrolling | Floating avatars are ordered with the minimal number of moves (views already in the right relative order stay; the rest are inserted next to their neighbour) instead of re-inserting all of them whenever one avatar is created or switches between the table and the pinned overlay. Same final order, checked by a DEBUG verifier (0 violations in two chats) | same scroll scenario, 6 interleaved rounds (12 passes each) | main 27.6 % (median 27.45), 0.509 cores, worst 21.6 ms; avatar `addSubview` 255 ms per pass (Time Profiler) | main 26.3 % (median 26.3), 0.486 cores, worst 20.7 ms; 145 ms | −4.6 % main, −4.4 % CPU, −43 % avatar insertion time |
| 6 | Sticky date header while scrolling | The date header re-applies its blur / background colours only when the theme object or the blur setting changed (it set them, and rebuilt the blur layer, on every scroll event); `TableView` caches the sticky class names instead of `NSStringFromClass` per event | Changelogs and translations (channel), Time Profiler, 2 runs per build | `updateStickAfterScroll` 136 ms, `updateColors` 36 ms per pass | 116 ms, 18 ms | −14 % sticky header work (~0.5 % of main thread) |
| 7 | Group chat scrolling | Cached floating avatars are not re-configured (`setPeer`) when their group still ends with the same `ChatRowItem` (same arguments; also stops re-subscribing video-avatar photos) | Telegram macOS Talk, Time Profiler 2 runs per build | `setPeer` 45 ms, `collectFloatingPhotos` 217 ms per pass | 20 ms, 174 ms | −56 % `setPeer`, −20 % regrouping |
| 8 | Any table (`TableView.rectOf(item:)`) | When the item is the object at its recorded index, the rect is taken directly instead of building an `AnyHashable` stable id and looking it up (same result: `listhash` maps that id to that object) | Telegram macOS Talk, Time Profiler 2 runs per build | `rectOf(item:)` 58.5 ms per pass | 8 ms | −86 % |
| 9 | Chat rows on scroll (`ChatRowView.updateMouse`) | The cheap "mouse inside this row" test runs before the computed chat `state` (all conditions are side-effect free), so `state` is only built for the hovered row | Telegram macOS Talk, Time Profiler 2 runs per build | `updateMouse` 13.5 ms, `state` getter 18 ms | 5.5 ms, 6.5 ms | −60 % |
| 7–9 | Combined | macro A/B, 3 interleaved rounds | Telegram macOS Talk scroll | main 26.2 %, 0.535 cores | main 25.6 %, 0.499 cores | −2.2 % main thread, −6.8 % CPU |
| 10 | Bubble gradient backdrops on scroll | The scroll listener updates every visible bubble backdrop inside one `CATransaction`; each backdrop wrapped its frame change in its own begin/commit, and with no enclosing transaction every one of them was a real commit to the render server (one per row per scroll event) | Telegram macOS Talk, Time Profiler 2 runs per build | backdrop update 151 ms, explicit commits 138 ms per pass | 3.5 ms, 36 ms (one commit per event) | −105 ms per pass (~2.3 % of main thread) |
| 11 | Media rows on scroll (`updatePlayerIfNeeded`) | Returns before computing visibility and the lite-mode check (which scans file attributes) when the view has no autoplay player, since the result was only used for one | Telegram macOS Talk, Time Profiler 2 runs per build | `lite` check 29 ms, `updatePlayerIfNeeded` 41.5 ms per pass | 11 ms, 27.5 ms | −62 % / −34 % (depends on autoplaying videos on screen) |
| 10–11 | Combined | macro A/B, 3 interleaved rounds | Telegram macOS Talk scroll | main 26.2 %, 0.516 cores, worst 19.0 ms | main 25.6 %, 0.498 cores, worst 17.3 ms | −2.4 % main thread, −3.5 % CPU, −9 % worst frame |
| 12 | Typing in the chat input | `InputTextView.updateTextContainerInset` marks the text view for display instead of calling `display()` on every keystroke (a synchronous redraw that also forced a window layout; the display cycle drew the view again in the same frame). Snapshot after typing shows the same text rendering | Saved Messages, 124 characters at 15 / s, 3 interleaved rounds | 10.74 ms main thread per character, 0.170 cores, 61 dropped frames per 124 characters | 9.82 ms, 0.150 cores, 43 | −8.5 % per keystroke, −12 % CPU, −30 % dropped frames |
| 13 | Pinned message header (resize, typing) | `ChatPinnedView.updateLayout` skips re-measuring and re-applying the reply model when the model object, its text layouts and the available width are unchanged (the header was laid out twice per resize step: explicitly and again from `layout()`, and once per keystroke) | Telegram macOS Talk window resize (Time Profiler), Saved Messages typing (3 interleaved rounds) | pinned `updateLayout` 104 ms per resize run, 9.72 ms main per typed character | 54 ms, 9.42 ms | −48 % pinned header work on resize, −3 % per keystroke |
| 14 | Chat layout on every input change (typing) | The header title/status are re-measured only when their layout is not already measured at the new width; `EdgeEffectView` rebuilds its 28-stop horizontal mask only when bounds or fade change | Saved Messages typing, Time Profiler 2 runs per build (the interleaved macro A/B was confounded by a load change on the machine) | `updateFrame` 121 ms, bubbles header 36 ms, edge effect 17 ms per 248 characters | 89 ms, 7 ms, 1 ms | −26 % of the per-keystroke `updateFrame` |
| 15 | Selection mode action bar | (rejected) cache the precomposed delete/forward icons: the theme hook returns a new image per call, so an identity cache never hits, and keying on theme identity was not worth ~1 ms per action | — | — | — | not committed |
| 16 | Finding, not a change | Removing the window's 67 hidden view subtrees (209 views: chat-list avatars, glass effect views on buttons, hosting views) lowered scroll main thread 26.2 → 24.6 %; hidden glass views alone ≈ 1–1.5 points. The views belong to many components, so this is left for a dedicated change. An implicit-transaction variant of loop 10 was also tried and rejected (the commit work just moves to the run-loop flush) | Telegram macOS Talk scroll (lab-only strip) | — | — | not committed |
| 17 | Animated stickers / custom emoji (rlottie raster threads) | REVERTED (2026-10-02): `RleTaskScheduler` workers scanned the task queues twice before blocking instead of 32 times. Measured −10 % process CPU while scrolling (0.506 → 0.454 cores; main thread, hitches, WindowServer, GPU unchanged), but rendering output, animation frame latency under load and shutdown were not verified with a dedicated harness, so the change was reverted until that exists | Telegram macOS Talk scroll, 3 interleaved rounds | 0.506 cores | 0.454 cores | not shipped |

## Cumulative (2026-10-02 03:10)

Interleaved A/B, 3 rounds × 2 passes, same Debug build settings, baseline = the build before the first loop that touches each scenario.

| Scenario | Loops | Before | After | Win |
|---|---|---|---|---|
| Group chat scroll (Telegram macOS Talk, 2 × 9 s at 3500 px/s) | 1–11 (measured with 17, now reverted) | main 29.75 %, 0.571 cores, worst frame 19.3 ms, hitch time 20.8 ms | main 24.91 %, 0.456 cores, 17.3 ms, 18.7 ms | −16 % main thread; CPU −20 % measured with loop 17, about −11 % without it (loop 17 alone was −0.052 cores) |
| Typing (Saved Messages, 124 characters at 15 / s) | 12–14 | 8.31 ms main per character, 41.7 dropped frames, 0.124 cores | 6.89 ms, 17.3, 0.110 cores | −17 % per keystroke, −58 % dropped frames |
| Window resize (Telegram macOS Talk, 62 steps) | 13, 14 (measured with 17, now reverted) | 12.11 ms main per step | 11.81 ms | −2.5 % |
| Reply / pinned jumps (10 chats) | 0 | 0.28 s to visible, main 36.6 % | 0.10 s, main ~26 % | 2.8× faster |

Not pushed: all loops are local commits on `beta`. Loop 17 (rlottie) was reverted; `submodules/rlottie` is back on a78ba9f and needs no push.


## 2026-10-18: skip the clip view's display walk while the chat scrolls

`TGClipView.skipsDisplayOnScroll` (already used by the profile media grid since 2026-10-02) is now set on the chat table. AppKit marks the clip view as needing display on every scroll step, and the next display pass walks every view under it; the clip view draws nothing, so the walk is pure cost. Views that need display still mark themselves.

In-app A/B with the user's Debug build (no rebuild: the DEBUG switch `-PerfLabClipNoDisplay 1` forces the same skip), `chat-navigation` `scroll` in "Telegram macOS Talk", two passes per run, interleaved base / skip / skip / base:

| Run | Main thread | Process CPU (cores) | Hitches per pass |
| --- | ---: | ---: | ---: |
| base 1 | 21.28 % | 0.42 | 0.5 |
| skip 1 | 17.71 % | 0.31 | 0 |
| skip 2 | 17.48 % | 0.34 | 0 |
| base 2 | 20.13 % | 0.36 | 0 |

Main thread −15 % (20.7 → 17.6 %). Visual check: `snapshot` scenario at six scroll positions with and without the skip; only live content differs (online count, an animated emoji status in the sidebar), message rows are identical. Raw reports in `docs/perflab/evidence/2026-10-18-chat-clip-skip/`.

## 2026-10-18: date and status hosted in the row's layer tree

`ChatRightView` (date, edit mark, views, replies, read checks — already all layers) keeps its content in a `contentLayer`. When the row needs no native subview there (no blur, no message-effect view, no sending clock), the row hosts that layer directly in its own layer and removes the `ChatRightView` NSView from the hierarchy: one NSView fewer per row. The hosted layer copies the native view layer's appearance (background, corner radius, clipping, continuous corners, the AppKit antialiasing mask, opacity, hidden). The date tooltip is a tooltip rect on the row, its text computed when shown; shake, the send flight and the video-processing tooltip follow the hosted layer. Rows switch back to the native view whenever blur, an effect or the sending clock appears.

Proof with the new in-app parity lab (see `docs/perflab/README.md`), WindowServer captures of real rows, native vs hosted:

| Chat | Rows | Identical | Different | Self-animating | Date hosted |
| --- | ---: | ---: | ---: | ---: | ---: |
| Telegram macOS Talk (group) | 40 | 37 | 0 | 3 | 35 |
| Saved Messages (media, files, voice) | 60 | 57 | 0 | 3 | 48 |
| Changelogs (channel) | 42 | 18 | 0 | 24 | 41 |
| Telegram macOS Talk, hosted layer shifted 1 pt (oracle check) | 40 | 5 | 33 | 2 | 35 |

Whole-app scroll A/B of the earlier slices of the day (reaction chips, comments, inline emoji) against the 11:46 build, both with the display-walk skip, six interleaved runs: 18.39/18.85/18.89 % vs 18.86/18.78/18.74 % main thread — no measurable whole-app change in this chat; those slices are component-level wins (construction, memory).

## 2026-10-19: what the rest of the window costs while the chat scrolls

`-PerfLabDetachSidebar 1` (chat-navigation `scroll`) removes the chat list pane (`MainController_View`) for the measurement. Interleaved in "Telegram macOS Talk": with the sidebar 17.53 / 16.45 % main thread and 36.5 / 36.6 % GPU, without it 15.34 / 15.22 % and 30.0 / 30.2 %. The window held 523 NSViews during the chat (`viewcount`): the chat table only 9 row views, most of the rest are the chat list (51 AvatarControl, 49 TextView, story strip items), 22 SwiftUI hosting views and 41 glass views. AppKit's per-frame walks (layer tree build, needs-display tickle, tracking areas) visit the whole window, so a static sidebar costs about as much as all chat rows; the chat list view count is as large a lever as the chat rows. Stripping the 49 hidden views (`-PerfLabStripHidden 1`) changed nothing measurable (15.61 vs 15.51 %). Run-to-run spread is about ±1.5 points, so single-view slices are verified with component benchmarks and the parity gate, not in-app timing.

## 2026-10-19: reaction emoji as layers

Each reaction chip held its emoji in an `AnimationLayerContainer` NSView with its own scroll-notification observer. `ChatReactionEmojiLayer` replaces it: same centring (`round((w − size) / 2)`), clipping, continuous corners, AppKit antialiasing mask and corner radius, the same playback rule (`visibleRect`, key or non-key-capable window, lite mode); the chip observes visibility and re-evaluates playback after every emoji frame change, which mirrors the frame notifications the old view received. `getView()` (fly-in target, screen effects) returns a lazily created anchor view at the emoji's frame. One NSView fewer per chip. `ChatRowView.usesLegacyRowChrome` keeps the old container (`ChatReactionEmojiViewHost`) for the parity lab.

Parity (real rows, WindowServer captures): group 46/46 and 46/48 identical, channel 32/32, Saved Messages 47/47; an emoji-only 1 pt shift (`-PerfLabParityMutateEmoji 1`) is caught on 19 rows. The two remaining group rows are animated emoji whose playback differs in the capture window (`playback` note): the old container never starts playing there because its only later trigger, a frame notification, fires before the chip has a size; in a real chat a scroll notification starts it, the layer path starts it once the chip is laid out.

## 2026-10-19: reaction reactor avatars as layers

The recent-reactor avatars inside a reaction chip were a container `View` plus one `AvatarContentView` (a View with two `ImageView`s) per reactor: 3 reactors cost 10 NSViews. They are passive (the chip handles clicks and the tooltip), so the chip now holds a `SimpleLayer` container with one `AvatarContentLayer` per reactor. Both copy the native backing layer's anchor point (0, 0, which the position and spring scale animations rely on), clipping, opacity, continuous corners and AppKit antialiasing mask; the z order follows the container's children like before. `AvatarContentLayer.animatesClipChanges` (opt-in, the comments button keeps its immediate switch) crossfades the clipped and unclipped image with the native `change(opacity:)` rules. `ChatRowView.usesLegacyRowChrome` keeps the old views for the parity lab.

Parity in "Telegram macOS Talk" (25 reactor avatars per pass, counted on both paths): 46/48 identical, the two others are the self-animating emoji rows from the previous entry; shifting only the avatar container by 1 pt (`-PerfLabParityMutateAvatar 1`) is caught on 16 rows.

## 2026-10-19: hosted date no longer re-measured on every bind

A Time Profiler capture of a 16,000 pt/s fling in "Telegram macOS Talk" (Debug, `-PerfLabScrollSpeed 16000`) showed `ChatRowView.updateRightHosting` at 1.4 % of the main thread: on every bind it recomputed the bubble geometry (`ChatRowItem.bubbleFrame` → `bubbleFrameWidth`) and re-registered the date tooltip rect, although every table bind is followed by `updateLayout`, which positions the hosted date anyway. It now sets the frame only when a row switches from the native view to the hosted layer; a row that stays hosted is positioned by the layout pass, like the native view. This also makes animated item updates (`set(item:animated: true)` followed by an animated `updateLayout`) move the hosted date with the transition instead of jumping it first.

Parity: group 46/48 (the two known self-animating emoji rows), Changelogs 31/31, Saved Messages 47/47; `-PerfLabParityMutate 1` caught on 38 rows.

Where the fling's main thread goes (14.8 s window, 5.4 s busy): row binding 12.8 % (`set(item:)`; row views are reused, construction ≈ 0), AppKit display walks 16 % (needs-display tickle 7.6 %, layer tree build 8.2 %), floating avatars 7 %, CA commit 12.4 % of which layer display 6.8 % and text glyph rasterization about 2 %, `_setWindow:` recursion for inserted rows 4 %, tracking areas 3.9 %, macOS glass views re-rendered through SwiftUI during window layout 4 %. All 17 frames over 9 ms were history-window merges (`ChatController.applyTransition` → `TableView.merge` → `NSTableView endUpdates` creating the newly visible row views in one frame, 10–20 ms each).

## 2026-10-19: history merges tile once

All hitching frames of a 16,000 pt/s fling were history-window merges. A DEBUG probe around `TableView.merge` (`ChatMergeProbe`, reported by the `scroll` scenario as `merges`, `mergeMsMax`, `mergeNewBinds`, `mergePreexistingBinds`, `mergeMaxShift`) showed every `.saveVisible(.upper)` merge re-binding all visible rows: deletions and insertions were two NSTableView update batches, each re-tiling the old clip rect over shifted content before `saveVisible` restored the position. The chat table now sets `mergesSaveVisibleInOneGroup`: one NSTableView update for the whole merge, with inserted row heights noted and the table frame set to the final height before `saveVisible` (details and the 42-case equivalence test in `tools/perflab/MergeRetileLab`).

| 16,000 pt/s, "Telegram macOS Talk" | Old path | One group |
| --- | ---: | ---: |
| Hitches (warm-up / measured pass) | 5 / 2 | 0 / 0 |
| Merge time per pass | 77 / 45 ms | 30 / 22 ms |
| Worst merge | 9.7–10.3 ms | 4.1–6.0 ms |
| Row binds inside merges | 53 / 34 | 3 / 0–13 |
| Max on-screen shift of rows visible before and after a merge | 0 | 0 |

At 2400 pt/s nothing changes (no hitches either way). `-PerfLabMergeGrouped 0` runs the old path for A/B.

## 2026-10-19: avatar tracking areas kept across refreshes

The handoff's slice 3 (98a0b0760): `AvatarControl` keeps its tracking area while attached instead of replacing it on every `updateTrackingAreas`, and refreshes tracking itself in `viewDidMoveToWindow`. `tools/perflab/AvatarTrackingLab` passes in Release, ASan and TSan (one fixture fix: on macOS 14+ an unclipped view's `visibleRect` is not empty when scrolled out). Refresh of attached avatars costs 9–15× less; a detach/attach cycle 1–8 % more (about 1–2 µs per avatar). The Debug builds behind the other 2026-10-19 measurements already contained it.

## 2026-10-19: what AppKit's per-frame walks scale with

A 2400 pt/s scroll in "Telegram macOS Talk" (whole window, Debug Time Profiler) spends 8.8 % of the main thread in `_NSTrackingAreaAKManager displayCycleUpdateStructuralRegions` (a recursive walk of the whole window's view tree), 4.4 % building the layer tree and 3.2 % in the needs-display tickle. A standalone probe (one 8-view row removed and added per frame, 50 or 500 other views in the window, tracking areas on or off) shows the walk fires on any view add/remove, costs about 0.9 µs per other view in the window per such frame, and does not depend on tracking areas: 1.39 vs 1.39 ms per frame with and without them, 1.0 ms with 50 other views vs 1.4 ms with 500. The chat rows are about 56 of the window's 542 views; the chat list, the story strip and the glass views (each `NSGlassEffectView` brings its own hosting views) are most of the rest, which is why detaching the sidebar cut 10 % of the main thread. Fewer NSViews per chat row still pays on every row that enters or leaves (its own `_setWindow`/`addSubview`/`removeFromSuperview`, 7.8 % at 2400 pt/s), and every floating-avatar move is such an add/remove.

Glass cost (standalone probe, 10 `NSGlassEffectView`s): writing the same corner radius is free, a changed radius 0.19 ms and a resize 0.23 ms per view (SwiftUI re-render), moving the origin 0.025 ms. In the chat the per-frame glass renders come from date-row binds resizing their glass to each date's width.

## 2026-10-19: bubble backdrops join the frame's commit

Follow-up to row 10 above. The scroll listener's outer `CATransaction` (which made the per-row backdrop transactions nest) still ran from the coalesced scroll callback with no transaction open, so it was a real top-level commit on every scroll event (1.0 % of the main thread at 2400 pt/s). The backdrop's gradient layer is a `SimpleLayer`, whose `action(forKey:)` always returns a null action, so the inner `setDisableActions` transactions never changed anything; both inner and outer transactions are gone and the frame changes go into the runloop's implicit transaction with everything else. Interleaved A/B, 3 rounds × 2 passes, "Telegram macOS Talk" at 2400 pt/s: 18.47 % vs 18.69 % main (−1.2 %); the listener's own commit 54 ms → 0 per pass. Parity: group 46/47 (one known self-animating row), Saved Messages 47/47.

## 2026-10-19: sender status as a row-scene node

`PremiumStatusControl` (verified / scam / fake / premium badge or animated emoji status next to the sender name) was an NSView with its own tracking area in every row that shows one. Its rendering now lives in `PremiumStatusRenderer`, driven through a small host protocol; `PremiumStatusControl` is one host with unchanged behavior for every other screen, and `PremiumStatusLayer` is a layer host. Chat rows put a `PremiumStatusLayer` into the row scene as a `ChatLayerButtonNode` (click opens the sender, no cursor or keyboard focus, like the control), laid out, removed (fade) and moved for the shake animation like the sender name. Playback follows the row's visibility through an `AnimatableContentObserver` on the row view.

Parity (both paths counted, `statusLayers` / `statusViews`): "Telegram macOS Talk" 45/46 with 8 statuses per pass (the one difference is the known self-animating row), Saved Messages 46/46, Changelogs 30/31 with 17 statuses per pass; a 1 pt status shift (`-PerfLabParityMutateStatus 1`) is caught on 4 rows. The Changelogs difference is playback timing (`nativeStatic`): in the capture window the native control never re-evaluates playback after its row gets a size (it only observes its own frame and scroll positions), so its animated status stays still there, while the layer starts once the row is laid out; in a scrolling chat both play. That is a behavior difference, not only a lab artifact: when a chat opens and is not scrolled, layer statuses start animating at layout, where native ones waited for the first scroll notification (likely an improvement). Accessibility matches the control: an unlabeled button that VoiceOver can press (opens the sender).

## 2026-10-19: reaction chips as scene nodes

`ChatLayerControlNode` (tools/perflab/ControlNodeLab: 23 equivalence tests against TGUIKit `Control` fed identical event sequences — click, double click, drag out/in, long press timing and the ±2 pt rule, menus on right/control/long press, `sendRightMouseAnyway`, disabled states, window moved, hover and LongOver, press scale, tooltips — plus a mutant with a 0.2 s long press that the tests catch) reproduces Control's event semantics on a layer node. `ChatReactionsView` is now a `ChatLayerSceneView`; ordinary reaction chips are `ReactionChip`s, a control node whose layer hosts the same sublayers as `ReactionView` (selected background, emoji layer, count text, reactor avatars, star effect), with the effect player and the fly-in anchor added to the scene at the chip's frame only while needed. The container's merge, reuse and removal logic runs over one element protocol for both kinds. `ReactionView` stays unchanged as the native reference for the parity lab; tag chips (Saved Messages) keep their views for now. A row with three reactions loses three NSViews and three tracking areas. Chip nodes get unique ids (the container reuses a deleted chip for a different reaction, so value-based ids could collide in the scene's id index), and the effect player is event-less so clicks during an effect still reach the chip. In-app hit chain (`chipHitOK` / `chipHitTotal`: the window's `contentView.hitTest` at each chip's center returns the reactions scene and the scene's hit index returns that chip, which is what the node's click needs): 50/50 in the group, 24/24 in Changelogs. Scroll gate on the chip build: group 0/0 hitches at 2400 pt/s, 1/1 at 16,000 pt/s with merges ≤ 2.8 ms, Changelogs 1/0 at 2400 pt/s (a 22 ms first-pass frame).

Parity: "Telegram macOS Talk" 45/47 with 25 chips per path (the two known self-animating rows); a 1 pt chip shift (`-PerfLabParityMutateChip 1`) is caught on 18 rows. Changelogs 30/31 with 12 chips per path, most of its reaction rows animate and are skipped as unstable; Saved Messages 47/47. Cross-build check of the shared container code (every row saved with `-PerfLabParitySaveAll 1` before and after the change): 154 of 188 captures identical; the rest are self-animating rows, one animated emoji status, and two group rows whose reply count ("1") was missing in that later run on both paths. Settled by capturing the pre-chip binary and the chip build back to back: the reply-count row is pixel-identical between them and to the original baseline, so the missing count was transient data or load timing (the count comes from `ReplyThreadMessageAttribute` and needs the loaded supergroup peer), not reaction code.

## 2026-10-19: admin badge as row-scene nodes

The sender's rank or signature badge (`TextView`) and its rank pill (`View`) were two NSViews on every row that shows one. They are now three nodes in the row scene: a `ChatLayerControlNode` ("admin-badge") holding a non-selectable `ChatLayerTextNode`, and a background node with the same color at 0.2 alpha, continuous corners and `height / 2` radius, ordered before the badge as the view was. The node is interactive (press scale, click opens the tag info) exactly when the TextView was (`adminBadgeAuthorId != nil`), and gets the arrow cursor as the TextView did for its plain text. Removal fades and scales out like `performSubviewRemoval(scale: true)`, and shake moves both nodes into the bubble and back like the sender name. Rows whose badge can be edited (`adminBadgeCanEdit`) stay on the TextView badge, because the edit sheet morphs out of that view (`showModal(morphSource:)`). `TextViewLayout.insets` is fileprivate but only ever `.zero`, so the node uses `layoutSize` for the TextView's frame size.

Few loaded rows carry badges (none in the last 50 of "Telegram macOS Talk"), so the parity lab can give every row with a sender name a badge through the item's real badge fields (`-PerfLabParityFakeBadge 1` green rank badge with pill, interactive; `2` plain gray badge), restored after the run. Parity, 18 badge rows per path: rank 47/48 equal, plain 46/46; the remaining difference is row 34, a known self-animating reaction row (the animated "100" reaction caught on another frame; it shows up as `different` or `unstable` from run to run depending on whether its two native frames happened to match, and the badge on it is pixel-identical). A 1 pt badge shift (`-PerfLabParityMutateBadge 1`) is caught on 17 rows; the 18th is row 34, unstable in that run. `badgeHitOK` / `badgeHitTotal`: the window's hit test reaches every interactive badge node at its center (36/36 captures). ChatLayerEngineLab: new `AdminBadgeNodeTests` (node reuse, background ordering, plain vs rank, removal, click wiring through `adminBadgeInteraction(rowView)`, hit test, shake round trip, and node vs TextView pixels at 1x and 2x for Latin, Arabic and CJK+emoji, rank and plain); full suite 441 tests, 0 failures.

## 2026-10-19: floating avatars as layers

Every floating avatar was a `ChatAvatarView` subtree (Control → `AvatarStoryControl` → `AvatarControl`, 3 NSViews), and every move between the anchored overlay (`floatingPhotosView`) and the table's document view was a `removeFromSuperview` / `addSubview` of that subtree, which fires AppKit's window-wide structural walks: about 135 creates, 268 anchored↔document transitions and 135 removes per 7 s pass at 2400 pt/s in "Telegram macOS Talk", 7–8 % of the main thread. Floating avatars are now `ChatFloatingAvatarNode`s: a `ChatLayerControlNode` (click opens the sender or toggles selection, the same context menu through the shared `ChatRowView.photoContextMenu`, press scale, the sender's name as tooltip and VoiceOver label) hosting an `AvatarImageLayer`, in two `ChatFloatingAvatarScene`s, one filling `floatingPhotosView` and one filling the document view. A transition is a layer moved from one scene to the other; no NSView is created, added or removed. The scenes copy their container's `isFlipped` (the overlay is unflipped, so anchored avatars stay at a fixed distance from the bottom while the input grows, exactly as the views did), pass hit tests through except over a node, install no tracking area, and are ignored accessibility containers whose misses go to the view underneath. The document scene is registered in `documentSubviewKeptAboveRows` like the avatar views; without that, every new row is inserted above it and forces a re-raise (138 per pass). Position changes mirror `_change(pos:)` (animate from the presentation when a position animation is running, drop it otherwise), fades mirror `performSubviewRemoval(checkCompletion: true)` and the new-row slide-in mirrors `animateNew`. Avatars with story stats (the ring and the story-open morph need a view) and premium video avatars stay `ChatAvatarView`s; a cached avatar whose kind no longer fits its item is replaced.

New `floatparity` scenario (docs/perflab/README.md): the real chat window captured through WindowServer, cropped to the avatar column, at 12 scroll offsets, views / nodes / views / nodes. Three runs: 12/12, 8/8 and 9/9 stable positions byte-identical (the rest unstable, the same on both paths), about 96 % of avatars on the node path (100 nodes, 4 views); a 1 pt node shift (`-PerfLabFloatMutate 1`) is caught at every stable position. The window's hit test reaches the node at its center exactly where it reaches the view (79/100 vs 83/104; the misses are the same avatars, whose centers are above or below the visible table or under the pinned bar and header). Only settled frames are compared; the animated paths are code mirrors of the view path, not captured.

Interleaved A/B, `scroll` at 2400 pt/s, "Telegram macOS Talk", `-PerfLabFloatNodes 0` for the view path, 1 measured pass per run:

| Order | Views main | Nodes main |
| --- | ---: | ---: |
| v, n | 16.70 % | 12.40 % |
| n, v | 14.12 % | 12.31 % |
| v, n | 14.27 % | 12.47 % |

Nodes are lower in every adjacent pair, by 1.8–4.3 points (mean 15.0 → 12.4 %, −17 %); hitches 0 on both paths; floating-avatar view moves 404 → 29 per pass (the remaining story/video avatars), order violations 0. An earlier batch run before the scene was kept above rows: 17.8 → 16.3 %. Fling at 16,000 pt/s, interleaved v / n / n / v: 42.49 / 39.72 / 39.65 / 42.66 % main (−2.9 points), floating view moves 2,700 → 363 per pass, worst history merge 2.9 ms on both paths, hitches 2 / 1 / 1 / 0 (the same on both paths; the chat's content changed since the 0 / 0 run in the merge entry). The document-sized scene has no backing store: TGUIKit `View` answers `wantsUpdateLayer` unless its class overrides `draw`, and neither scene class does, so it is a bare layer container.

## 2026-10-19: bubble frame memo (parked, no gain)

A 16,000 pt/s fling profile after the floating avatar change put `ChatRowGeometry.Bubble.init(item:rowWidth:)` at 2.0 % of the main thread: the row view's frame cache is cleared in `set(item:)` and in every `updateLayout`, and AppKit's `layout()` calls `updateLayout` again, so each bind recomputed `ChatRowItem.bubbleFrame` (a chain of computed properties: `bubbleFrameWidth`, `additionalLineForDateInBubbleState`, `lastLineContentWidth`, `reactionsLayout`, …) about three times. I memoized it on the item, keyed by layout width, height, the stored reactions layout and the reply markup model, cleared in `makeSize`, with a DEBUG check that recomputes on every hit: 0 mismatches over 2400 and 16,000 pt/s scrolls, resize, selection mode and the row parity lab with injected badges (about 10,000 hits). Interleaved A/B at 16,000 pt/s, memo off / on: 40.24 / 40.18, 39.95 / 39.77, 36.42 / 38.39 % main, so no measurable difference (2400 pt/s: 16.8 / 16.2 / 17.0 / 16.1 %), and hitches 4 / 2 / 4 with the memo against 0 / 1 / 0 without. Not kept; the patch is in `evidence/2026-10-19-bubble-frame-memo-parked`. Side finding: for rows without reactions, every read of `ChatRowItem.reactionsLayout` re-runs `effectiveReactions` and returns nil (only a created layout is stored), and several geometry getters read it.

## 2026-10-19: table rows without a backing store (parked)

`TableRowView` overrides `draw(_ dirtyRect:)` with an empty body (to keep `NSTableRowView` from drawing its own background and selection), and an overridden `draw(_:)` makes AppKit give the view a full-size bitmap. So every table row in the app had one, although most rows draw nothing: chat rows are layer trees, and the row's own `draw(_:in:)` only paints a border when one is set. In the chat window that was 1.1 megapixels for a photo row, about 9 MB in this display's 16-bit backing format. `TableRowView` now follows TGUIKit `View`'s rule: a row class that doesn't override `draw(_:in:)` or `draw(_:)` and has no border answers `wantsUpdateLayer`, so it gets no bitmap. Rows that draw (subclass overrides, borders) keep the drawing path, and a row that drew before clears its contents when it switches. No row subclass sets its own layer's contents.

`census` (new `censusDrawingViews` / `censusDrawingMPixels` / `censusDrawingClasses`, the drawing views and their backing pixels): "Telegram macOS Talk" window 53 drawing views / 5.55 MP → 31 / 1.27 MP (−77 %, about 34 MB at 8 bytes per pixel); chat rows (`ChatMediaView` 2.2 MP, `ChatMessageView` 0.5 MP), date headers (0.35 MP) and chat-list rows (0.97 MP) no longer have bitmaps. Pixels: new `rowbacking` scenario: in one run, the old behavior (DEBUG `TableRowView.debugForcesBackingStore`) and the new one alternate (old, new, old, new) with every visible row redisplayed, and each row's window crop is compared: 77/77 and 66/66 stable rows identical in two runs (rows with animated content counted unstable), row views with contents 11 → 1. A cross-build snapshot comparison was not usable (chat-list times and online counts change between runs). CPU, interleaved, `-PerfLabRowBacking 1` for the old behavior: 16,000 pt/s 39.60 / 38.29 % old vs 39.21 / 38.38 % new, 2400 pt/s 15.50 / 16.42 vs 15.29 / 15.84 %: no measurable difference; this is a memory change. `Button` has the same pattern (an override of `draw(_:in:)` that only calls super gives every Button a bitmap, e.g. the reply preview's `ChatAccessoryView` at 97 kP); not changed yet.

Parked the same day, not shipped. The 2026-09-02 memory pass made exactly this change and `42bf0af89` (2026-09-24) reverted it: rows turned solid white while scrolling fast (Buy a Gift grid). Reproduced in a standalone AppKit harness (`evidence/2026-10-19-table-row-backing-parked/white-row-harness.swift`): NSTableView sets every row view's `backgroundColor` to the table's background color, and on the `updateLayer` path `NSTableRowView` adds a background sublayer painted with it, with or without calling `super.updateLayer()`; with a white table background every captured frame had 56,030 white pixels, the drawing path none. The in-app `rowbacking` lab missed it because the chat table's background is clear. Pinning `NSTableRowView.backgroundColor` to clear in the row (it was never visible on the drawing path) removes the white pixels in the harness, but every table in the app is affected and selection highlighting and light-theme screens are unverified, so the change (`table-row-backing.patch`) waits for a verification pass over the other table screens. The census metrics stay.

## 2026-10-19: reply preview as a row-scene node

The reply preview was a `ChatAccessoryView` (a `Button`, so a full-size backing bitmap of its own) plus a `TransformImageView` for the thumbnail, added to and removed from the row on every bind that changes whether there is a reply (`fillReply` was the largest bind cost in the 16,000 pt/s profile, 1.7 % of the main thread, about a third of it NSView creation, insertion and removal). In bubble rows it is now a `ChatLayerControlNode` ("reply") in the row scene whose layer is the content layer of a detached `ChatAccessoryView(layerHost:)`: the view never joins the view hierarchy and adds every sublayer (background, line, header and message `TextViewLayer`s, poll and quote icons, pattern emoji, gift emoji) to the node's layer instead of its own; the thumbnail is a `TransformImageLayer`. `ReplyModel` reaches the thumbnail through `ChatAccessoryImageHost` (implemented by `TransformImageView` and `TransformImageLayer`) and the scale through `accessoryScale`, so its code is the same for both hosts. The node's layer copies the AppKit backing layer of a TGUIKit `View` (anchor at the origin, clipped, opaque flag, continuous corners, no edge antialiasing). A model can be hosted only when it is a plain `ReplyModel` with no text that needs a native `TextView` (custom emoji, spoilers, tooltips, block quotes, blocks, mask images), no loading shimmer and no summary; story replies, rows without a bubble (where the forward accessory and via accessory re-parent the reply view) and replies that load later stay `ChatAccessoryView`s. If a later model update cannot be hosted, the layer host asks the row to rebuild that reply as a view on the next turn of the run loop. Size changes the model makes itself (`setFrameSize` after loading) resize the node; layout changes keep the view's behavior (the frame animates with the transition, the content is laid out at the final size).

Parity in "Telegram macOS Talk", 15 reply rows per path, 7 with media thumbnails: 46/48 stable rows identical; the two differences are the known animated-reaction rows (diff boxes on the duck and "100" reactions, identical to earlier runs). A 1 pt reply shift (`-PerfLabParityMutateReply 1`) is caught on all 15 reply rows; `replyHitOK` / `replyHitTotal` 30/30 (the window's hit test reaches the reply node at its center). Saved Messages has no replies (47/47). ChatLayerEngineLab 441 tests, 0 failures. Other users of `ChatAccessoryView` (input panel previews, the pinned-message header) keep the view path; their image calls resolve to the same `TransformImageView` calls with the same arguments.

Follow-up: a fling profile showed the node path still creating and releasing a detached `ChatAccessoryView` (Button init and deinit, about 50 ms per 40 s trace) whenever a reused row gained or lost a reply, the same churn the view path has. A reply node removed without animation (every scroll-time rebind) is now kept as the row's spare and reused for the next reply; `updateModel` already handles switching models (the view path reuses its view the same way). 16,000 pt/s fling, `fillReply` per trace: view path 229 ms (1.7 % of main), first node version 281 ms (2.4 %), with the spare 217 ms (1.9 %); the traces differ in length and content, so only the direction is meaningful. The whole-window walk (`_recursiveTickleNeedsDisplay`) is 7.2 % → 6.5–6.8 % of main in the same traces. Parity unchanged (46/47 stable rows, the remaining difference is the known animated row).

Second follow-up: replies to copy-protected messages stay `ChatAccessoryView`s (the fail-closed `TransformImageLayer` drops sample-buffer cache entries, the view shows them, so the layer path is limited to where both render the same); the reply thumbnail layer is told when its row enters a window, like `TransformImageView.viewDidMoveToWindow`, so `ScopedImageCache` keeps attributing it; and the fallback has a lab switch, `-PerfLabParityReplyFallback 1`, which rejects every layer-hosted reply on its first update. With it every reply is rebuilt as a view on the next run-loop turn (`replyNodes` 0, `replyViews` 60, 28 thumbnails), and the rows match the native path except the two known animated-reaction rows and two rows whose animated emoji status landed on another frame (diff box on the status emoji, not the reply). Normal run: 47/47 stable rows identical, `replyHitOK` 30/30.

## 2026-10-19: chat photos on a TransformImageLayer

`ChatInteractiveContentView` drew every photo and video thumbnail with a `TransformImageView` subview. Plain photos now use a `TransformImageLayer` in the content view's own layer instead (one NSView fewer per photo, so one fewer view to insert, remove and walk when the row enters or leaves). The two hosts sit behind a small `ChatMediaImageHost` in the same file that exposes exactly what the view used (signals, arguments, the fully-loaded flags, size changes mirroring `_change(size:)`, opacity, `copy()`, `contents`). The layer is at `zPosition` -1, so it renders under every overlay subview (progress, accessories) whatever order AppKit keeps sublayers in, and it is noted for `ScopedImageCache` through the content view when that enters a window. A photo uses the layer only when it is a `TelegramMediaImage` without a live-photo video, not protected (`preventsCapture` has no layer equivalent), not a spoiler (ink view) and not secret media; videos, GIFs, live photos and the rest keep the view. The content view is reused across media kinds, so it switches host on update and carries the current image over when it stays the same message (a spoiler reveal does not flash). The gallery's `copy()` builds the same snapshot view `TransformImageView.copy()` builds.

Parity, photos per path: Saved Messages 11 (47/47 and 46/46 stable rows identical), "Telegram macOS Talk" 17 (44/45 and 44/46; the differences are the known animated rows, diff boxes on the sender's animated emoji status and the "100" reaction). A 1 pt image shift (`-PerfLabParityMutateMedia 1`) is caught on 10 photo rows, the 11th unstable in that run. Gallery snapshots (`copy()` on both paths for the same item, compared by frame, clipping, rasterization and image pixels): 11/11 and 16/16 identical. `photoLayers` / `photoViews` count the hosts on each path.

Video and GIF thumbnails (`TelegramMediaFile` with `isVideo` or `isAnimated`) now use the same layer, under the same conditions (not protected, not a spoiler, not secret media). With the image as a layer, "directly above the image" for the autoplay and live-photo players becomes "first subview" (`placeAboveImage` / `isPlacedAboveImage`), so they stay under the duration badge and progress views; the thumbnail layer is at `zPosition` -1 either way. The parity lab counts the hosts (`videoLayers` / `videoViews`), lists each video row's outcome (`videoRows` note), includes video rows in the gallery snapshot comparison and names the rows whose snapshots differ (`snapshot` note). When a chat title is not in the local store (a fresh login keeps only part of the chat list), the lab falls back to the server search, own chats first.

Parity, "Telegram macOS Talk", 49 rows, 7 video/GIF rows (14 hosts per path): 42/43 stable rows identical, every video row identical; the one difference is row 27, a text row whose sender's animated emoji status landed on another frame (268 pixels, all inside the status emoji; `nativeStatic`). Gallery snapshots 23/23 identical, video rows included. Saved Messages 5/5 (no video rows in this account's local history). A 1 pt image shift (`-PerfLabParityMutateMedia 1`) is caught on 6 of 7 video rows, the 7th unstable in that run (GIF playing), and on the photo rows as before.


## 2026-10-19: finding, glass date pills relayout on every scroll step (not changed)

A `sample` profile of "Telegram macOS Talk" at 2400 pt/s showed about 70 % of the window layout pass in SwiftUI (`AG::Graph` updates) inside `_NSCoreHostingView<RootView>`, the host inside `NSGlassEffectView`. By layout depth it is the glass of the date pills that are rows in the table (`ChatDateStickView` → `LiquidGlassView` → `AdaptiveGlassEffectView`), 533 samples, against 37 for the sticky header's glass, which does not move in the window. An lldb breakpoint on `-[NSView setNeedsLayout:]` for hosting views shows why: every clip-view scroll step (`translateOriginToPoint:`) posts AppKit's geometry-in-window notification down the document, the glass host observes it and invalidates its view graph, and the next display cycle lays it out again. This is AppKit's glass behavior, not a call from our code (the DEBUG `tg_swizzled_setFrame` detector is a pass-through).

`-PerfLabDateBlur 1` (DEBUG) builds the date pills with `LiquidGlassView(forceBlur: true)`, the existing blur fallback, to measure the ceiling. Interleaved A/B, 3 rounds × 2 passes: glass 20.69 / 20.96 / 20.55 % main, blur 19.59 / 19.67 / 19.65 % (mean −1.1 points, −5 %); hitches, worst frame, process CPU and GPU unchanged. Dropping glass from in-table pills changes how they look, so it is left as a design decision.

Follow-up, 16,000 pt/s fling (optimized build, 3 passes each, `sample` of the same window): glass 31.46 % main thread (median), hitches 42.2 %; blur 28.02 % main thread, hitches 32.6 %. In the profiles window layout (`___NSViewLayout_block_invoke`) drops from 6.6 % to 0.6 % and SwiftUI frames disappear (2,367 lines → 2), CA commit 25.9 % → 21.5 %, `prepareContentInRect` 8.2 % → 5.7 %. In a fling the pills are the largest single cost a chat row adds; the decision is still a design one.

A standalone probe (10 `NSGlassEffectView`s over a striped background, 400 steps, time to display and flush each step) separates moving glass from glass being scrolled: no glass 0.46 ms per step, glass inside a scrolled document 1.9–2.2 ms, the same glass in a non-scrolling overlay with its frame origin moved 2.3–2.5 ms, and the overlay moved by its layer's `sublayerTransform` 0.10 ms, with screenshots of the last two pixel-identical. Any glass whose AppKit geometry in the window changes is laid out again through SwiftUI; glass moved by Core Animation alone is not. That keeps a look-preserving option open: draw the in-table pills' glass in a layer between the wallpaper and the table, translated by the scroll offset, with the pill text left in the row. It was not built: the glass would have to follow every row animation (history merges, the animated scroll when a message arrives, insert springs, the hover-expand width), which Telegram drives with Core Animation on the rows themselves.

## 2026-10-19: ChatRowItem.leftInset without copying the history entry

Profiles from here on use an optimized build of the Debug configuration (`SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule`, so the DEBUG labs are kept); the -Onone build overstates Swift getters. In that build the remaining app-side scroll cost is small (`TableView.updateScroll` 1.2 % of main-thread samples, `ChatRowView.set(item:)` 0.3 %); AppKit's tracking-area walk (2.2 %), window layout (3.1 %, mostly the glass date pills above) and display dominate. Tracking areas are marked dirty about 71 times per pass, all by new rows, row frames and sticky-header rebinds.

`leftInset` is read for every floating-avatar group on every scroll step and read `entry.additionalData.monoforumState`, which copied the whole `ChatHistoryEntry` each time. Whether the entry has a vertical monoforum is now stored when the item is created (the entry, `isIncoming` and `renderType` never change afterwards). `sample`, "Telegram macOS Talk" at 2400 pt/s, same pass: `leftInset` 24 → 3 samples, entry copies 12 → 4 (about 0.1 % of the main thread; below run-to-run noise in macro metrics).

Follow-up, 16,000 pt/s fling (optimized build): the remaining `ChatHistoryEntry` copies came from `effectiveCommentMessage` (a `switch entry`, read by `hasPhoto` and others on every bind and layout) and `stableId`. Both depend only on the entry, so they are now stored when the item is created; `stableId` stays an overridable property. `sample` of the same fling, main thread: `effectiveCommentMessage` 17 → 0 samples, `stableId` 6 → 0, `entry` getter 20 → 3, entry copies 15 → 3. Parity in the same build: 39/41 stable rows identical, the two differences are the known animated emoji status (row 14) and the animated "100" reaction (row 35).

Follow-up, reaction and avatar binds: `NSFont.avatar(_:)` checked the shared font cache but never stored into it, and that cache is only prefilled for whole sizes 10–19, while avatars ask for `height / 3 + 3` (9.67 for a 20 pt reaction avatar). Every avatar layer, including each reaction-chip avatar on every bind, built a rounded bold font through a font descriptor. Avatar fonts for other sizes are now kept in their own cache behind a lock (the font can be requested off the main thread). 16,000 pt/s fling, `sample`, main thread: `NSFont.avatar` 13 → 1 samples, `AvatarContentLayer.init` 26 → 10.

Checked, not changed: in a 16,000 pt/s fling profile, 1.6 % of main-thread samples built chat items (`prepareEntries` → `makeItem`) on the main thread. The scroll lab now reports `mainThreadItems` per pass (counted from the start of the pass): 0 in every fling pass, while history merges (8–11 per pass, about 70 rows swapped each) are prepared on the history queue. The main-thread builds come from the lab's `scrollToLatest` between passes, an `.Initial` reload that is prepared on the main queue on purpose (`prepareOnMainQueue`), as the scroll-to-bottom button does.

## 2026-10-19: where chat row time stands (optimized build, main thread, `sample`)

| Scenario | Row bind (`ChatRowView.set`) | Row insertion (`_addRowViewForVisibleRow`, includes bind) | Largest other cost |
|---|---|---|---|
| "Telegram macOS Talk" scroll, 2400 pt/s | 0.3–0.4 % | ~1 % | glass date pills' SwiftUI layout 2.0 %, tracking areas 2.0–2.2 % |
| Same chat, 16,000 pt/s fling | 1.5–2.3 % | 5.7–6.8 % | Core Animation commit 23–27 %, window layout 4.6–5.2 % |
| Chat open, 12 opens | ~5 ms per open (`rowViewForRow`) | — | navigation push and view insertion; glass SwiftUI layout 1.4 % |

Checked and left: batching floating-avatar detaches (updates almost always move one avatar, no change in a fling profile, reverted); an incremental node index for `ChatLayerNode.setChildren` (at most ~0.2 % of a fling, in tree code every row uses); `TableRowView.cursorUpdate` forwarding (0.35 %); AppKit's key-view-loop layout on row insertion (layout the pass does anyway). Earlier sample totals in this log that came from a parser counting every thread were re-checked against the main thread alone; the numbers above and in the entries today are main-thread counts.

## 2026-10-19: reaction avatar clip images and the right view's blur view

Reaction-chip avatars (`AvatarContentLayer`, `AvatarContentView`) drew a second, clipped copy of every avatar with Core Graphics on the main thread on each bind, even when the avatar came from the memory cache (the cached signal emits synchronously). The clipped image is now kept in an `NSCache` keyed by the source image, frame size, inset and scale; the entry keeps its source image so a hit is checked by identity. `ChatRightView` created and removed an `NSVisualEffectView` whenever a reused row switched between a blurred media row and a plain row; the view is now hidden and shown, and `canHostContent` ignores it, so plain rows still host the right view in the row layer. 16,000 pt/s fling, `sample`, main thread: `AvatarContentLayer.init` 23 → 6 samples, `fillReactions` 69 → 34, `blurBackground` setter 11 → 1, `ChatRowView.set(item:)` 213 → 170 (1.9 → 1.5 %). Parity twice in the same build: 40 and 43 stable rows identical, the one difference both times is the animated "100" reaction (row 35); hosted right views 84 and reaction-chip hit tests 50/50, as before.

## 2026-10-19: reuse floating avatar nodes

A 16,000 pt/s fling pass in "Telegram macOS Talk" creates and removes about 463 floating avatars (each group gets a new `ChatFloatingAvatar` when the visible grouping changes). Layer-based avatar nodes removed from a scene (after the fade, when animated) now go to a pool of up to eight on `ChatControllerView`, and new node avatars take one from it; the context menu is reset on reuse, and `AvatarImageLayer.setPeer` already clears the image when the peer changes (and skips work when it is the same peer). The scroll lab reports `floatingReuses`: 409–411 of 463 creates per pass. `sample`, main thread: `ChatFloatingAvatarNode.init` 11 → 0 samples, `ChatFloatingAvatar.init` 51 → 37, `collectFloatingPhotos` 140 → 112. `floatparity` 10 equal, 0 different (avatar hit checks 59/88, the same as before the change: the misses are points under glass bars and date pills or just off screen), row parity 52 equal with the known animated reaction (row 35) and an autoplaying video (row 19) different.

## 2026-10-19: sticky header bookkeeping without class-name strings

`TableView.updatePrimaryStickAfterScroll` (and its secondary twin) runs on every scroll step and compared classes through `NSObject.className`, which builds a string with `NSStringFromClass` per call, for every table subview and the candidate rows. One of those comparisons matched subview class names against the stick *item* class, so it never matched and the sticky view was re-added below the scroller on every step. Item checks now use `isMember(of:)`, view checks compare `object_getClass`, the position check looks for the sticky view itself, and the scroller search drops the clause that could not match. 16,000 pt/s fling, `sample`, main thread: `updatePrimaryStickAfterScroll` 49 → 37 samples, `NSStringFromClass` 13 → 0. Snapshots of the same chat show the sticky date pills as before.

## 2026-10-19: one floating-avatar pass per scroll step

Each scroll step positioned floating avatars twice: `scrollDidUpdate` (from `scrollDidChangedBounds`) ran `updateFloatingPhotos` with the current grouping, and when the visible range changed the range listener then regrouped in `collectFloatingPhotos` and positioned them again, so the first pass placed and moved avatars for groups that were replaced before the frame was drawn. `scrollDidUpdate` now goes through `collectFloatingPhotos`, which regroups first when the visible range or its edge messages changed and otherwise goes straight to the same positioning. 16,000 pt/s fling, `sample`, main thread: `ChatControllerView.updateFloating` 134 → 99 samples, `TableView.updateScroll` 291 → 266 (the per-step range check adds a little to `collectFloatingPhotos`). `floatparity` 10 equal, 0 different; row parity 54 equal, 0 different; floating avatar counters per pass unchanged within noise.

## 2026-10-19: correction, the glass date pills cost nothing measurable outside a profiler

The fling numbers in the glass follow-up above (glass 31.46 % main thread and 42.2 % hitches against blur 28.02 % and 32.6 %) were taken while `sample` was attached, and they do not hold without it. Interleaved runs without a profiler, optimized build, "Telegram macOS Talk":

| Run | 16,000 pt/s fling (3 passes) | 2400 pt/s scroll (2 passes) |
|---|---|---|
| glass | 31.18 / 31.18 % main, hitches 1.37 / 1.30 % | 19.80 / 20.22 / 21.23 % main, hitches 0.25 % |
| blur | 31.09 / 31.20 % main, hitches 1.36 / 1.17 % | 19.62 / 20.82 / 20.99 % main, hitches 0.23–0.32 % |

The differences are inside run-to-run drift (the 2400 pt/s rounds drift by 1.4 points from round to round, more than any mode difference). `sample` suspends the process about every millisecond, and under it the fling hitch rate rises from about 1.3 % to about 40 %, so profiles still rank where main-thread work goes, but timing comparisons between modes have to come from runs without it. The earlier −1.1 point scroll result for blur was a single interleaved set and is not reproduced here.

A look-preserving prototype was also built and dropped: the in-table pills' glass drawn in a DEBUG overlay between the wallpaper and the table and moved with a layer `sublayerTransform`, with the row's own glass taken out of the document and the overlay's glass views pooled. It cut window layout under `sample` from 6.6 % to 3.6 % and hosting-view invalidations from 27 to 9 in a 15 s lldb window, but without a profiler it measured the same as glass and blur (fling 31.24 / 31.43 % main, scroll 19.72 / 21.27 / 21.38 %), so it was removed rather than committed.

## 2026-10-19: item building on the history queue

Chat items are built and measured off the main thread, and a 16,000 pt/s fling spends about 140 samples there in `makeItem` (all threads, `sample`). Three costs in it were repeated work:

- `stringForMediumDate` (the "edited" label's date) created a `DateFormatter` and formatted a time on every call, then returned `DateUtils.string(forLastSeen:)` for any past date without using it. The formatter is now created only for future dates. 19 → 2 samples; `ChatRowItem.init` 53 → 36.
- `ChatRowItem.reactionsLayout` kept a built layout but not a missing one, so for messages without reactions every access copied the entry, checked `unsupported` and computed `effectiveReactions` again. It now remembers "no layout" when the reason cannot change (log, fake or saved-messages entry, unsupported message, no reactions on the message); a missing `available` reactions list is still checked again because it loads later. 10 → 8 samples, so most items read it once.
- `NSAttributedString.trimNewLinesToSpace` (reply previews and others) compiled the `\n` regular expression on each call; it is compiled once.

Parity 45 equal, 0 different; `floatparity` 10 equal, 0 different (avatar hit checks 58/88).

The timing baseline moved during this session for reasons outside the code: with no profiler, the 16,000 pt/s fling now drops frames (about 1,250 frames per pass instead of 1,516, hitches about 19 %) and the 2400 pt/s scroll hitches about 0.9 %, with main-thread busy unchanged or lower and no thermal warning recorded. A rebuild of the parent commit measured the same (fling 19.72 % hitches, 29.60 % main; scroll 0.98 %, 16.75 %) as this change (fling 18.52 %, 30.64 %; scroll 0.87 %, 17.89 %), so compare later runs against a baseline taken in the same sitting.

## 2026-10-19: row insertion and removal, notification observers and pointer tracking

Rows that scroll out are removed from the table and rows that scroll in are added, and part of that cost was app code reacting to the window change:

- `AnimatableContentObserver` (media rows' content listeners) unregistered with `NotificationCenter.removeObserver(_:)`, which scans every registration in the process. It now removes the name and object pairs it added, holding the objects weakly, and falls back to the full removal if one of them is gone. A new test detaches and reattaches a view in a different scroll view and checks that only the current one is followed.
- `ChatLayerSceneView.updateTrackingAreas` removed the pointer tracking area whenever a scene left the window and created a new one when it came back. The area is now kept while the scene is out of a window; AppKit keeps tracking areas with the view.

16,000 pt/s fling, `sample`, main thread: `_CFXNotificationRemoveObservers` 41 → 19 samples, `ChatLayerSceneView.updateTrackingAreas` 21 → 11, `_NSTrackingAreaAKViewHelper addTrackingArea:` 35 → 25. The scroll lab now reports `scenesTracking` and `scenesMissingTracking` (visible scenes that should track the pointer and whether their area is installed): 6 and 0 after every pass. Parity 45 equal, 0 different; `floatparity` 10 equal, 0 different (avatar hit checks 59/88).

## 2026-10-19: keep `Control` tracking areas out of the window

`Control.updateTrackingAreas` had the same pattern as the layer scenes: it removed its tracking area when the control left the window and created one when it came back, for every control in every row that scrolls in. It now keeps the area while the control is out of a window and still removes it in a window when `visibleRect` is empty. The scroll lab's tracking check now also counts visible `Control`s in the table without a tracking area: 7 tracked, 0 missing after every pass (scenes 6 and 0). 16,000 pt/s fling, `sample`, main thread: `addTrackingArea:` 25 → 15 samples, `Control.updateTrackingAreas` 16 → 8, row `addSubview` 112 → 93. Parity 45 equal, 0 different; `floatparity` 10 equal, 0 different (avatar hit checks 59/88).

## 2026-10-19: one accessory update when a reply view is attached

Assigning `ReplyModel.view` ran `ChatAccessoryView.updateModel` twice: the base `ChatAccessoryModel.view` observer removes the accessory image and updates the view, then `ReplyModel`'s observer adds the reply thumbnail and updated the view again. `updateModel` does not read the thumbnail, so the second update repeated the first. `updateImageIfNeeded` now skips it when called from the view observer; frame changes still update the view. A first attempt skipped the base update instead and was dropped: the thumbnail layer was then created before the gift pattern layers and parity showed the pattern drawn over the thumbnail (row 44, a reply to a video with a pattern). 16,000 pt/s fling, `sample`, main thread: `ChatAccessoryView.updateModel` 20 → 14 samples, `ChatRowView.fillReply` 40 → 31, `ChatRowView.set(item:)` 186 → 161. Parity twice: 45 and 43 equal, 0 different.

## 2026-10-19: the pointer over the chat, and cursor updates during scrolling

The jump in fling hitches recorded above (about 1.3 % to about 19 % with the same main-thread time, in the parent build too) was the mouse pointer, which had come to rest over the chat window. The scroll lab now takes `-PerfLabCursor inside|outside` to place the pointer at the table's centre or beside the window before each pass, and reports `cursorInWindow`. Same build, 16,000 pt/s fling: outside 0.46 % hitches, 28.51 % main; inside 17.46 %, 29.48 %.

With the pointer still and rows moving under it, every tracking area with `.cursorUpdate` that passes the pointer posts a cursor-update event, and `-[NSApplication sendEvent:]` routes each one through `routeCursorRect` → `_NSFindWindowUnderMouse` → `SLSCopyWindowRoutingRecordsForScreenLocation`, a synchronous WindowServer call (12 % of main-thread samples in a sampled fling; type 17 at a breakpoint there). The app now runs as `TGApplication` (TGUIKit, created in `main.swift` before `NSApplicationMain`), which keeps only the latest cursor update while a `ScrollView` has received a scroll event in the last 0.1 s and delivers it when scrolling stops. The cursor after a scroll is the one the last update set, as before; hover still follows entered and exited events. The lab reports `cursorUpdatesDeferred` and `cursorUpdatesDelivered`: about 1,200 deferred and 1 delivered per pass with the pointer inside.

| Run, pointer inside | Hitches | Main thread |
|---|---|---|
| 16,000 pt/s fling, before | 17.46 % | 29.48 % |
| 16,000 pt/s fling, after | 2.08 % | 30.98 % |
| 2400 pt/s scroll, before | 0.87–0.98 % | 17.9 % |
| 2400 pt/s scroll, after | 0.35 % | 18.74 % |

With the pointer outside: fling 0.39 % (0.46 % before). Parity 43 equal, 0 different; `floatparity` 10 equal, 0 different (avatar hit checks 59/88). Timing comparisons from here on should state the pointer placement.

## 2026-10-19: one pressure configuration for every table row

With cursor updates deferred, the rest of the cost of a pointer over the chat was `-[_NSTrackingAreaAKManager _updateActiveTrackingAreasForWindowLocation:]` → `_updateTrackpadBehavior` → `SLSTrackingRegionSetForceConfig`, another synchronous WindowServer call (6.9 % of main-thread samples in a sampled fling with the pointer inside). `_updateTrackpadBehavior` takes the pressure configuration of the active tracking area's view and calls WindowServer when it is a different object from the last one. Every `TableRowView` created its own `NSPressureConfiguration(pressureBehavior: .primaryDeepClick)`, so each row passing under the pointer counted as a change. Rows now share one configuration object; the behaviour is the same deep click.

| Run | Hitches | Main thread | CPU cores |
|---|---|---|---|
| 16,000 pt/s fling, pointer inside, before | 2.08 % | 30.98 % | 0.68 |
| 16,000 pt/s fling, pointer inside, after | 0.52 % (0.58 %, 0.20 % in two more runs) | 28.42 % | 0.59 |
| 16,000 pt/s fling, pointer outside, after | 0.65 % | 27.02 % | 0.58 |
| 2400 pt/s scroll, pointer inside, after | 0.38 % | 18.54 % | 0.27 |

With the pointer inside the chat a fling now hitches as little as with the pointer outside. Parity: 40 equal with rows 7 and 19 different (both videos, reported as `layerAnimates`), then 43 equal with the animated reaction row (35) different; `floatparity` 12 equal, 0 different.

## 2026-10-19: correction, the cursor-update deferral is not needed, and a bind-step probe

After rows shared one pressure configuration, the scroll lab counted no cursor-update events at all with the pointer inside the chat (`cursorUpdatesDeferred` and `cursorUpdatesDelivered` both 0 in every pass, against about 1,200 deferred before). The cursor updates were AppKit re-evaluating the cursor each time the pressure configuration under the pointer changed, so the shared configuration removes them at the source. `TGApplication` and its scroll hook are removed again; cursor behaviour is as before that entry. Interleaved 16,000 pt/s flings on the build without it, while another app kept the machine busy (load average 3.5–3.9): pointer inside 5.06 % and 4.62 % hitches, outside 5.20 % and 4.81 %, so the pointer costs nothing measurable now. (The higher absolute level comes from the load: the previous build measured 28.5 % main and 0.58 % hitches on a quiet machine.)

`sample` and `vmmap` currently hang on this machine before attaching (even to Finder), so the scroll lab now reports bind time per step of `ChatRowView.set(item:)` (`binds`, `bindMs_<step>`, DEBUG only). 16,000 pt/s fling, pointer inside, 578 binds per pass: reactions 17.7 ms, reply 15.1, status 7.8, name 7.4, right view 6.0, layout type 5.4, caption 5.3, forward 1.6, everything else under 1 ms; about 126 µs per bind in the base row in total.

## 2026-10-19: profiling with xctrace, and the benchmark chat

`sample` and `vmmap` stopped attaching on this machine (they hang before printing anything, even for Finder). `xctrace` still works, and it does not suspend the process the way `sample` does. `tools/perflab/run.sh` now takes `PERFLAB_PROFILE=<delay>:<seconds>`: it attaches the Time Profiler to the lab app after the delay and exports the samples to `results/<lab>-<label>-profile.xml`, and `tools/perflab/profile.py <xml> [regex]` prints main-thread inclusive counts (`profile.py <xml> '' under '<symbol>' <depth>` breaks one symbol down).

From about 21:55 the benchmark chat "Telegram macOS Talk" opens with "Sorry, this group is not accessible." and a Join button, so scroll passes report `avg_rows` 1 and `scrolledRange` 0. Runs after that time measured an empty chat; every result in this log was taken before it (the last full pass at 21:50 scrolled 191 rows over 26,331 pt).

Correction at 23:15: membership is lost too. After the long flood wait expired the server still answers `400 USER_NOT_PARTICIPANT` and the group opens with a Join button, so "Telegram macOS Talk" needs the account owner to rejoin before it can be the benchmark again. The flood wait explains why every other remote chat came up empty in the same window: at 21:54:44 the server answered with `420 FLOOD_WAIT_4360` (73 minutes) and the request failed, and the same screen then appears for "jewproxy changelogs" and the public `@telegram` channel ("No messages here yet"), while Saved Messages still scrolls from the local database. Every lab launch reconnects and resyncs the real account; today's logs hold about 700 flood waits, including 2,594 s and 8,202 s waits at 18:03. Space out lab runs against a real account, and check `debug/logs` for `FLOOD_WAIT` before trusting a run with `scrolledRange` 0.

## 2026-10-19: reactions container skips the effect hop when nothing was newly selected

`ChatReactionsView.update(with:animated:)` queued a `DispatchQueue.main.async` block on every bind to play the select effect, and the block returned at once when no reaction had just been selected, which is every bind during a scroll. It now returns before queuing when `new` is empty; when a reaction was just selected the block runs exactly as before. Reactions were the largest bind step (24 ms over 578 binds in `lblcache1/2`), but this hop runs after the bind, so `bindMs_reactions` does not include it. Not measured yet: no remote chat had content at the time (see above).

## 2026-10-19: picking a benchmark chat without the benchmark group

`-PerfLabScenarios list` writes every read channel and basic group in the main chat list (the sweep's candidates: nothing unread, so opening one changes no read state) to the report as `peerId`/`title`, and `-PerfLabPeerId <id>` opens one of them directly. At 23:16 the only real candidate, "Анекдоти, за які нам соромно" (member, Unmute bar), also opened as "No messages here yet" and the run issued no `messages.getHistory` at all, while Saved Messages still scrolled from the local database. Remote history is not being requested for channels on this account right now; benchmarking stays blocked until a chat with stored history is available.

## 2026-10-19: why remote chats stopped loading at 21:54

The first log line of the 21:54:44 launch is `[Api] Type constructor b90c2afd not found`. From then on the server answers `users.getFullUser` and `channels.getFullChannel` with constructors this build's `swift_scheme.tl` does not have (`b90c2afd`, `fbce613`, `adf3f567`, `c4c4dd40`; 464 times by 23:18), and the responses log `could not be parsed` (181 `users.getFullUser`, 36 `channels.getFullChannel`). No earlier log today has a single parse failure. The generated TelegramApi copy (14:04) matches the schema (14:00) and was unchanged through every good run, so this is the server sending objects from a newer layer, not the build. Without a parsed full channel the chat opens as not accessible or empty, which is what every remote chat has shown since. The flood waits and the lost "Telegram macOS Talk" membership are real but secondary. Chat benchmarks need a schema that knows these constructors, or the server to stop sending them to this layer.

## 2026-10-19: a synthetic chat for benchmarks that need no server

`-PerfLabSynthetic <count>` opens a real `ChatController` over `ChatSyntheticContents`, a `ChatCustomContentsProtocol` built entirely in memory (the same mechanism as the HTML demo chats): a fake basic group with eleven fake members, `count` text messages of one to three sentences, a reply on every fourth message (with the replied message in `associatedMessages`), one to four reaction chips on every third, and every ninth outgoing. Timestamps start from a fixed base, so snapshots of two builds compare pixel for pixel. Nothing is stored in Postbox or sent, and no media is included (a fake resource would be fetched from the server). With 400 messages a 3 s fling at 16,000 pt/s scrolls 37,353 pt and binds 786 rows per run, and the bind steps repeat within about ±2 ms, so A/B runs need no real chat.

Baseline app copies for A/B must sit at a path ending in `Debug/Telegram.app` (for example `/Users/tmac/Projects/perflab-base/Debug/Telegram.app`): `run.sh` finds the lab process with that pattern, and a copy elsewhere returns at once and overlaps the next run.

## 2026-10-19: keep a spare reactions container per row

Profiling the synthetic fling put 94 of 1,652 main-thread samples in `fillReactions`, and a third of those were not chips: when a recycled row went from a message with reactions to one without, `ChatReactionsView` was removed from the row (`-[NSView removeFromSuperview]`, 20 samples of window and superview teardown) and a new one created and added for the next message with reactions (init 6, `addSubview` 8). A non-animated removal now clears the container's chips (`removeAllChips`, which detaches each chip through its own `removeFromContainer`), hides it and keeps it as the row's spare; the next reactions fill unhides it with the new frame. `reactionsView` is still nil whenever the row shows no reactions, so every existing check keeps its meaning, and an animated removal still animates out as before.

Interleaved A/B, synthetic chat with 400 messages, two rounds of three flings per side: `bindMs_reactions` 75.6 → 63.8 ms per fling (−16%; ranges 73.3–77.6 and 62.0–67.2), other steps unchanged, main thread 23.9% → 22.5%. Snapshots are identical in the chat pane; the only differences are chat-list timestamps, which differ between two baseline runs as well.

## 2026-10-19: the spare reactions container keeps its chips

With the container reused, the profile still spent 13 samples clearing chips, 9 creating them, 15 attaching them and 14 fetching each new chip's emoji layer (`getInlineLayer`), out of 2,318 main-thread samples. The spare now keeps its chips. The next non-animated `update(with:)` recycles them through the reuse path that already served non-animated updates, preferring a chip that shows the same reaction, so most binds create, attach and look up nothing. While the spare is hidden its chips cannot play: a hidden view and every view under it report an empty `visibleRect` (checked with a standalone AppKit program), which is what emoji playability reads, and `ChatReactionsView.isHidden` now asks each chip to recheck its emoji visibility whenever it changes (`chipVisibilityChanged`, for node chips and both view kinds) instead of waiting for the next scroll notification.

Interleaved A/B against the build before the spare container, synthetic chat with 400 messages, two rounds of three flings: `bindMs_reactions` 76.2 → 40.8 ms per fling (−46%; ranges 74.4–77.6 and 40.3–41.7; the container alone had reached 63.8), other steps unchanged, main thread 23.9% → 22.7%. Snapshots differ only in the chat list, as two baseline runs do.

## 2026-10-20: the bubble mask skips its colour conversions

`renderLayoutType` spent 18 of its 22 samples in `ChatRowItem.bubbleImage`: `messageBubbleImageModern` converted its fill and stroke colours to device RGB on every call just to build the cache key (`NSColor.argb`, 8 samples), and `bubbleNeighbors` copied the whole `ChatHistoryEntry` to test `case .MessageEntry` (5 samples). Chat rows always ask for the black-on-clear mask, so `messageBubbleMaskImage(incoming:neighbors:)` now passes the two keys computed once; the cache, its keys and the generated images are the same as before, and every other caller still goes through `messageBubbleImageModern`. The item stores whether its entry is a `.MessageEntry` at init (`entry` is only assigned there). The check stays before `reactionsLayout`, which caches a layout and captures an analytics context when first read, so the order in which that happens is unchanged.

Interleaved A/B against HEAD (135f7c99c), synthetic chat with 400 messages, two rounds of three flings: `bindMs_renderLayoutType` 6.6 → 2.4 ms per fling (−63%; ranges 6.6–6.8 and 2.3–2.5), total bind time 81.0 → 75.9 ms, other steps unchanged. The chat pane is pixel-identical.

## 2026-10-20: checking the reaction spares

Parity on the synthetic chat (`-PerfLabScenarios scroll,parity -PerfLabParityRows 60 -PerfLabSynthetic 400`) after the spare containers: 60 of 60 rows equal between legacy and layer chrome, reaction chip hit tests 100 of 100, reply hit tests 30 of 30. Parity binds fresh views, so it covers what a reused container shows only through the scroll scenario's snapshots.

The scroll scenario now also reports `spareReactions`, `spareReactionChips`, `spareReactionPlayable` and `shownReactionPlayable` for the rows in the table after each pass (typically 4 hidden spares holding 13 chips). They cannot yet show that hidden chips stop playing: in lab runs `shownReactionPlayable` is 0 as well, because emoji play only in the key window and the lab's window is not key. That hidden chips do not play rests on a hidden view reporting an empty `visibleRect` and on `ChatReactionsView.isHidden` asking each chip to recheck. The synthetic chat has built-in reactions only, so animated custom-emoji reactions remain unexercised by these changes.

## 2026-10-20: reuse parity

`-PerfLabScenarios reuseparity` checks what a recycled row shows. For each of the first `-PerfLabParityRows` rows it renders the item in a fresh view, then binds two other rows into one pooled view of the same class (one with reactions and one without, so the reactions container goes through its hidden spare and its chips are recycled) before binding the target, and compares the window pixels. A difference is counted only when a second fresh render agrees with the first; otherwise the row is `unstable` (an animation caught mid-frame). The synthetic chat now also puts a paid star reaction first on every eleventh message, so chips move between star and plain reactions, which adds and removes the stars effect layer and the right-click handler.

Synthetic chat, 80 rows: 77 equal, 3 unstable, 0 different, with 159 prior binds; 3 of the compared rows and 13 of the 134 reaction rows used as prior binds carry a star reaction.

## 2026-10-20: hidden spare chips do not play

`-PerfLabIgnoreKeyWindow 1` (DEBUG only) lets `ChatReactionEmojiLayer` treat the lab window as key, so the playability counters mean something. Synthetic chat, three flings at 16,000 pt/s: every pass reports `shownReactionPlayable` 8 and `spareReactionPlayable` 0, with 4 hidden spares holding 13 chips. This replaces the earlier reasoning with a direct measurement.

Negative control: with the `isHidden` recheck disabled, the counters are the same (shown 8, spare 0, 12 spare chips). By the time the pass is measured, scroll-driven visibility updates have already stopped the hidden chips, because a hidden view reports an empty `visibleRect`. The recheck only stops a hidden chip at once instead of at the next visibility update, and the scroll scenario cannot tell the two apart.

## 2026-10-20: AppKit's display walk (no change)

In the synthetic fling profile, `-[NSView _recursiveTickleNeedsDisplay]` takes about 13% of main-thread samples: 216 of 1,681, 159 of them in `convertRect:toView:`. It recurses up to 22 levels deep. A temporary census just before `-[NSWindow displayIfNeeded]` found no view reporting `needsDisplay`. It did find every visible `ChatMessageView` with a layer that stays `needsDisplay` from frame to frame (5,479 of 5,759 dirty rows were already dirty the frame before). That comes from `TableRowView`'s empty `draw(_:)` override together with `layerContentsRedrawPolicy = .never`. Removing the override cleared the flag (5,759 → 269), but an interleaved A/B (two rounds of three flings per side) showed no gain: main thread 14.78% and 14.68% for base against 14.54% and 15.09% with the change. The override stays. 97 row classes draw through `draw(_:in:)`, and a version scoped to rows that don't draw would have nothing to gain. What drives the walk remains unidentified.

`blockWidth` now reads the stored `hasVerticalMonoforum` instead of copying the whole `ChatHistoryEntry` to look at `additionalData.monoforumState`. The entry is only assigned in init, so the result is the same. The profile attributed 7 samples (0.4%) to the copy, too few to show in an A/B.

The census on the synthetic chat shows message rows are already lean: 38 views across 7 `ChatMessageView` rows, out of 567 views in the window. The layer-tree rebuild (`NSViewBuildLayerTreeForDisplay`, about 8%) and the display walk partly cover the whole window. Removing the chat list's stories strip (`StoryListChatListRowView`, 198 views, many of them hidden avatars) for a lab run cut the walk from 184 to 146 samples, the layer-tree rebuild from 138 to 95 and the opaque-region pass from 39 to 16. In that single run, main-thread share did not drop (15.25% → 15.93%), and the strip is outside the chat row, so nothing changed.

## 2026-10-20: reaction count tooltips are memoized

Every chip bind set its tooltip to the count formatted by `Formatter.withSeparator`, an `NSNumberFormatter` call (6 of 55 samples in `fillReactions`). That formatter is a `static let` whose locale is fixed at first use, so a given count always gives the same string. Chips now take it from a memo of counts below 10,000; larger counts are formatted as before. The tooltip text is unchanged.

Interleaved A/B against 398e312ed, synthetic chat with 400 messages, two rounds of three flings: `bindMs_reactions` 35.2 → 31.8 ms per fling (ranges 33.9–35.6 and 30.4–33.2), total bind time 78.7 → 74.8 ms. Main thread 14.89% → 14.72%, within noise.

## 2026-10-20: what is left after the tooltip memo

Synthetic fling profile, main thread. Bind work totals about 9% of samples, and no single remaining item in it exceeds about 1%:
- reactions: container merge 6 samples, chip install 6 (first attach of new chips only), text layer 4, `getInlineLayer` 4
- sender name: `ChatLayerTextNode.update` 7 samples
- message text: 10 samples
- `updateColors`: 22 samples, spread over a dozen colour setters
- the second `updateLayout` that `layout()` runs on about a third of binds: 11 samples
- `RightToolTip`: 8 samples, already skipped when unchanged
- per-chip notification re-registration when a row returns to the window: 14 samples

Most of the remaining cost is AppKit's: the display walk (about 10–13%), the layer-tree rebuild (about 8%), and table row removal and window attach (about 6%). The last two scale partly with the whole window's view count rather than with the chat rows.

Tried: node chips keep their scroll observers registered while their row is out of the window (`updateEmojiListeners` returns early when the container has no window). Interleaved A/B, three rounds: main thread 14.93% → 14.68% on average (14.79–15.07 against 14.61–14.79). The profile shows no saving behind that difference: `AnimatableContentObserver.unregister` takes 11 samples before and 10 after, and `update` 8 before and 17 after. Observers are still dropped and rebuilt on another path, so the main-thread difference is noise. Reverted.

Tried: keep the frame cache filled during `set(item:)` for the `updateLayout` that `rowViewForRow` runs straight after, at the same row width. Interleaved A/B, three rounds: main thread 14.81% → 14.61% on average. In the profile, `ChatRowItem.bubbleFrame` takes 12 samples both before and after, so the bubble frame is not computed twice on that path, and the difference is noise. Reverted. A real version would also have needed a guard against the hundreds of other `set(item:)` callers that do not lay out immediately.

## 2026-10-20: what one view per row costs

A temporary lab flag added N empty views to every message row (synthetic chat, three flings per run, two rounds, interleaved):

| N | main thread |
|---|---|
| 0 | 14.78%, 14.65% |
| 5 | 15.30%, 15.36% |
| 20 | 16.95%, 16.85% |

Each view per row costs about 0.11 points of main thread (about 0.7% of its time) during a fling. The cost is in AppKit's row detach, attach and layer-tree passes, not in bind.

A text message row has 5 views: `ChatMessageView`, `ChatLayerRowView`, `ChatMessageBubbleBackdrop`, the `contentView` wrapper and `ChatLayerMessageTextView`, plus the hidden reactions spare on rows that had reactions once. The backdrop is the obvious candidate for a plain layer, but other views use it as their superview (polls, grouped media, todos, `ChatRowView` itself). It is also the scene's `layerHitBackground` and a coordinate space for the send flights. `contentView` is public API for every row subclass. Neither conversion is worth about 0.1 point. The reactions spare costs about 0.1 point on the rows that hold one and saves 35 ms of bind time per fling, so it stays.

## 2026-10-20: why recycled rows lay out twice

`ChatRowView.layout()` reruns `updateLayout` on recycled rows (10–12 samples per profile) right after `rowViewForRow` has laid them out. A temporary recorder on `needsLayout` showed who marks the row:
- `-[NSView prepareForReuse]` on every dequeue
- the Auto Layout engine, when NSTableView places the row (`NSISEngine` marker replacement, constraint optimisation and pending change notifications from `updateConstraintsForSubtreeIfNeeded`), about 45 times each per pass
- `-[NSTableRowView setFrameSize:]`, 40 times

Clearing the flag after `super.prepareForReuse()` left `layout()` at 10 samples against 12 (main thread 14.81% → 14.71%, noise), because the engine marks the row again. Reverted. Stopping the second pass would mean taking table rows out of NSTableView's constraint engine, which `TableRowView` has a commented-out attempt at (`translatesAutoresizingMaskIntoConstraints`). That would affect every table in the app, not just the chat.

Tried: `ChatRowView` alone answers `translatesAutoresizingMaskIntoConstraints = false`. In the profile, `layout()` fell from 12 to 6 samples and `updateLayout` from 39 to 30, and the chat pane snapshots are identical. But `-[NSISEngine withBehaviors:performModifications:]` rose to 68 samples, and the interleaved A/B over three rounds showed no gain: main thread 14.78% for base against 14.85% for the change. Reverted.

## 2026-10-20: media rows in the synthetic chat

`-PerfLabSyntheticMedia 1` adds media to the synthetic chat:
- a photo on every fifth message, with a caption on every tenth (`LocalFileMediaResource` with no data, so it stays a placeholder with a download control)
- a PDF on every seventh
- a forward header on every thirteenth

Text-only rows had hidden three costs: content creation, content update and forward headers. On this chat a 3 s fling at 16,000 pt/s scrolls 47,996 pt in 626 binds. Main thread is about 21% (14.8% for text only). Per-fling bind steps:

| step | ms |
|---|---|
| reactions | 27.4 |
| reply | 11.5 |
| mediaUpdate | 10.3 |
| mediaCreate | 10.2 |
| name | 9.7 |
| messageText | 7.4 |
| right | 6.6 |
| forward | 6.5 |
| caption | 4.4 |

The total is 99.9 ms. The window's drag-margin pass (`_opaqueFullSizeContentViewRegionWithClipRect`) also rises to 3.1% of samples.

`mediaCreate` is high because `ChatMediaView.set(item:)` discards its content view and creates a new one whenever the message's `stableId` changes, so a recycled media row never reuses its content view. `-PerfLabMediaReuse 1` (DEBUG only; release keeps the current check) reuses the content view whenever its class matches. Interleaved, two rounds: main thread 20.62% and 20.75% against 19.81% and 19.83%, with hitches 4 and 6 against 3 and 4.

This is not enabled. Reuse parity on the media chat has 61 equal, 0 different and 19 unstable rows both with and without reuse, and the unstable rows are the media rows: their spinner animates, so the pixel check does not cover them. The synthetic photos never load, so loaded images, autoplaying video, spoilers and download progress are untested. `ChatInteractiveContentView.update` already handles a message change (it clears the image at once when the `stableId` differs). The other content classes (file, audio, voice, video message, sticker, dice, map) would each need checking, and real media chats to try it in.

Correction, same day: the gain above came from placeholder photos. The synthetic photos now get real JPEG data (striped, a different colour per message), written to the media box when the lab opens the chat, so they render as loaded images. With loaded photos, interleaved, two rounds:
- `-PerfLabMediaReuse 1` (all content classes): main thread 19.11% and 19.20% against 18.98% and 18.94%, noise.
- Reuse in release code for still photos only (`ChatInteractiveContentView` with `TelegramMediaImage`, no video), three rounds: `mediaCreate` 11.0 → 8.3 ms, but `mediaUpdate` 10.7 → 11.9 ms and total bind time unchanged. Main thread 18.99% → 19.11%.

Rebuilding the download-progress spinner made recreation expensive. A loaded photo is cheap to recreate. Reverted.

With loaded photos, reuse parity on the media chat is meaningful: 116 equal, 0 different and 4 unstable of 120 rows, both with and without reuse. The scenario keeps one pooled view per row class, so each photo row after the first is drawn into a view that last showed another photo.

## 2026-10-20: main-thread text rasterization

`CA::Layer::display_if_needed` takes about 10% of main-thread samples on both synthetic chats. The biggest part is glyph rasterization when the display list is replayed at commit: `CGDisplayListDrawInContextDelegate > CGContextDelegateDrawGlyphs > ripc_DrawGlyphs`, 60 of 1,699 samples. Recording in `TextViewLayer.draw(in:)` adds another 21.

Tried: `drawsAsynchronously` on `ChatLayerTextNode.drawingLayer`, behind a lab flag. Interleaved, two rounds: main thread 14.76% and 14.83% against 14.80% and 14.82%, while CPU rose from 0.16–0.17 to 0.18 cores. Snapshots differ inside the chat pane (up to x = 745), so text renders differently. Reverted. (`ScrollView` and `TGClipView` have commented-out `drawsAsynchronously = System.drawAsync` from an earlier attempt.)

A temporary counter in `TextViewLayer.draw(in:)` showed 3,332 text draws for 786 binds per scroll pass, 4.2 per bind: sender name, message text, reply name and text, and timestamp. No layer redrew the layout it had already drawn at the same size, so there are no redundant redraws.

Two facts about the synthetic chat behind these counts:
- Each pass scrolls down and back up, so every row is bound twice.
- The author formula `(index * 7 + index / 3) % 11` only produces users 0, 3 and 7, so only Alice, Dana and Hana write messages (134, 133 and 89). Consecutive messages from one author are therefore more common than in a real group. The formula is left unchanged so earlier measurements stay comparable.

## 2026-10-20: window drag margins

`-[NSWindow(Regions) _resetDragMargins]` takes 3.3% of main-thread samples on the text chat and 5.3% on the media chat. Two thirds of that is the walk over opaque views (`_regionForOpaqueDescendants`), and the rest is the resize and titlebar regions. A temporary lab-only replacement for `_setNeedsToResetDragMargins:` (one 3 s pass on the media chat) counted 97 invalidations:
- 79 from NSTableView adding row views (`_addRowViewForVisibleRow`)
- 10 from `ChatFileContentView` adding its status view
- 6 from the reactions spare being unhidden
- 2 others

A standalone AppKit check in a `.fullSizeContentView` window with a transparent titlebar:
- adding a view invalidates the margins only when the view lands under the titlebar, whatever its `isOpaque` or `mouseDownCanMoveWindow`
- removing a view never invalidates them

Chat rows scroll in under the transparent titlebar and header, so this cost comes from the window design. Nothing in the row view avoids it. No change.

Upper bound check: a temporary lab-only switch replaced `_setNeedsToResetDragMargins:` with a no-op. The profile confirmed `_resetDragMargins` was gone, yet in four interleaved rounds on the media chat (16k pt/s, 3 runs each) main thread was 18.88% with the reset and 19.12% without. Moving rows out from under the titlebar would not buy a measurable gain, so the window design stays.

## 2026-10-20: tracking area updates

`-[_NSTrackingAreaAKManager displayCycleUpdateStructuralRegions]` takes 7.9% of main-thread samples on the media chat at 16k pt/s. Almost all of it is `-[_NSTrackingAreaAKViewHelper updateTrackingAreasWithInvalidCursorRects:]` walking subviews 13 to 21 levels deep, 117 of 163 samples under one `NSScrollView`. Upper bound with a temporary lab-only no-op for that method (breaks hover, measurement only), four interleaved rounds: 19.01/18.78/18.77/18.81% main thread with the walk and 17.59/17.98/17.95/24.62% without, so about one point once the outlier round is set aside. This is the one AppKit cost left whose removal shows up in main%. Next step: find which views keep tracking areas dirty during a scroll and keep them clean.

Attribution (temporary lab-only timer around `-[NSScrollView _updateTrackingAreasWithInvalidCursorRects:]`, media chat, one 3 s pass at 16k pt/s): every frame walks every scroll view in the window, not only the one that scrolls. Per pass, about 1,436 calls each:
- stories strip `ScrollView` in the chat list, 201 descendants: 43.8 ms
- chat `TableView`, 38 to 46 descendants: about 40 ms in total
- chat list `TableView`, 58 descendants: 17.5 ms
- folder sidebar `TableView`, 29 descendants: 8.5 ms

The cost grows with the total descendant count, hidden ones included (the strip already hides items outside its visible range). Split across that upper bound of about one main-thread point, the strip is worth about 0.4 points, the chat table 0.4, the chat list 0.15 and the sidebar 0.08. Each is below the run-to-run noise, which matches the earlier result where removing the strip showed no main% drop. Taking hidden strip items out of the hierarchy would touch the stories collapse animations for a gain the lab cannot resolve. No change.

A tracking-area census on the same window: 598 views and 276 tracking areas, of which only 25 are inside chat rows (`AvatarControl` 73, `TextView` 48, `ComponentView` and `ItemView` 29 each, all in the chat list and strip).
