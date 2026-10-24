# Developer menu localization checks

Run from the repository root on macOS:

```sh
python3 tools/tests/developer-localization/run.py
python3 tools/tests/developer-localization/run.py --output /tmp/developer-localization
python3 tools/tests/developer-localization/run.py --baseline
```

The final command intentionally fails against the original resolver: the updated
English and Russian catalogs alone are insufficient while missing cloud strings
still fall straight through to English. At the initial upstream base
`250e5ebc33379c905d413cf9e0466d5f7da04f47`, it reports 35 failures; the patched
resolver reports 9,294 checks with zero failures under each of English and Russian
system-language preferences.

The runner builds a temporary native `.app` bundle containing the real `.strings`
resources. It compiles the production `Language` and `TelegramLocalization` types,
lookup/formatting functions, all generated L10n accessors, the String bridge and the
real NumberPluralization Objective-C implementation. The account/settings signal
layer is replaced only by an explicit test language value. Foundation, Bundle,
formatting and plural selection are native. No Telegram account is used.

Coverage includes:

- Russian bundled fallback when new keys are absent from downloaded translations.
- Downloaded primary/secondary translation priority and empty downloaded values.
- A custom language with Russian as its secondary/base language.
- Regional identifiers (`ru-RU`, `RU_ru`), unsupported languages and empty bundles.
- Missing-key nil/key behavior, English-only NativeLocalization and every existing
  English fallback key without a new Russian value.
- Generated menu accessors, ordered engine names, preserved warning/diagnostic code,
  Russian plural forms at 0, 1, 2, 5, 11, 21, 22 and 25, English singular/plural, and 1,000
  concurrent bundle lookups.
- English/Russian/English language selection, matching preview row counts, new-key
  uniqueness and format-argument parity. Existing unrelated catalog duplicates
  are outside this change.

The source check also verifies that the controller observes `languageSignal` and
provides a dynamic navigation title. Full controller/signal integration is not
executed by this harness.

`--output` saves before/after AppKit **text previews**. The before labels are read
from the upstream controller; the after labels call the generated production
accessors and real localization resolver. Both images use the same simple AppKit
renderer. They are not screenshots of a running Telegram client and do not prove
Telegram layout, interaction or full application build correctness.

The fallback caches available locale bundles once and derives matching exact/base
bundles when each Language object is created. Normal lookups do not enumerate the
filesystem or rebuild bundles. Downloaded translations retain priority; bundled
primary/secondary translations precede the final English fallback. Unsupported
languages do not acquire unrelated Russian strings.

The `.strings` files remain UTF-16. Regenerate accessors with:

```sh
sh tools/swiftgen.sh
```

The original source contains no `News: Skip Read History` row; this change does not
add an unavailable setting from another release/channel.
