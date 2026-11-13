# Affiliate introduction layout regression

Run on macOS with Python 3 and Xcode command-line tools:

```sh
python3 -I tools/tests/affiliate-intro-layout/run.py
python3 -I tools/tests/affiliate-intro-layout/run.py --revision c64a3ea7
```

The first command must pass. The second compiles the original source and must fail layout assertions; a compiler error is not a valid negative control. The runner uses an automatically removed temporary directory. `--output-dir /absolute/new/directory` retains the generated Swift source, binary and module cache and refuses an existing directory.

The fixture extracts the two header callers, superclass forwarding, row width/measurement/height/layout methods and option measurement/frame/content-size methods. Native CoreText and system fonts (medium titles/option headers and medium ranges for bold-marked text) wrap current English strings and Russian, German and Japanese fixtures at widths 320–1600, including repeated resizing. It checks standard column/insets, title/description bounds, icon offset, row heights and empty options. The original code fails because the header ignores its view type and option frames are narrower than their measured text.

Boundary stand-ins replace Telegram's row classes, view frames and TextViewLayout. CoreText exercises real font wrapping, but this is not Telegram TextViewLayout rendering, an AppKit window, SceneKit, or account-bound UI testing. No program creation, referral actions, financial operations or payment flows run. Visual acceptance remains a separate manual check.
