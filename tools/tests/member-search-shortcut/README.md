# Member search shortcut regression

## Run

From the repository root, with Python 3.9+ and a selected full Xcode installation containing Swift and XCTest:

```sh
python3 -I tools/tests/member-search-shortcut/run.py
python3 -I tools/tests/member-search-shortcut/run.py --baseline c64a3ea7
```

`--root /path/to/checkout` selects another source checkout. The default uses the checkout containing this runner, not the current directory. `--baseline` reads the original commit `c64a3ea77750fa753da0913cf26610df9b237640` with `git show`; it never checks out or modifies a revision. That commit must already exist locally.

The default temporary directory is automatically removed. To retain generated Swift, compile/test logs, source SHA-256 hashes and JSON results, pass `--output /path/to/new-directory`. Its parent must exist and the output directory must not exist, including as a symlink. Compiler caches and executables are temporary even with retained output. Do not commit generated evidence. The runner requires `python3 -I`, removes inherited `GIT_*` variables from child processes, discovers XCTest using `xcrun`, and downloads no dependencies.

Exit 0 means all requested expectations matched, including expected baseline failures. Exit 1 means unexpected test results. Setup, extraction or compilation errors are not negative controls and return 2.

## Executed production source

The runner inserts the original source directly into `MemberSearchShortcutTests.swift.in`:

- The case declarations of `PeerMediaCollectionMode`, excluding unrelated message-tag conversion.
- `PeerMediaController.hasSearch`.
- The complete Command-F registration statement from `viewDidAppear`.
- The complete search-button action closure from `loadView`.

Only the surrounding controller/framework boundary is replaced. The test window stores the registered handler and verifies its key/modifier; the child controller and member-search endpoint count calls. Optional external search is represented by a presence-only value. These are recording stand-ins, not alternate implementations of the availability predicate or action routing.

## Assertions and negative control

One real XCTest method runs 33 labelled scenarios, one `XCTAssertTrue` per scenario:

- 16 collection modes with and without external search: exact invoked/rejected result, expected member/child call counts, and button/shortcut parity.
- A released controller: the weak capture permits deallocation and rejects invocation.

Fixed source must pass 33/33 assertions. The original commit must compile, execute all 33, and fail exactly the 32 mode/external-search labels; the released-owner assertion passes. The runner compares the full expected failure-label set, XCTest failure count, assertion count and exit code, not merely a nonzero status.

This is offline, source-extracted native Swift/XCTest coverage. It does not dispatch an AppKit keyboard event, open member search, inspect GUI layout, or use an account/server. No app build, launch, profile, Keychain or network access is required. Source anchors intentionally fail closed if surrounding code changes; this small brace-based extractor is not a general Swift parser.
