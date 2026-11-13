# Preview album target regression

Run on macOS with the Xcode command-line tools and Python 3.9 or later, from the repository root:

```sh
python3 -I tools/tests/preview-album-target/run.py
python3 -I tools/tests/preview-album-target/run.py --source-revision c64a3ea7
```

The first command must pass. The second runs the same assertions against the pre-fix production source and must fail with wrong second/third album targets and reorder results. `--output-dir /absolute/path` retains the extracted `main.swift`, binary and compiler cache there; the directory must not already exist. `--extract-only --output-dir /absolute/path` generates the fixture without invoking Swift.

The runner compiles against Foundation and CoreGraphics and extracts the production entry builder, grouped-row construction, URL action bindings, rendering-preview lookup, row-drop mutations, global delete/reorder mutations, and array/grouped-layout movement methods. `AlbumTargetTests.swift.in` supplies inert model/UI boundary types; no production mapping algorithm is copied into the test. It does not import the full `PreviewSenderUI` target, which currently has no native test target and depends on the app's native frameworks.

Coverage includes empty/single/exact-ten boundaries; 11, 12, 20, 21, 22 and 30 attachments; edit/draw/delete targets in later albums; edited-data and rendering-preview identity; forward/backward album-local to global reorder; immediate row state and rebuilt rows; deletion rechunking; replaced attachment URLs; unchanged spoiler flags with `payAmount: nil`; and ungrouped media/file order.

Boundary limits: this is an exact-source logic regression, not a complete package build or UI test. Media, rendering previews and edit metadata are represented by numbered values. Group layout hit testing uses synthetic non-overlapping rectangles. Actual layout measurement, AppKit event routing, asynchronous table transitions, editor export and payment flows are not exercised. Full-app compilation and user acceptance remain separate.

## Manual acceptance

1. Attach 12 distinct images visibly numbered 1 through 12 and enable grouped preview.
2. In the second album, edit image 11. The editor must show 11, not 1. Cancel; verify drawing and deletion also target 11.
3. Reopen with all 12 images, reorder 11 and 12 inside the second album, then immediately edit each. The first album must remain 1 through 10; the selected image and existing edits must still correspond.
4. Repeat with 22 images to check both the second album's last image (20) and the third album's first image (21). After deleting a boundary image, verify the newly grouped previews still edit the visible image.

These steps are for the user to perform in an isolated combined test build, not an automated live-account operation.
