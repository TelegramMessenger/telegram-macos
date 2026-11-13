# Chat-list bottom clearance regression tests

Run on macOS with the installed Xcode command-line tools:

```sh
python3 -I tools/tests/chat-list-bottom-clearance/run.py
```

The runner uses `swiftc -j2` and system AppKit. It does not resolve packages, fetch dependencies, build Telegram, create windows, open applications, synthesize input, or access an account.

## Negative control

```sh
python3 -I tools/tests/chat-list-bottom-clearance/run.py \
  --source-revision 246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5
```

All production declarations come from that existing local commit. To reproduce the previously tested update-button-only fix, override just the peer-list file with its exact preserved copy while using the same original commit for the other sources:

```sh
python3 -I tools/tests/chat-list-bottom-clearance/run.py \
  --source-revision 246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5 \
  --peer-list-source /absolute/path/to/preserved/PeersListController.swift
```

The preserved pre-correction file has SHA256 `fc404cabd8976377ea7dfa4e441e76699bbbf1754839dd751eebf6872b838545`. Its real bodies are compiled with the current test fixture; the runner does not transform or simulate the old implementation. Both controls must **compile successfully and fail behavioral assertions**, not fail because a new symbol is missing. Exit codes are 0 for passing tests, 1 for behavioral failures, and 2 for fixture/compiler/runner failures.

Recorded on macOS 27.0 with Apple Swift 6.4:

| Source | Test cases | Scenarios | Assertions | Failed assertions |
| --- | ---: | ---: | ---: | ---: |
| Corrected working tree | 20 | 164 | 2,075 | 0 |
| Previous update-button-only U02 fix | 20 | 164 | 2,075 | 217 |
| Original commit above | 20 | 164 | 2,075 | 402 |

A **test case** is a named `test` block. A **scenario** is one parameter combination or lifecycle sequence inside a case. An **assertion** is an individual `expect` evaluation; these counts are not interchangeable.

## Production coverage

The runner extracts complete declarations without rewriting their bodies:

- `MainViewController.updateChatListBottomOverlays` and `updateButtonBottomY` supply the active, visible update-button rectangle through real `NSView.convert` calls.
- `TabBarController` inset propagation/visibility and `FloatingTabBarLayout` feed the original tabbar geometry into the navigation stack.
- `ViewController`/`NavigationViewController`/`PeersListController` inset propagation, navigation-change notification, and controller enumeration exercise All Chats and a subsequently pushed folder. A source guard verifies that `ChatListController` inherits `PeersListController`.
- `PeerListContainerView.contentBottomInset`, `updateBottomControls`, `updateScroller`, and `downloadsFrame` run the actual feature layout and arrow creation/removal, including stacked controls and collapsed-layout clipping.
- `ChatNavigationScroller.init` supplies its real 64-point control frame and 40-point glass size. `ImageButton.hitTest` and its extracted glass-layout block run against native offscreen views to distinguish the clickable control from the smaller visible glass. The final row must clear both.
- `ScrollView.documentSize`, `TableView.scroll(to:)`, `TableView.isAtBottom`, and `TGClipView`'s scroll/update-bounds methods run against native `NSScrollView`, `NSClipView`, and `NSTableView`. Native `constrainBoundsRect` establishes the nonelastic maximum scroll; native row rectangles are converted back into the list to assert clearance. Programmatic `.down(false)` and last-row `.bottom(...)` targets use the extracted TGUIKit implementation, not a copied formula.

The fixture supplies inert controller/account boundaries, basic state/control types, row storage, and non-rendering callbacks. Glass visuals are plain native views; icons, Liquid Glass rendering and animation are not loaded. The removal boundary is synchronous even when a scenario passes the animated flag; the real `updateScroller` decision/removal callback is executed, not the production fade timing. It is **not the complete ChatListUI or TGUIKit target**. Table row content, signal-driven chat loading, appearance/rendering, animated transitions, live wheel input, and Settings/search are outside this fixture. Production callbacks are invoked directly; their event wiring is inspected in source rather than exercised through the application. Manual acceptance in the full client remains necessary.

## Scenarios

The 20 cases cover:

1. Native maximum scroll at three widths, three heights, three update-button heights, and dual/single layouts.
2. Programmatic bottom scroll with short and long lists.
3. All combinations of tabbar/update visibility.
4. Repeated layout, hide/show, resize, and tabbar visibility changes.
5. Translated parent coordinates and existing download/undo stacks; scroll-up control placement is preserved.
6. Collapsed layouts, including the raised update button when connection status is visible, without double-counting clearance.
7. Short, near-viewport, and long lists at different row heights.
8. Expanded/collapsed/expanded transitions on the same list.
9. Nonzero parent insets.
10. Last-row-targeted bottom scrolling through TGUIKit.
11. Inactive tabs, detached views, unloaded controllers, and horizontally nonintersecting overlays.
12. Folder push and return to All Chats.
13. Direct overlay geometry, offscreen and partly intersecting rectangles, preservation of other inset edges, and reset when geometry disappears.
14. Arrow clearance at multiple widths/heights with and without the update button, using both native maximum and programmatic bottom scrolling.
15. Arrow creation by scroll position/filter state, removal at top or in Contacts, repeated updates, and immediate restoration of non-arrow clearance without an unrelated layout call.
16. Collapsed arrows with/without update/connection controls; only the arrow's intersection with the already shortened viewport is reserved.
17. Arrow dimension changes, hide/detach/reattach, translated coordinates, resize, and update/tabbar visibility changes.
18. Arrow clearance for All Chats and a pushed folder's last-row-targeted scroll.
19. Short/long lists, varying row heights, and expanded/collapsed/expanded transitions with an arrow.
20. Repeated threshold crossings, preserving the current mid-list scroll position as the arrow appears/disappears.

At the long-list maximum, the last row must be fully above visible bottom overlays and the scroll-up arrow's **entire hit frame**, not just its smaller glass surface, with the existing 12-point control gap. Tests also ensure expanded layouts keep the full drawing viewport, the parent/tabbar base does not accumulate overlay height, and collapsed layouts retain their existing shortened viewport while adding only arrow clearance within that viewport.

## Temporary files and evidence

Default runs create one owned directory under `TMPDIR`, put the generated Swift source, executable, logs, Swift/Clang caches and child `TMPDIR` inside it, print a JSON result, and remove the directory on success or failure. Python isolated mode is required. Inherited `GIT_*` variables are stripped before subprocesses; fixed and both baseline runs were checked with poisoned Git environment variables. No files are written into the checkout during execution.

To retain a run, explicitly choose a **new directory whose parent exists and whose path has no symlink components**:

```sh
python3 -I tools/tests/chat-list-bottom-clearance/run.py --output /absolute/new-run-directory
```

Existing directories, direct/dangling symlinks, and symlinked parent components are rejected. Explicit output preserves the owned temporary/cache tree for inspection; remove it when no longer needed. The JSON records full source hashes, extracted declaration hashes, fixture/runner/generated-source hashes, compiler identity, compilation status, scenario counts, and behavioral failures.
