# Native integration verification and UI captures

Tested on macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), Telegram 13.1.0 (283357), arm64 Debug.

The patched client integrated the production changes from PRs #83, #84 and #85 at `6bb2e154`. Local SDK, isolated-profile and validation-hook changes are excluded from the feature PRs. The baseline used `deffa9c1` versions of ChatRowItem, ChatReactionsView and ChatMessageMenuItems.

## Method

Two harmless 640x480 JPEG photos were uploaded as one album to the test account's Saved Messages. A local validation hook requested the loaded album row's production `menuItems(in: .zero)`, recorded the generated titles and invoked the matching ContextMenuItem handler. The native folder picker was completed through the UI. The selected-photos case first selected both real message IDs through ChatInteraction.

This exercises production menu generation, actual Postbox messages, MediaBox resources, folder selection and filesystem writes. It bypasses physical right-click dispatch: the computer-use tool returned AXError.failure for coordinate clicks on the drawn message. No screenshot was taken during the original export pass. The later Before/After capture pass is described below.

## Results

- Baseline: two-photo album; Save As exists, Save All Photos is absent (`before-menu.json`).
- Patched album: Save All Photos exists even at an individual tile point (`after-album-menu.json`). One folder picker; native UI reported Saved; two distinct, decodable 640x480 JPEG files were written (`saved-album.json`).
- Patched selection: Save Selected Photos exists with two messages selected (`after-selection-menu.json`). Saving to the same directory created two files suffixed (1). The original files retained their SHA-256 hashes, and each new copy matched its corresponding original (`saved-selection.json`).
- Targeted Swift checks: 35/35 pass, including delayed remote resources, cancellation, failed downloads, protections, ordering, duplicates and filename collisions. The individual-album-tile regression failed before the follow-up fix (34/35).

The native photos were local by the time saving ran. Delayed downloads and their failures are covered by the targeted production-saver tests with resource collaborators, not by a forced network failure in this native run.

## Before/After capture pass

`before-album-menu.png` and `after-album-menu.png` are genuine crops of the running authenticated client, using the same two-photo album and window size. Before uses `df90450c` menu source. After uses the photo sources from `d492dca2`; `capture-source.json` records matching file hashes. Both complete Debug arm64 client builds succeeded. Other independent UI fixes and local SDK/profile adjustments are shared by the two builds.

A local diagnostic button requests the loaded row's production `menuItems(in: .zero)` and presents those exact ContextMenuItem objects through Telegram's supported native system-menu renderer. The tool could not address drawn messages or reliably select transient menu items. The button, its presentation adapter and other local validation changes are excluded from this PR. These captures establish the generated menu commands and their visible result; they do not establish physical right-click dispatch or the custom glass-menu renderer. Private chats, account identity, unrelated Saved Messages content and the diagnostic button are cropped out. No UI is reconstructed or composited.

The original real export checks above remain the filesystem evidence: both Save All Photos and Save Selected Photos saved two valid JPEGs, and a repeat save preserved existing files. This later capture pass does not claim a new successful menu-selection/export run.

## Selected-photo right-click regression

The selection-mode guard previously stopped the row before its menu dispatcher. The fix allows a multi-selection context menu only on a selected photo row, preserving the previous suppression for a single selection, text rows and unselected photos.

The production `ChatRowView.rightMouseDown` override is extracted into an AppKit fixture, with a superclass dispatch recorder and controlled row/selection collaborators. `dispatch-regression.json` records 39/41 checks before the guard fix and 41/41 after it; the two previous failures are selected album and standalone-photo dispatch. The same test run still exercises the production saver/batch writer, real SwiftSignalKit and filesystem operations.

Run from a full dependency checkout:

```sh
python3 tools/tests/save-photos/run.py
```

A separate sparse source checkout can pass `--dependency-root /path/to/full-checkout`.
