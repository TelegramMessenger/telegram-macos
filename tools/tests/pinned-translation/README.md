# Pinned translation refresh

```sh
python3 -I tools/tests/pinned-translation/run.py --telegram-core /path/to/TelegramCore
```

The runner compiles the production outgoing eligibility helpers, content snapshot/batch, translation State and the actual `ChatPresentationInterfaceState.TranslateState` projection with the repository's model and presentation XCTest suites. Foundation/NaturalLanguage and XCTest are real. Telegram message/media models are adapters; rich-text/block declarations and plain-text traversal are extracted from the supplied TelegramCore checkout. Each suite's message-construction helper is adapted, not its assertions.

The suites cover version-only pinned refresh without a collection pass, content/entity/rich-text changes, rich-page view counts, enabled/target guards, incoming pins, edited-source cache/loading invalidation, and the existing outgoing-language/reply/transcription policies. Seven additional cases execute the animation/rebuild expressions extracted from the real pinned-header update: same-message reactions, edits and pin-list metadata do not replay the pin-switch transition, while selecting a different pin retains it. A macOS 10.13 deployment typecheck covers extracted production availability, not old-OS runtime behavior.

`--negative-control` adds message stableVersion back into source identity. Version-only refresh tests must fail. This is a targeted mutation control, not a checkout of the previous implementation.

`--header-source-revision ea656cf0` runs the same animation fixture with the previous PR revision's actual header expressions. Same-message refresh cases must fail while the state/projection suites remain green. This verifies the transition decision, not AppKit animation playback.

Source integration checks verify both header callers use the tested ChatUI projection, no duplicate model pinned lookup remains, the header redraws updated pinned message versions, pinned updates notify the collector, and recognition stays in the prepare-queue path. These checks are not a live AppKit scroll/navigation test, a full module build, or a server translation test. Temporary package/build outputs are removed after each run.
