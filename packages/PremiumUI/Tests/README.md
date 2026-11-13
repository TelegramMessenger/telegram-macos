# Business header layout regression

Run from the repository root on macOS with Xcode command-line tools installed. No package dependencies, Telegram account, app launch, or network access are required.

```sh
python3 -I packages/PremiumUI/Tests/run-business-header-layout-tests.py --check-only
python3 -I packages/PremiumUI/Tests/run-business-header-layout-tests.py --output-dir /tmp/business-header-fixed
python3 -I packages/PremiumUI/Tests/run-business-header-layout-tests.py --revision c64a3ea7 --output-dir /tmp/business-header-baseline
```

The fixed command must exit 0. The baseline command must compile successfully, then exit nonzero with `FAIL: coin title width at 1049.0`. A compiler error is not a reproduced regression. Explicit output directories must not already exist; choose new paths for another run. Omit `--output-dir` to use an isolated temporary directory that is cleaned up afterward. Add `--prepare-only` with an explicit output directory to generate Swift source without compiling or running it. The output directory holds the generated source, executable, and compiler module cache. Git-specific environment overrides are removed for source extraction and test execution.

The harness extracts the current caller's scene-specific view type, initializer forwarding, row column calculation, text measurement call sites, height, and view positioning from production source. It checks widths 320–1600 points, repeated resizing, both English Business messages, the screenshot's Russian text, long German title/body text, Japanese text, vertical spacing, and unchanged legacy width for star/grace/gift headers. English strings and font sizes are read from the repository; localization files are never modified. `--revision` extracts the same production sections from a Git revision without changing the worktree.

Text wrapping uses real macOS CoreText and system fonts. The surrounding row and frame probes are lightweight substitutes, not Telegram framework objects. This does not run `TextViewLayout`, instantiate `PremiumBoardingHeaderItem`, render SceneKit, validate the full app's layout lifecycle, or exercise any business/payment/account operations. Height assertions verify that the production row formula accommodates the probe's measured text, not pixel equivalence with Telegram's text renderer. The standalone test complements, rather than replaces, the app build and the user's manual resize/localization checks.
