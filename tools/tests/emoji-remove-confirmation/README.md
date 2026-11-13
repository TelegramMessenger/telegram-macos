# Emoji removal confirmation regression

## Run

From the repository root, with Python 3.9+ and a selected full Xcode installation containing Swift and XCTest:

```sh
python3 -I tools/tests/emoji-remove-confirmation/run.py
python3 -I tools/tests/emoji-remove-confirmation/run.py --baseline c64a3ea7
```

Use `--root /path/to/checkout` for another source checkout. By default the source root is determined from this runner's location. Baseline reads the original locally available commit `c64a3ea77750fa753da0913cf26610df9b237640` through `git show`; it does not check out or modify anything.

Default output is automatically cleaned. `--output /path/to/new-directory` preserves generated Swift, the revision's English bundle, compile/test logs, source SHA-256 hashes and JSON. Its parent must exist and output must not exist, even as a symlink. Module caches and executables always autoclean. Do not commit generated output. The runner requires `python3 -I`, removes inherited `GIT_*` variables from subprocesses and discovers XCTest with `xcrun`. No dependency downloads, localization regeneration or app build are needed.

Exit 0 means requested fixed/baseline expectations matched. Unexpected assertions return 1. Setup, extraction or compilation failures return 2 and never count as a negative control.

## Production extraction and baseline fidelity

Both variants extract their own unchanged `removePack` closure from CustomEmojiController. The runner follows the closure's actual confirmation accessor, extracts that revision's generated property, `L10n.tr`, `strings()` and `_LocalizedStringFor`, and copies that revision's exact UTF-16LE English strings bytes into a test bundle. Real Foundation `Bundle`/`NSLocalizedString` reads the bundle.

**The baseline receives no new emoji accessor or English key.** It selects the original sticker-description accessor and its original bundle, which compile without adaptation. Generic primary/secondary/fallback checks follow whichever accessor the real closure selects. Separately, an invariant assertion requires the displayed confirmation to equal `Are you sure you want to remove this emoji pack?` in both variants. Thus baseline fails at the real incorrect archive promise, not at compilation or an injected localization API. Fixed-only new-key localization checks are not misrepresented as baseline coverage.

Boundary stand-ins provide the alert recorder, window token/default title, language dictionaries, account/engine shell and recording remove operation. The small `translate` bridge accepts no format arguments and delegates to the extracted lookup; pluralization and language storage are not modeled. The fallback bundle location is supplied as a process argument rather than using an app's main bundle. The alert success/cancel closures are invoked manually; no alert is shown and no actual pack is removed.

## Assertions and negative control

One real XCTest method runs 14 labelled checks, one assertion each:

- Bundle readability, selected-accessor English fallback, primary precedence, secondary fallback and empty translation handling.
- Deferred removal before consent, selected window/default title, unchanged Delete/Cancel labels and emoji-specific wording.
- Cancel and non-basic confirmation do nothing; basic confirmation starts exactly one `.delete` for the selected ID.
- Ordinary sticker archive wording remains unchanged.

Fixed source passes 14/14. Baseline compiles and passes 13, failing only `emoji-specific confirmation replaces archive promise`. The runner checks the complete expected failure label list, counts, XCTest failures and process exit code. UTF-16LE BOM validation is an additional extraction contract, not a counted XCTest assertion.

This is offline source-extracted Swift/XCTest, not AppKit dialog behavior, live consent flow, account/server deletion or GUI acceptance. No app launch, profile, Keychain, network or payment behavior is exercised. The narrow anchored brace extractor is not a general Swift parser; changed source shapes fail setup rather than being silently approximated.
