# Shared-media Escape selection regression

Run from any directory using Python isolation and a Swift compiler on `PATH`.

```sh
python3 -I tools/tests/shared-media-escape-selection/run.py
python3 -I tools/tests/shared-media-escape-selection/run.py --revision 246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5
```

The original revision must compile successfully and then fail behavioral assertions. A compiler/extraction failure is not a reproduced regression. Exit status is `0` for passing assertions, `1` for behavioral failure and `2` for setup or compilation failure. `--revision` reads production sources with `git show`; it does not check out files or change refs. Tests always use the runner and template next to this README.

By default, the runner creates and removes an owned temporary directory. `swiftc -j2`, compiler module caches, `TMPDIR`, `TMP`, `TEMP` and `XDG_CACHE_HOME` are directed inside it. To retain generated Swift, compiler/test logs and a JSON extraction/hash manifest, pass `--output /absolute/path/to/new-directory`. The parent must already exist; the output must be new, and neither it nor any ancestor may be a symlink. No Swift package, app build, network request, AppKit window or account data is required.

## Production code executed

The runner extracts real bodies rather than reimplementing the cancellation or navigation condition in the fixture. Only declaration access modifiers are removed to compile the extracted members against internal doubles. The optional `escapeSelection()` extraction is empty on the original revision, where neither production caller refers to it.

- `Window`: priority/handler types, handler registration/removal, dead-owner cleanup, responder selection and the complete `sendEvent` body.
- `MajorNavigationController`: appearance/disappearance registration, `escapeKeyAction`, `back` and `invokeBack`, including lock, return-status and navigation-back veto decisions.
- `PeerInfoController`: the full Escape override, including existing profile-edit priority and the visible-media route.
- `PeerMediaController`: the full Escape override, selection-only handler when present, state observer, `update(with:)`, `changeState()`, visible-block lifecycle method and selection-transition branch from `notify`.
- `StoryMediaController`: Escape, selection toggle, state update and the context-menu `toggleSelected` closure.
- `EditableViewController`: state observer, update and state toggle; `ViewController`: default Escape rejection.
- `InputDataController`: its actual Escape implementation, demonstrating why routing every media child would be wrong.
- `SearchView`: Escape registration and `changeResponder`, preserving the focused search's higher-priority handler.

`result.json` records each source path, extraction anchor, line range and SHA-256, full source hashes, runner/template/generated-source hashes, compiler version and build/test exit codes.

## Boundary doubles and limits

- Foundation supplies collections and timing only. `NSObject`, `NSResponder`, `NSWindow`, `NSEvent`, text views/fields and keyboard codes are explicit in-memory doubles, not AppKit objects. The window's superclass counts system delivery, and responder replacement is counted. Mouse/swipe bodies compile but their platform side effects are no-ops and are not tested. No OS event injection or IME composition is claimed.
- Controller construction, active-tab installation and view lifecycle bookkeeping are doubles. The fixture supplies the same navigation topology: the profile is the stack controller, the media controller is embedded, and the media tab is its child. The production visibility method is executed, but scroll geometry, actual view attachment, bar swapping, animation and view unloading are not tested.
- `ChatInteraction` and its presentation are selection-only doubles. They preserve the relevant contract: non-nil selection means `.selecting` even for an empty set; updates notify on change; `withoutSelectionState` removes it. Database message loads, action eligibility and unrelated presentation fields are intentionally absent. The real media selection-notification branch updates state and panel visibility.
- `Atomic`/`ValuePromise` are synchronous value doubles. Media's production `state` observer sends the editing Boolean through a recorded table-scroll completion. The members fixture records that Boolean instead of generating actual member rows. This checks editing propagation, not member permissions or rendered row affordances.
- Story state includes only selected IDs. Production state/toggle/context-selection logic executes; rendered selection controls and action visibility are recorded by the promise sink, not by table transitions. Parent-owned and independent child-owned selection are tested separately. The base toolbar's existing `changeState()` behavior is retained: a story context selection can open the parent menu while the child alone enters selection. No Edit-availability/direct-Edit changes are included.
- Search state transitions and navigation `show` effects are doubles; actual routing priority, handler return values and stack removal decisions are extracted. Higher-priority focused search and modal handlers may legitimately consume Escape before shared-media selection. Their existing priority is intentionally unchanged. The normal confirmed media case, with no such handler, cancels even with zero selected messages.
- For embedded media, profile Escape now invokes selection cancellation only. An unfocused search panel without selection still follows the original profile back-navigation behavior. With selection, cancellation does not mutate that panel. Standalone media retains its existing search-before-selection order. This does not fix search-only behavior or Command-F.
- This suite does not establish full-package compilation, native rendering, animation timing or user acceptance. Manual validation in the integrated client remains necessary.

## Cases

The suite covers empty and nonempty message selection in media/files/links/music/voice/GIF tabs; context-started message selection; member editing and deferred completion; parent-owned story/archive selection; child-owned story/archive selection including an empty set; normal Escape on every tab (including nonselectable `InputDataController` children); profile editing priority; hidden media; inactive story selection; standalone media/story controllers; focused/unfocused search; editable/noneditable focus; higher-priority modal rejection/consumption/`invokeNext`; sheets and nonkey windows; locked navigation; a pushed controller above the profile; navigation-back veto; root rejection; handler removal on disappearance; and a missing active mode/current child.
