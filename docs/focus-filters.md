# macOS Focus filters

On macOS 13 or newer, the `FocusIntents` ExtensionKit extension exposes Telegram in
System Settings → Focus → a Focus → Add Filter. All filter configuration belongs
to System Settings. There is no Telegram profile editor or custom Focus scheduler.

The system form has five parameters:

| Parameter | Behavior |
| --- | --- |
| Accounts | Apply the rule only to these signed-in accounts. Other accounts retain their usual behavior. |
| Effect | Notifications only, chat list only, or both. |
| Rule | Allow selected, or exclude selected. |
| Folders | Use the current membership of the selected Telegram chat folders. |
| Chats | Select individual private chats, groups, or channels, in addition to folders. |

Folder and chat selections are combined as a union, using account-qualified,
namespaced peer identifiers. A selection belonging to an account outside Accounts
has no effect. Both effects use the same union. With an empty Accounts selection,
the filter is inactive. With selected accounts and an empty union, Allow Selected
allows no chats; Exclude Selected excludes none. macOS sends the default parameters
when the filter is disabled, restoring normal behavior.

Focus adds a restriction to the existing Telegram notification decisions. It does
not enable muted notifications or override macOS notification permissions or the
Focus's general application/person allowances. A chat-list-only rule does not
apply additional notification suppression. Calls and existing unread badge totals
are outside this filter's scope.

The visible-list effect applies to the main chat list, Telegram folders and the
archive. Filtering enters the Postbox query before pagination, retains eligible
pins, and also validates the final result against raw chat identifiers. The archive
navigation row retains its normal unread count, with chat titles and message
previews removed while filtering. Search, quick switching and already open
conversations remain usable; this feature does not implement an access lock.

## Selection identity

Accounts, folders and chats are Set-valued App Intents parameters. The system
receives unordered collections without duplicate support; entity equality and
hashing use only the stable identifier, so renaming an item does not make another
selection. Query results also remove repeated identifiers while retaining distinct
items with the same name. Existing parameter names and entity identifiers are
unchanged; saved identifier arrays resolve through the same queries.

Each entity's primary display title includes `(ID: identifier)`. This is visible
both when choosing an item and in the selected-items list, where macOS may omit
subtitles. Accounts use their local account record ID; folders use
`accountId:folderId`; chats use `accountId:fullPeerId`, including the Postbox peer
namespace. These are the filter's stable identifiers, not Bot API chat IDs. The
account prefix distinguishes the same chat or folder selected through different
accounts. Unavailable items retain their ID label, and searches match IDs as well
as names. The filter summary sorts accounts by ID for stable display.

After installing a signed build, check in System Settings that each picker
prevents adding the same item twice, removing and re-adding still works, same-name
items remain independently selectable, and existing filters (including those
with repeated items) reopen with the intended selection. Also check a second
Focus mode: selecting an item in one mode must not remove it from another mode's
choices.

## Dependency boundaries

| Boundary | Responsibility | Dependencies |
| --- | --- | --- |
| `FocusFilterCore` | Identifiers, configuration, catalogue values, selection rules and repository/source contracts | Swift standard library |
| `FocusFilterInfrastructure` | JSON persistence, cross-process change delivery, storage location and native notification predicate/criteria | Core and Foundation |
| Application adapters | Postbox catalogue projection/publication and live notification membership | Injected Core contracts, Telegram/Postbox adapters; Infrastructure formats native notification criteria |
| Chat-list presentation | Query composition, archive/pin preservation and visible results | Core policies supplied through `ChatListFocusHooks` |
| App Intents presentation | Native parameters and searchable entities | Core values; Infrastructure creates the native notification predicate and the repository in extension composition |

AppDelegate creates the process repository once and injects it into catalogue and
notification adapters. It installs the chat-list policy stream before creating
those screens. The extension has its own composition point. Consumers do not
resolve paths or access a mutable shared store.

The repository coordinates injected persistence and change-delivery adapters.
Observer callbacks, read-failure reporting and cross-process posting execute
outside the state lock. Pending deliveries preserve order during reentrant
updates. Missing files use defaults; unreadable or corrupt files are reported and
recover independently, preserving the valid component of the state.

