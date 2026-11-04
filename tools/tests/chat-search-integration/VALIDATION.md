# Chat search verification

The current source and reproduction commands are the authority for this PR. Historical intermediate fade-only claims and their recordings have been removed: the 0.2-second input-background removal policy is already in upstream and is not a net change made by this PR.

Run on macOS with initialized native dependencies:

```sh
python3 tools/tests/chat-search-integration/run.py --dependency-root /path/to/full/checkout --scratch-path /tmp/search-validation
python3 tools/tests/chat-search-integration/run.py --revision a190a124 --expect-regression --dependency-root /path/to/full/checkout --scratch-path /tmp/search-validation
python3 tools/tests/chat-header/run.py --dependency-root /path/to/full/checkout --scratch-path /tmp/header-validation
```

The executable compiles actual ChatSearchHeader/ChatSearchView controls and extracted helper layout, attachment and header-slot logic with native AppKit/TGUIKit views and controlled domain/search collaborators. These are component checks, not an authenticated Stories or server-backed translation test. It covers wide/narrow geometry, full-width results, empty controls, tags, lifecycle, dynamic Stories hosts, ordinary suggestion caps and suppression of repositioning while dismissing. Baseline source without updateLayout omits calls to that newer API.

Native historical captures retained in chat-header/screenshots show two identical comparisons: public Telegram Tips search for stories, and Reopen Topic in a deliberately created validation topic. Only cropped headers/search results are published; no chat list or account identity is included. They establish original layout and prior full-client behavior, not a recording of the latest review fixes. The main application screenshot source comparison used macOS 27.0.1, Telegram 13.1.0 (283357), full Debug arm64 builds with real dependencies and local SDK/account-isolation overrides. Those overrides and other integration fixes are not part of this PR.

The current design preserves the translation bar and its existing Hide wording. Only search without tags, pinned messages and Reopen Topic are eligible for the inline slot; request/share-info/pending-request/bot-photo and other explanatory banners retain separate rows. Restoring a separate row uses the state's natural primary height rather than a previously stretched frame. Typing-status layout adapts the title to the available accessory width.

Current test outputs are recorded in review-search.txt, review-baseline.txt and review-header.txt. Full-client validation of the review follow-up, if performed, is recorded separately instead of being inferred from these component tests. Other macOS versions, continuous frame profiling, live Stories token resolution and live server translation remain unverified.
