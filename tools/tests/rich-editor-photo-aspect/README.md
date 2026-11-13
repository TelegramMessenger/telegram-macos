# Rich editor photo aspect

Run on macOS with the selected Xcode toolchain and Python 3:

```sh
python3 -I tools/tests/rich-editor-photo-aspect/run.py
```

The runner executes the current source and an upstream negative control at `246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5`. Use `--source-root` for another source tree, `--baseline-ref` for another Git revision, and `--output /tmp/rich-photo-results` to retain results. An explicit output directory must be new and must not be a symlink. The default removes all generated sources, binaries, module caches and logs. Swift-driver `TMPDIR` is contained in the same owned temporary directory. Inherited `GIT_*` variables are stripped; native compilation uses two jobs. No dependencies are downloaded and no application, account, network, preferences or database are used.

## Production path

The image picker inserts a hosted `image` media block, not the older bitmap-only `ImageBlockBox`. The provider initially creates an aspect-sized photo node. `syncMediaBlockViews` then caps its frame height at `CanvasMetrics.maxMediaHeight` while retaining the width. The ordinary chat node's layout changes its image frame but does not recompute its previously supplied transform, stretching that old bitmap into a different aspect ratio.

The editor-only photo subclass refreshes the existing `update(size:)` transform when its positive frame size changes. That method already uses the source dimensions, aspect fitting and the existing blurred-background mode. Repeated layouts and origin-only changes do not repeat the transform. Other media factories, the ordinary chat photo class, the media payload, captions and canvas height cap are unchanged.

## Extracted source and boundaries

The harness compiles the complete production editor media factory and optional editor-only subclass, the real base view `layout`, photo `updateLayout` and `update(size:)`, blur-background predicate, existing aspect-fit/fill helpers, hosted-media holder, full canvas `syncMediaBlockViews`, and reserved-height accessor/constant. Baseline extraction omits the new subclass when absent; it does not insert a replacement implementation into upstream.

Native offscreen `NSView` frames, bounds and overlay hierarchy are used. Media/account models, signals, theme, image transformation sink and unrelated canvas behavior are small doubles. Initial full media binding is a boundary double that invokes the extracted size-transform method; it does not execute Telegram's full asynchronous image subscription/decoder. Assertions check requested `TransformImageArguments` and native view geometry, not rendered pixels or resource loading. No window is presented and no GUI input or live app is driven.

Twelve XCTest cases cover landscape, portrait, square and panorama sources; three canvas widths; capped and uncapped heights; repeated layout and origin movement; explicit frame resizing; pre-media/zero-size layout; native canvas pooling, selection-overlay alignment and removal; payload identity/spoiler preservation; unchanged nonphoto nodes and the ordinary chat photo path. The frame-resize case checks a node whose frame changes, not an assertion that the canvas recreates pooled nodes on every document-width change.

All 12 cases pass with the fix. The upstream control compiles and executes the same 12 cases: 7 cases fail with 34 expected assertions, while 5 control cases pass. A compiler/extraction error is a harness failure, never a successful reproduction.

Manual acceptance should use the original reported photo in the editor, compare its proportions with the original, and check a tall image and a smaller window. The user's screenshot alone does not establish the original input dimensions. Sending is not required to verify this preview-only change; no outgoing serialization or sent-message renderer is modified.