Catalogue publication and delivery-time membership are separate operations. The
notification resolver consumes a policy source and live-lookup dependency, returns
a named decision, and retries if the configuration changes while lookup is pending.
Native entity queries accept a catalogue provider; enum mappings are exhaustive.
Archive query scope requires its membership set, preventing a partially configured
archive-only query.

## Data and lifecycle

The extension alone declares `TelegramFocusFilter`; it atomically persists the
parameters delivered by the system. The application reads them at startup, on
activation and after a distributed notification. The shared directory is
`<App Group>/<build channel>/FocusFilters`, isolated between Debug, Stable,
App Store and Beta builds. New files use mode 0600 in a 0700 directory.

The application publishes a local catalogue of account/chat/folder identifiers,
display names, archive membership and resolved folder membership. It exports no
message content or phone-number fallback names. Account logout removes that
account from the catalogue. The catalogue uses local Postbox views and coalesced
transactions, without requesting remote chat history. Its additional view memory
and transaction cost should be measured with large accounts before release.

Notification criteria contain the account, full peer identifier and folder tokens.
The system predicate matches stable tokens, so a folder's membership can change
without invalidating an old system predicate. Notification delivery must obtain
current per-chat folder membership before the local gate, sound and criteria are
created; the debounced picker catalogue is not a delivery-time authority.

State recovery follows Apple's extension/shared-storage design. It restores the
last configuration delivered by macOS; it cannot independently establish current
system state if macOS fails to execute the extension. No private Focus APIs or
direct changes to saved system Focus settings are used.

## Development checks

Run from the repository root:

```
swift test --package-path packages/FocusFilterCore --disable-sandbox
python3 tools/tests/focus-chat-list/run.py
python3 tools/tests/focus-catalog/run.py
python3 tools/tests/focus-notification-membership/run.py
python3 tools/tests/focus-intents/run.py
python3 tools/tests/focus-filters/build_extension.py
python3 tools/tests/focus-filters/build_extension.py --configuration Release
```

The chat-list test compiles the actual production predicate adapter with the
predicate and group type extracted from the pinned Postbox source. The catalogue
test uses lightweight transaction fixtures around the production projection.
The notification test combines the production live adapter and folder mapper with
the pinned Postbox predicate and mute resolver, checking a newly unread chat
against both selection rules without waiting for catalogue publication.
Injected resolver checks cover a configuration change during a pending lookup,
fallbacks and avoiding unnecessary lookups. Native-query checks compile actual
extension sources against isolated providers and verify ID-based uniqueness,
renaming, removal/reselection, same-name and cross-account items, ID labels/search,
stale identifiers, enum mappings, configuration and persistence failures. Repository
checks inject memory persistence/change delivery, verify callback execution outside the lock,
and distinguish missing files from permission failures.
These checks do not replace complete application compilation or a device test.

The extension build check extracts the real `FocusIntents` target and its local
package dependency into an isolated project. It compiles and links the extension,
checks the host's embedding/dependency declarations, and validates the system Focus
protocol, five parameters, Set collection capabilities and original entity types,
English/Russian resources and build channel in extracted App Intents metadata.
Release also checks both Apple Silicon and Intel binaries.
It neither installs nor runs an application or extension, and code signing is off.

The complete application still requires the submodules, generated sources and
native libraries described in [INSTALL.md](../INSTALL.md). Xcode 27 additionally
requires the local compatibility preparation in [XCODE27.md](../XCODE27.md).

For a signed development build, use your own bundle identifier, development team
and matching App Group in the app and extension, including `FOCUS_APP_GROUP` on
the extension. Follow the existing fork instructions in INSTALL.md. Do not install
a development build over an existing Telegram installation. When bumping the host
version, synchronize the extension with the existing helper:

```
sh tools/sync_share_version.sh Telegram-Mac/Info.plist FocusIntents/Info.plist
```

System Settings discovery, activation/deactivation, real notification delivery,
signing and interaction with a user's existing accounts require a separately
authorized device test. Automated compilation and policy checks do not establish
those results.
