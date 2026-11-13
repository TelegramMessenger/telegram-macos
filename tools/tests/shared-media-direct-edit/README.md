# Shared-media direct Edit

This change depends on the shared-media edit-availability fix. Apply that prerequisite once, then apply only the direct-Edit delta. Do not reapply the cumulative diff from the original upstream base.

Run on macOS with Xcode selected and Python 3:

```sh
python3 -I tools/tests/shared-media-direct-edit/run.py
```

The default runs the current fixed source only and cleans all logs and temporary output automatically. To retain a fixed/baseline comparison:

```sh
python3 -I tools/tests/shared-media-direct-edit/run.py --baseline-source /tmp/availability-only-PeerMediaController.swift --baseline-story-source /tmp/availability-only-StoryMediaController.swift --output /tmp/shared-media-direct-edit-results
```

`--baseline-source` points to the real availability-only production file or a preserved earlier direct-Edit controller when checking a correction. Use `--baseline-story-source` for its matching preserved story controller. After a prerequisite has been committed, use `--baseline-ref <availability-commit>` instead. The runner refuses a baseline without the capability contract. `--source-root` can target a combined working tree. An explicit output directory must not exist and must not be a symlink.

The runner strips inherited `GIT_*` variables, invokes native `swiftc -j 2`, and uses an automatically cleaned temporary directory for all generated Swift, executables and module caches. It downloads no dependencies, builds no app, and uses no GUI, accounts, preferences or network. It retains only compile/test logs and source hashes in the explicit output directory.

## Production source exercised

The test harness extracts the real availability/menu contract and direct-action discriminator, complete toolbar setup, title update, resize/theme refresh, selection update, controller lookup and tab activation from `PeerMediaController`. It also extracts the editable superclass state/update methods, story menu callback and UI-transition subscriber, collection enum and `Control.accessibilityPerformPress`. With `--baseline-source`, the story controller is read from `HEAD` unless `--baseline-story-source` is provided. `HEAD` may already include the direct-Edit callback, so provide the matching preserved story file for a faithful comparison. With `--baseline-ref`, both baseline controllers are read from that ref unless the story source is explicitly overridden. No parallel implementation of the direct-Edit decision is provided by the harness. The baseline and fixed sources compile and execute the same assertions; compiler errors are harness failures, never valid negative controls.

Twenty-three native XCTest cases check supported Edit-only controls, direct invocation without opening a menu, Done and Some presentation, localized accessibility labels, genuine story multi-action menus, non-Edit single actions, separators, disabled/handlerless/submenu actions, unsupported tabs, theme refresh, resize, tab transitions, asynchronous story-menu updates, accessibility activation and click-time menu revalidation. The child-supplied handler must be invoked, not replaced with a guessed action.

## Boundary doubles and limits

Controls, image assets, text metrics, glass/layout, tables, signals and navigation are deterministic UI boundary doubles. They record which themed image, label, handler, visibility, size and menu the extracted production methods request. The superclass theme callback forwards the toolbar refresh as production does; table scroll completions can be queued. The story menu body and parent selection route are extracted from production. The image boundary records `highlight(color:)` and verifies the pencil receives the toolbar `theme.colors.text` token after both light/dark palette changes and Done transitions, rather than retaining the accent-colored asset. This verifies the production tint request, not rendered pixels.

These tests are not a full PeerInfoUI build and do not establish actual image rendering, AppKit/VoiceOver hit testing, animation timing, asynchronous story permissions or database behavior. Manual acceptance should verify themed pencil/Done transitions at narrow and wide sizes, Edit activation with VoiceOver, real story/gift multi-action menus remaining menus, and no Edit in Saved/Polls/Groups. Escape behavior is outside this change.
