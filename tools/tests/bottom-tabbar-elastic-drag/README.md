# Bottom tab bar elastic interaction tests

Run on macOS with the active Xcode command-line tools. The native-lens case requires a compatible Liquid Glass runtime and fails rather than silently skipping if it is unavailable.

From this checkout, use an absolute runner path and a **new absolute output directory** whose parent already exists:

```sh
python3 -I /absolute/checkout/tools/tests/bottom-tabbar-elastic-drag/run.py \
  --output /absolute/evidence/new-fixed-run
```

To test production sources in a separate materialized source tree without taking its Git history as authority:

```sh
python3 -I /absolute/checkout/tools/tests/bottom-tabbar-elastic-drag/run.py \
  --source-root /absolute/materialized-source \
  --output /absolute/evidence/new-materialized-run
```

For the original negative control:

```sh
python3 -I /absolute/checkout/tools/tests/bottom-tabbar-elastic-drag/run.py \
  --revision 246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5 \
  --output /absolute/evidence/new-baseline-run
```

The original source must compile, then exit nonzero for missing elastic behavior. `--revision` reads only from the runner checkout's Git repository. It cannot be combined with `--source-root` or `--tab-bar-source`.

To check a preserved earlier implementation that stretched the capsule without any additional foreground motion, use `--tab-bar-source /absolute/previous/TabBarView.swift` with a new `--output`. Only that production file is replaced; the remaining toolkit sources come from this checkout or `--source-root`.

The fixed source passes 29 scenarios and 585 assertions. The previously tested capsule-only source compiles and fails 72 assertions out of the same 585. The original base compiles and fails 130 assertions out of 510; spring-parameter checks only execute when a spring exists, explaining the smaller original-base count. Neither negative control treats a compiler failure as a reproduced behavior.

## What runs

The runner compiles the complete production `TabBarView.swift`, `GlassTouchEffect.swift`, and the seven underlying native Liquid Glass lens files using `swiftc -j2`. No alternative gesture or elastic geometry implementation is substituted. A separate real `GlassTouchEffect` instance supplies the expected transform, and actual `CASpringAnimation` objects are checked against the existing lift-off parameters.

Cases cover whole-capsule lift, two-axis pointer following, bounded displacement, one-third additional foreground travel relative to the capsule translation, vertical and subthreshold tracking, clearing that foreground offset on release/cancellation, long holds with fixed relative icon slots, selection commits, native/fallback/no-lens paths, Reduce Motion, Reduce Transparency, Escape, window resignation, resize, tab mutations, hide/detach, programmatic selection, effect reuse across reordering-policy changes, context-click routing, accessibility activation, and release/lifetime cleanup. Generic opted-in reordering remains supported; these tests do not change the application's reordering policy.

## Test boundaries

`Platform.swift.in` supplies lightweight TGUIKit view/control/tab/theme and glass-material stand-ins. Both `.swift.in` fixtures become Swift sources only inside the runner's owned temporary directory. It substitutes simple selection-frame/alpha transitions, not the production elastic animation. Production event-monitor registration is redirected to a local dispatcher so the real Escape callback can be invoked without sending GUI input. Cursor operations are redirected to a counter. Both substitutions are exact, checked source replacements; the gesture methods themselves remain unchanged.

Native AppKit views, offscreen window lifecycle, notification callbacks, Core Animation transforms, the production lens implementation and elastic springs run normally. Control base-class dispatch and accessibility plumbing are stand-ins; this is not a full TGUIKit integration test. Material appearance, the on-screen compositor, cursor appearance and physical input acceptance require the separate app build and manual test. No window is shown or activated, and no app, account, network or payment operation runs.

## Output and cleanup

Each output contains `compile.log`, `tests.log` when compilation succeeds, and `result.json` with source/fixture SHA-256 hashes and exit codes. Existing output directories and output-path symlinks are rejected. The runner strips inherited `GIT*` variables, owns its temporary directory and `TMPDIR`, bounds compile/run time, and removes generated sources, binaries and module caches on normal completion or failure. Only the small evidence files remain.
