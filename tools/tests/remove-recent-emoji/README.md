# Remove individual recent emoji

```sh
python3 -I tools/tests/remove-recent-emoji/run.py \
  --signal-kit /path/to/telegram-ios/submodules/SSignalKit
```

The runner creates a temporary Swift package and removes it on exit. It executes the complete production `RecentUsedEmoji` model and `Strings.swift` with real Cocoa/CoreText and SwiftSignalKit. It also extracts the ordinary emoji menu, the custom-emoji removal branch, the segment renderer/filtering, Recent-item resolution, the complete browsing segment loop, row selection and both coordinate lookup helpers. All picker modes and their row-mode mapping are extracted from production rather than maintained as a partial test enum.

The tests run against the production Recent model from PR #117: entries are kept as used and matched ignoring variation selectors. On 2026-11-02 all 34 cases passed. Checks cover:

- Removing all variation-selector variants without rewriting or reordering surviving entries.
- Separate skin tones, ZWJ sequences, flags and keycaps; the saved skin tone is painted only on lists written before the canonical format, which are migrated on load.
- Original source identity retained through display normalization, including reused visual layers.
- Exact custom-emoji namespace/file identity and immediate equality-driven updates.
- Custom Recent remains reachable when the last ordinary recent emoji is removed, without an empty Frequently Used Emoji header or ordinary block.
- Actual emitted row identifiers, ordering, indices, item identities and constructed row types for mixed, custom-only, ordinary-only and empty Recent states.
- A 192-state matrix spanning all 12 picker modes, ordinary recents present/removed, custom recents absent/resolved/unresolved/premium-filtered, and ordinary emoji allowed/fully filtered out.
- Independent reaction/quick-reaction/default-tag Recent and popular rows, status/background-icon/channel-status defaults, forum-topic defaults and icons, avatar custom recents, channel reaction replacement, and no Recent rows for message effects.
- Empty mode-specific data, custom premium gating, reaction fallback and clear actions, status deduplication/selection/expansion, icon and item limits, and expiration text.
- Idempotent removal, empty lists, JSON round trips and transaction-time reads of the latest preferences.
- Menu availability only with the explicit Recent callback; no removal for search/category rows, no accidental send, and menu identity unaffected by later pointer movement.

A bounded send/reload check covers the duplicate growth reported before PR #117: four cycles for both ✅ and 😁 keep counts at `[1, 1, 1, 1]`, and the removal operation clears the selected symbol's variants.

For the picker regression, run the same fixture against the previous PR revision:

```sh
python3 -I tools/tests/remove-recent-emoji/run.py \
  --signal-kit /path/to/telegram-ios/submodules/SSignalKit \
  --source-revision cacb1121
```

Both revisions are in this feature's pull request history; fetch them with `git fetch origin pull/199/head` if they are missing. That revision compiles and runs but fails twelve cases: nine picker and row construction cases, including actual mode-specific row construction, and the three Recent model cases added with PR #117 (send/reload, renderer and skin-preference migration), since it predates that model. Using `--source-revision 422a3a0b` fails fourteen cases, retaining the two earlier empty ordinary section regressions. The tests do not equate a missing ordinary glyph segment with permission to remove unrelated Recent rows. Source checks also verify removal of the unused `emojiUnderMouse` accessor while retaining the private hover lookup used by click/drag handling.

## Boundaries

Postbox/PreferencesEntry, MediaId, media/reaction/peer/context data, InputDataEntry, row/layer/menu state, localization and the font factory are adapters. The forum-topic file hook and default-status-pack predicate are deterministic adapters; resource loading and TelegramCore implementations are not tested. JSON encoding/decoding is checked separately from the lazy in-memory transactional adapter. Custom-emoji menu coverage executes only its removal branch. Section-entry checks run the production pre-loop recent resolution and every browsing segment-loop branch, but not search execution, tabs, installed-pack/collectible rows, live subscriptions or complete controller assembly. Wiring checks inspect the search call sites. These tests do not claim real AppKit mouse dispatch, live account database mutation, server behavior or complete application validation.

The normal context menu should be checked in the running app: Recent ordinary/custom emoji offers Remove From Recent; search, categories, installed packs and unrelated picker modes do not. Removing an item does not uninstall its pack, delete messages or prevent it being added to Recent on its next use.
