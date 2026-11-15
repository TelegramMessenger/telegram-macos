# Preview album target regression

Run on macOS with the Xcode command-line tools and Python 3.9 or later, from the repository root:

```sh
python3 -I tools/tests/preview-album-target/run.py --output-dir /absolute/path/fixed
python3 -I tools/tests/preview-album-target/run.py --source-revision 34ac52b8df11168ad09b6573f0e114c5a5d2a25a --scenario stale --output-dir /absolute/path/stale-baseline
python3 -I tools/tests/preview-album-target/run.py --source-revision c64a3ea7 --scenario original --output-dir /absolute/path/original-baseline
```

The first command must pass. The second must compile the prior PR head successfully and fail the stale-album behavior assertions, not compilation. The third preserves the original pre-PR negative control for wrong second/third album targets and reorder results. `--output-dir /absolute/path` retains the extracted `main.swift`, binary, compiler cache, `compile.log`, and per-scenario output, including failures; the directory must not already exist. `--extract-only --output-dir /absolute/path` generates the fixture without invoking Swift. Compilation uses one `swiftc -j1` invocation; selected scenarios run serially from that binary. In sparse checkouts, source files absent from the working tree are read from `HEAD`.

The runner compiles against Foundation and CoreGraphics and extracts the production entry builder, grouped-row construction, URL action bindings, rendering-preview lookup, row-drop mutations, global deletion, the complete controller reorder closure, table-reorder adapter, and array/grouped-layout movement methods. `AlbumTargetTests.swift.in` supplies inert model/UI boundary types; no production mapping algorithm is copied into the test. It does not import the full `PreviewSenderUI` target, which currently has no native test target and depends on the app's native frameworks.

Coverage includes empty/single/exact-ten boundaries; 11, 12, 20, 21, 22 and 30 attachments; edit/draw/delete targets in later albums; edited-data and rendering-preview identity; forward/backward album-local to global reorder; immediate row state and rebuilt rows; deletion rechunking; replaced attachment URLs; unchanged spoiler flags with `payAmount: nil`; and ungrouped media/file order.

Additional scenarios retain the original assertions and then check:

- `original`: unchanged first-album and table-index moves in both directions and no-op drops.
- `stale`: deletion before the dragged/target items in the first or second album, including multiple deletions, while reusing the still-visible row; current URL order, immediate edit identity, and repeated reverse moves before refresh.
- `missing`: deleted dragged or target URLs in both directions, replaced endpoints, and an empty controller URL list; no controller mutation, reorder analytics, or transition-animation suppression for rejected drops.
- `boundary-forward` / `boundary-backward`: a stale two-item second album after deletion in the first album, in both directions at the controller array boundary. On the prior PR head these can trap at invalid insert/remove indices, so they run in separate processes; the non-crashing `stale` scenario is the behavioral negative control.

Boundary limits: this is an exact-source logic regression, not a complete package build or UI test. Media, rendering previews and edit metadata are represented by numbered values. Group layout hit testing uses synthetic non-overlapping rectangles. Actual layout measurement, AppKit event routing, asynchronous table transitions, editor export and payment flows are not exercised. Full-app compilation and user acceptance remain separate.

## Manual acceptance

1. Attach 12 distinct images visibly numbered 1 through 12 and enable grouped preview.
2. In the second album, edit image 11. The editor must show 11, not 1. Cancel; verify drawing and deletion also target 11.
3. Reopen with all 12 images, reorder 11 and 12 inside the second album, then immediately edit each. The first album must remain 1 through 10; the selected image and existing edits must still correspond.
4. Repeat with 22 images to check both the second album's last image (20) and the third album's first image (21). After deleting a boundary image, verify the newly grouped previews still edit the visible image.
5. With 12 images, delete an image in the first album, then drop 11 onto 12 in the still-visible second album before it refreshes. Only those surviving images must move, without a crash. Repeat in the reverse direction and with 22 images. A drop whose dragged or target attachment has already been deleted must not reorder a different attachment.

These steps are for the user to perform in an isolated combined test build, not an automated live-account operation.
