# Notification exception Return regression

## Run

From the repository root, with Python 3.9+ and a selected full Xcode installation containing Swift and XCTest:

```sh
python3 -I tools/tests/notification-exception-return/run.py
python3 -I tools/tests/notification-exception-return/run.py --baseline c64a3ea7
```

`--root /path/to/checkout` selects another source checkout. The default uses this runner's checkout regardless of the current directory. The negative control reads `c64a3ea77750fa753da0913cf26610df9b237640` through `git show`; the object must exist locally. No checkout or ref changes occur.

Default output is automatically cleaned. `--output /path/to/new-directory` retains generated Swift, compile/test logs, source SHA-256 hashes and JSON results. Its parent must exist; the output must not exist, including as a symlink. Compiler caches and test executables always use an automatically removed nested temporary directory. Do not commit generated output. The runner requires `python3 -I`, strips inherited `GIT_*` variables, discovers XCTest with `xcrun`, and requires no dependencies or downloads.

Exit 0 means both fixed and requested baseline expectations matched. Exit 1 denotes unexpected assertions; setup/extraction/compilation failures return 2 and never count as baseline detection.

## Executed production source

The fixture extracts, rather than reimplements:

- The notification controller's `apply` closure, `validateData` binding when present, and Done interaction.
- `InputDataController.returnKeyAction`, `validateInputValues`, and the complete `validateInput(data:)` method. Only `public override`/`public` declaration modifiers are removed where the standalone test class requires it; bodies are unchanged.
- The existing close-header assignment and handler. The fixed/baseline handler hashes must match.

The runner separately checks that both modal Return and KeypadEnter registrations delegate to `returnKeyAction`. These source checks are not native event dispatch tests.

Boundary stand-ins supply the current event, input-data/controller shell, empty form/table data, optional pending state and a recording engine. The empty table intentionally exercises the no-text/no-input-limit path used by these settings. Validation result handling is a no-op; return invocation uses `.default`. Engine calls record ordered arguments when started; the close callback records `close`. There is no persistence, signal scheduling or server operation.

## Assertions and negative control

One XCTest method runs 100 labelled scenarios with 100 `XCTAssertTrue` calls:

- Ordinary and story settings across eight pending-state combinations: unchanged, mute on/off, previews on/off, sound off/custom, and all fields.
- 16 Done assertions check exact ordered engine operations, exception insertion and closure.
- 64 Return assertions check parity with Done for two key-code inputs and two sending-ability results.
- 16 existing close-header scenarios check cancellation produces only `close`.
- Four checks cover the latest pending state, event-independent Done, absent-event forwarding and weak controller ownership.

Fixed source must pass 100/100. Baseline must compile and fail exactly the 64 Return labels plus `reads current state`, leaving 35 passing assertions. The full failure-label set, counts, XCTest failures and exit code must match. Key codes 36/76 are simulated inputs; the extracted method does not itself route by key code.

This is offline, source-extracted Swift/XCTest coverage, not AppKit dispatch, GUI acceptance, account/server behavior or a full-app build. No launch, profile, Keychain, network or payment behavior is exercised. Extraction uses narrow unique anchors and balanced braces, not a general Swift parser; source drift is a setup failure.
