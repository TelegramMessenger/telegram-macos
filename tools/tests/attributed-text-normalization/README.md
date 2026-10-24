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
```

The runner copies the actual working-tree methods into an isolated Swift package
and copies the actual `String.nsstring`/`String.length` bridge from `Strings`.
Foundation and AppKit are native; no application dependencies are mocked. It prints
source and reference SHA256 hashes. The tests also belong to the normal TGUIKit
test target. The isolated run does not compile the whole TGUIKit package or app.

Ten tests cover LF versus CR/CRLF and other separators; Unicode and combining
marks; links, attachments, per-UTF-16 attributes and effective ranges; empty and
whitespace inputs; the helper's explicit argument; input/result mutation isolation;
long inputs; 1,500 deterministic randomized styled inputs; and 1,000 concurrent
calls. The original implementation passes the same behavioral tests.

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

## Measured results

2026-10-24, Apple Silicon Mac16,8 (12 logical CPUs), macOS 27.0.1, Swift 6.4.
Medians of nine paired Release batches per run:

| Scenario | Before, first / repeat (µs) | After, first / repeat (µs) |
|---|---:|---:|
| preview-short-plain | 2.340 / 2.323 | 0.481 / 0.490 |
| preview-short-styled | 2.750 / 2.680 | 0.974 / 0.997 |
| preview-no-newlines-styled | 2.197 / 2.111 | 0.398 / 0.383 |
| preview-long-styled | 51.451 / 51.572 | 37.268 / 37.358 |
| trim-short-styled | 5.119 / 5.140 | 4.768 / 4.777 |
| trim-no-separators | 2.274 / 2.304 | 2.235 / 2.282 |
| trim-separators-64 | 57.633 / 58.726 | 19.249 / 19.479 |
| trim-separators-512 | 2644.344 / 2659.282 | 137.376 / 139.363 |
| trim-separators-2048 | 40806.492 / 40992.797 | 544.764 / 543.425 |

Short preview normalization is 2.7–5.5 times faster; the 2,048-separator
synthetic input improves from about 40 ms to 0.54 ms (75 times). Trimming
without separators is effectively unchanged (the two runs vary within about 2%).
The optimization targets separator scanning; leading/trailing whitespace
trimming is preserved and is not claimed to have linear complexity.
