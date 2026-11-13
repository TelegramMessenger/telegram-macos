# Archived stickers empty-state regression

## Run

From the repository root, with Python 3.9+ and a selected full Xcode installation containing Swift and XCTest:

```sh
python3 -I tools/tests/archived-stickers-empty-state/run.py
python3 -I tools/tests/archived-stickers-empty-state/run.py --baseline c64a3ea7
```

`--root /path/to/checkout` selects another source checkout. The default source root is determined from the runner's location, not the current directory. Baseline reads the locally available commit `c64a3ea77750fa753da0913cf26610df9b237640` with `git show` and never changes refs or checks out files.

The default temporary output autocleans. `--output /path/to/new-directory` retains source, compile/test logs, SHA-256 hashes and JSON results; its parent must exist and output must not exist, even as a symlink. Module caches/executables autoclean even with explicit output. Do not commit generated evidence. The runner requires `python3 -I`, strips inherited `GIT_*` environment variables, and discovers XCTest with `xcrun`. No dependencies are built or downloaded.

Exit 0 means all requested expectations match, including expected negative-control failures. Unexpected assertions return 1. Setup/extraction/compilation errors return 2 and do not count as regression detection.

## Production source under test

The runner extracts the complete `archivedStickerPacksControllerEntries` function, its state struct, the real `ItemListStickerPackItemEditing` value type and the Equatable `bestGeneralViewType` helper. The description is read from that revision's English strings file. The function body is neither copied into the template nor rewritten for the test.

Boundary stand-ins model item IDs/namespaces, collection views, sticker metadata/top items, row enum values and localized description access. They hold data only. Expected row arrays are a test oracle over explicitly expected remaining packs, not a replacement filtering implementation. The runner also checks that the controller still maps `.loading` to its existing empty-row text and publishes `updatedPacks(packs)`; these are source checks, not server or row-rendering tests.

## Assertions and negative control

One real XCTest method runs 21 labelled input scenarios with one assertion per scenario, comparing full output entries and unchanged input packs:

- Nil/loading and already-empty archive states.
- One or three packs, ordering, corner styles, count/top-item data.
- Missing collection key, wrong view type, missing namespace and cross-namespace IDs.
- Partial/complete restores and a three-step restore sequence.
- Editing/removing state, disabled rows and absent top items.

Fixed source passes 21/21. Original baseline compiles and fails exactly these three assertions, while 18 pass:

- `last pack restored becomes empty`
- `all packs restored become empty`
- `final restore in sequence`

The runner checks the exact failure-label list, assertion/scenario counts, XCTest failure count and exit code. A compiler failure is never accepted as a negative control.

This is offline source-extracted Swift/XCTest, not a live archive restore, account/server test, AppKit row rendering or GUI acceptance. No app build/launch, profile, Keychain, network or payment operation occurs. The unique-anchor/brace extractor is intentionally small rather than a general Swift parser; source changes may require reviewed fixture updates.
