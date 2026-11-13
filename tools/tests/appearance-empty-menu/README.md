# Appearance empty-menu regression

## Run

Requires Python 3.9+ and a selected full Xcode installation containing Swift and XCTest. From the repository root:

```sh
python3 -I tools/tests/appearance-empty-menu/run.py
python3 -I tools/tests/appearance-empty-menu/run.py --baseline c64a3ea7
```

`--root /path/to/checkout` selects a different source checkout; by default the runner locates its own checkout. Baseline reads the locally available original commit `c64a3ea77750fa753da0913cf26610df9b237640` with `git show`, without checkout/ref changes.

Output defaults to an automatically removed temporary directory. `--output /path/to/new-directory` preserves generated Swift, compile/test logs, source SHA-256 hashes and JSON. The parent must exist and output must not exist, even as a symlink. Compiled executables and module caches always autoclean. Do not commit generated output. Run with `python3 -I`; inherited `GIT_*` variables are removed from subprocesses. XCTest paths are discovered with `xcrun`; no dependency target, downloads or app build are needed.

Exit 0 means all requested expectations matched, including the baseline's expected assertion failures. Unexpected test results return 1. Setup/extraction/compilation errors return 2, not a successful negative control.

## Extracted source and boundaries

The fixture executes the appearance screen's custom-right-button factory and updater, InputDataController's appearance callback, theme-update and right-bar-update bodies, plus the navigation bar's opacity preparation and visible-right-bar opacity update.

Menu construction, conditional items, labels and images come from the factory. **Menu action handlers are replaced with no-op closures**: creating/exporting/sharing/resetting a theme is outside scope. With `--baseline`, the full original menu, including all untouched handler bodies, must have the same SHA-256 in both revisions before results are accepted. The runner also checks the existing theme-to-appearance signal chain, update-before-emission ordering, and child ownership of the glass effect. Those are source contracts, not execution of SwiftSignalKit or glass rendering.

Framework boundary stand-ins supply themes/palettes, image tokens, view hidden/opacity properties, menu storage and a synchronous appearance signal. The signal invokes the extracted production callback; it does not model queueing, disposal or every emission policy. No actual view, theme editor or sharing action is opened.

## Counts and expected failures

There is one real XCTest method, **94 view-verification scenarios and 411 assertions**, not 411 XCTest cases:

- 20 initial combinations: five built-in palettes, cloud theme present/absent, custom/basic accent.
- Two animated entries, starting in System or Day.
- 72 live changes on the same bar, including repeated System/Day transitions and all cloud/accent combinations.
- Each scenario checks visibility and icon refresh, plus either nil System menu or menu ordering/icons. Live changes also assert bar identity. A non-image bar is passed to the updater as a no-crash guard exercise without an additional assertion.

Fixed source passes 411/411 assertions. Original baseline compiles and fails exactly 37 System visibility assertions: four initial, one animated entry and 32 live transitions. All other 374 assertions pass. Step-specific labels are unique, and the runner compares the complete expected label list, assertion/scenario counts, XCTest failures and process exit status.

This is offline source-extracted native Swift/XCTest, not GUI/accessibility acceptance, pixel/glass rendering or real notification scheduling. No app launch, account/server, profile, Keychain or network use occurs. Narrow brace-based extraction is intentionally not a general Swift parser; source drift must be reviewed rather than treated as a passing baseline.
