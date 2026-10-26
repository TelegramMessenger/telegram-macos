# Context menu topic submenus

Right-clicking a message builds the Forward submenu for up to 15 chats. For every
forum chat it also built a submenu with up to 100 topics. `ContextMenu.addItem`
removed every native `NSMenu` item and inserted all stored items again on each
call, so a submenu of N topics caused N × (N + 1) / 2 native insertions on the
main thread.

The fix appends one native item per `addItem` call while still updating the
observed `_items` list, and builds forum topic submenus only when they are
presented through `ContextMenu.itemsProvider`. Topics are still loaded when the
menu opens, so the submenu arrow appears exactly as before.

Run from the repository root on macOS:

```sh
python3 tools/tests/context-menu-topic-submenus/run.py --revision c0785dc8 --expect-bug
python3 tools/tests/context-menu-topic-submenus/run.py
python3 tools/tests/context-menu-topic-submenus/run.py --revision c0785dc8 --expect-bug --benchmark --configuration release
python3 tools/tests/context-menu-topic-submenus/run.py --benchmark --configuration release
```

The runner exports `packages/TGUIKit` from the given revision, or copies the
working tree, into a scratch package. Dependency paths point back to this
checkout. Only `TGUIKitTestBootstrap.swift` and `ContextMenuBuildTests.swift` are
compiled as tests; the fixture uses public `TGUIKit` API that exists in both
revisions. The runner prints SHA256 hashes of `ContextMenu.swift` and
`AppMenuController.swift` so each result can be tied to its source.

`testTopicSubmenuInsertions` counts `NSMenu.didAddItemNotification` while 1, 25,
100 and 400 items are added and checks that native and stored items keep the same
order. With `--expect-bug` it expects the quadratic count:

| Items | Before | After |
|---:|---:|---:|
| 1 | 1 | 1 |
| 25 | 325 | 25 |
| 100 | 5,050 | 100 |
| 400 | 80,200 | 400 |

`--benchmark` times building submenus through `addItem`, one warm-up and nine
measured batches per scenario, each inside an autorelease pool. Medians from a
Release build, two runs of the baseline and three of the fix, alternating order:

| Scenario | Before | After |
|---|---:|---:|
| 1 forum, 100 topics | 1.95 / 1.94 ms | 0.17 / 0.16 / 0.17 ms |
| 15 forums, 100 topics each | 29.2 / 28.7 ms | 2.48 / 2.48 / 2.51 ms |
| 1 forum, 1,000 topics | 175 / 170 ms | 3.25 / 3.23 / 3.26 ms |
| 100 forums, 1,000 topics each | 16.92 / 16.99 s | 0.325 / 0.322 / 0.322 s |

Environment: Mac16,5 (Apple M4 Max, 36 GiB), macOS 27.0 (26A428), Xcode 27.0
(27A266a), Swift 6.4.

The benchmark measures only native menu bookkeeping for plain items. In the
application each topic item also prepares an avatar and premium state, and the
Forward menu loads at most 100 topics for at most 15 chats. With the fix, none of
those topic items are created when the context menu opens; they are created for
one chat when its submenu is presented. The 100 × 1,000 scenario is a stress case
beyond what the application loads. Absolute numbers depend on the machine; there
is no timing threshold.
