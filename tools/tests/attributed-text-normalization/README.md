# Attributed text normalization

The regression suite compares the production `NSAttributedString.trimmed` and
`trimNewLinesToSpace` methods against a frozen reference from upstream commit
`4f356d8a82658a3fdeb18c5c4463dfb99733525d`. Keep
`packages/TGUIKit/Tests/TGUIKitTests/AttributedTextNormalizationReference.swift`
unchanged when modifying production code. Only the method names and imports have
been adapted, the original comments omitted and trailing whitespace normalized.

Run from the repository root on macOS:

```sh
python3 tools/tests/attributed-text-normalization/run.py
python3 tools/tests/attributed-text-normalization/run.py --configuration release
python3 tools/tests/attributed-text-normalization/run.py --source-ref 4f356d8a82658a3fdeb18c5c4463dfb99733525d
python3 tools/tests/attributed-text-normalization/run.py --benchmark
python3 tools/tests/attributed-text-normalization/run.py --benchmark --reverse
python3 tools/tests/attributed-text-normalization/run.py --render-output /tmp/normalization-render
```

The runner copies the actual working-tree methods into an isolated Swift package
and copies the actual `String.nsstring`/`String.length` bridge from `Strings`.
Foundation and AppKit are native; no application dependencies are mocked. It prints
source and reference SHA256 hashes. The tests also belong to the normal TGUIKit
test target. The isolated run does not compile the whole TGUIKit package or app.

Eleven tests cover LF versus CR/CRLF and other separators; Unicode and combining
marks; links, attachments, per-UTF-16 attributes and effective ranges; empty and
whitespace inputs; the helper's explicit argument; input/result mutation isolation;
long inputs; 1,500 deterministic randomized styled inputs; and 1,000 concurrent
calls. The original implementation passes the same behavioral tests. The rendering
test draws six styled inputs through Core Text for both normalizers and compares
the full RGBA buffers: all 12 reference/optimized pairs match. `--render-output`
saves the before/after PNG files; these offscreen fixtures exercise native shaping
and drawing rather than the complete Telegram chat view.

`U+2028` intentionally keeps the original canonical search options. In particular,
`U+2028` followed by a combining mark is not interchangeable with a literal
substring search. `U+FFFC` keeps literal search. Replacements preserve UTF-16
length, so their existing ranges remain valid. Whitespace trimming behavior is
unchanged.

The benchmark compiles production and reference code into separate modules,
without `@inlinable`. It validates outputs before timing, warms up both paths,
alternates their order over nine measured batches and uses a per-call autorelease
pool. `--reverse` reverses the initial order. Results are consumed via a checksum.
The last line contains JSON with every sample and median microseconds per call.
Timing is observational and has no machine-dependent pass/fail threshold.

These are method-level synthetic measurements. They do not establish an
application-wide CPU, memory, battery or scrolling improvement. Full application
build and real-chat rendering must be checked separately.

## Review validation

The branch was synchronized with current upstream master and checked against
README.md, AGENTS.md, CONTRIBUTING.md and the current pull-request template.
The production method implementation remains unchanged from the initial
optimization; the follow-up adds rendering parity coverage and this validation
record. No public signatures, package dependencies or language catalogs change.

On macOS 27.0.1 / Xcode 27.1 / Swift 6.4, all 11 tests pass in Debug and Release,
and the current upstream implementation passes the same 11 tests. The 12 PNG pairs
are also byte-identical after encoding. The full-client build result and fresh
benchmark observations are recorded in the pull request. End-to-end signed-in
chat interactions and app-wide CPU, battery or scrolling effects are not measured.

## Measured results

2026-10-24, Apple Silicon Mac16,8 (12 logical CPUs), macOS 27.0.1, Swift 6.4.
Medians of nine paired Release batches per run:

| Scenario | Before, first / repeat (µs) | After, first / repeat (µs) |
|---|---:|---:|
| preview-short-plain | 2.364 / 2.410 | 0.496 / 0.487 |
| preview-short-styled | 2.758 / 2.768 | 1.021 / 1.007 |
| preview-no-newlines-styled | 2.278 / 2.204 | 0.402 / 0.393 |
| preview-long-styled | 51.615 / 52.025 | 38.643 / 38.172 |
| trim-short-styled | 5.162 / 5.247 | 4.881 / 4.951 |
| trim-no-separators | 2.315 / 2.331 | 2.296 / 2.299 |
| trim-separators-64 | 58.085 / 58.635 | 19.020 / 19.328 |
| trim-separators-512 | 2671.073 / 2697.110 | 138.494 / 141.019 |
| trim-separators-2048 | 41111.669 / 41448.106 | 552.083 / 557.111 |

Short preview normalization is about 2.7–5.7 times faster; the 2,048-separator
synthetic input improves from about 41 ms to 0.55–0.56 ms (about 74 times). Trimming
without separators is effectively unchanged (the two runs vary within about 2%).
The optimization targets separator scanning; leading/trailing whitespace
trimming is preserved and is not claimed to have linear complexity.

The arm64 Debug application build passed with this production patch in the
prepared source tree (base 166e37d, local Xcode 27/test configuration).
The compiled Extensions.swift matches this branch byte-for-byte. This is not a
clean full build of the entire PR head; the native output/rendering checks above
exercise the changed behavior separately. The benchmark table records the fresh
paired runs performed after that build completed.
