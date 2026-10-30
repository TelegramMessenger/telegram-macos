# Remove individual recent emoji

```sh
python3 -I tools/tests/remove-recent-emoji/run.py \
  --signal-kit /path/to/telegram-ios/submodules/SSignalKit \
  --compatibility-ref 592446a5f9833ec24c84844b571d9caf6f06dec9
```

The default compatibility ref is pinned to `592446a5f9833ec24c84844b571d9caf6f06dec9`, the original recent-emoji deduplication composition from PR #117. Fetch that ref separately if needed, or pass its available local ref. Later PR #117 revisions have different scope and are not substituted automatically. This feature does not import that PR into its branch.

The runner creates a temporary Swift package and removes it on exit. It executes the complete production `RecentUsedEmoji` model and `Strings.swift` with real Cocoa/CoreText and SwiftSignalKit. It also extracts the ordinary emoji menu, the custom-emoji removal branch, the segment renderer/filtering, Recent-item resolution, the complete browsing segment loop, row selection and both coordinate lookup helpers. All picker modes and their row-mode mapping are extracted from production rather than maintained as a partial test enum.

On 2026-10-30, all 34 cases passed both against this feature and against a temporary composition with PR #117's model, string helpers and Recent rendering policy. Checks cover:

- Removing all variation-selector variants without rewriting or reordering surviving entries.
- Separate skin tones, legacy default-tone rendering, ZWJ sequences, flags and keycaps.
- Original source identity retained through display normalization, including reused visual layers.
- Exact custom-emoji namespace/file identity and immediate equality-driven updates.
- Custom Recent remains reachable when the last ordinary recent emoji is removed, without an empty Frequently Used Emoji header or ordinary block.
- Actual emitted row identifiers, ordering, indices, item identities and constructed row types for mixed, custom-only, ordinary-only and empty Recent states.
- A 192-state matrix spanning all 12 picker modes, ordinary recents present/removed, custom recents absent/resolved/unresolved/premium-filtered, and ordinary emoji allowed/fully filtered out.
- Independent reaction/quick-reaction/default-tag Recent and popular rows, status/background-icon/channel-status defaults, forum-topic defaults and icons, avatar custom recents, channel reaction replacement, and no Recent rows for message effects.
- Empty mode-specific data, custom premium gating, reaction fallback and clear actions, status deduplication/selection/expansion, icon and item limits, and expiration text.
- Idempotent removal, empty lists, JSON round trips and transaction-time reads of the latest preferences.
- Menu availability only with the explicit Recent callback; no removal for search/category rows, no accidental send, and menu identity unaffected by later pointer movement.

A bounded send/reload check reproduces the reported duplicate growth for both ✅ and 😁: four cycles produce counts `[1, 2, 3, 4]` with the current base's persistence logic and `[1, 1, 1, 1]` with PR #117. The removal operation clears the selected symbol's variants in both versions. This does not claim exhaustive verification of the separate PR.

For the picker regression, run the same fixture against the previous PR revision:

```sh
python3 -I tools/tests/remove-recent-emoji/run.py \
  --signal-kit /path/to/telegram-ios/submodules/SSignalKit \
  --source-revision cacb1121
```

That revision compiles and runs but fails nine cases in each model variant, including actual mode-specific row construction. Using `--source-revision 422a3a0b` fails eleven cases in each variant, retaining the two earlier empty ordinary section regressions. The tests do not equate a missing ordinary glyph segment with permission to remove unrelated Recent rows. Source checks also verify removal of the unused `emojiUnderMouse` accessor while retaining the private hover lookup used by click/drag handling.

## Boundaries

Postbox/PreferencesEntry, MediaId, media/reaction/peer/context data, InputDataEntry, row/layer/menu state, localization and the font factory are adapters. The forum-topic file hook and default-status-pack predicate are deterministic adapters; resource loading and TelegramCore implementations are not tested. JSON encoding/decoding is checked separately from the lazy in-memory transactional adapter. Custom-emoji menu coverage executes only its removal branch. Section-entry checks run the production pre-loop recent resolution and every browsing segment-loop branch, but not search execution, tabs, installed-pack/collectible rows, live subscriptions or complete controller assembly. Wiring checks inspect the search call sites. These tests do not claim real AppKit mouse dispatch, live account database mutation, server behavior or complete application validation. The PR #117 composition is not a full merge or exhaustive verification of that PR.

The normal context menu should be checked in the running app: Recent ordinary/custom emoji offers Remove From Recent; search, categories, installed packs and unrelated picker modes do not. Removing an item does not uninstall its pack, delete messages or prevent it being added to Recent on its next use.
