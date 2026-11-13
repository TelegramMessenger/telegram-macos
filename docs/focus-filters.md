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
items with the same name. Selected items may remain visible in suggestions and
search; selecting them again does not add a duplicate. Removing and re-adding an
item remains supported, and each Focus form keeps its own selection. Existing
parameter names and entity identifiers are unchanged.

Parameters use each entity's default `EntityStringQuery` for suggestions, search
and identifier resolution. Queries must not depend on the parameter they resolve:
`IntentParameterDependency` on the same collection makes App Intents recursively
resolve that collection after its first selection, blocking the other pickers.
Using `optionsProvider:` instead would lose search text. Empty or whitespace-only
searches return the full catalogue; other searches match the trimmed text.

Account and chat titles use `Name (TelegramID)`, with only the number inside the
parentheses. This applies to suggestions, search results, selected items, account
subtitles and the filter summary. Account IDs are Telegram user IDs; chat IDs use
[Telegram's dialog ID format](https://core.telegram.org/api/bots/ids): positive user
IDs, negative group IDs, and the documented channel/secret-chat offsets. The app
publishes these display values separately from the stable local account and full
Postbox peer identifiers used by saved selections. Searching accounts/chats matches
the Telegram ID or name, rather than the internal composite identifier.

Older catalogues without these optional display IDs still decode. Until the updated
app republishes the catalogue, and for unavailable items, only the name is shown;
local record keys are never substituted for Telegram IDs. The same chat selected
through different accounts retains separate internal identity and an account
subtitle even when its primary `Name (TelegramID)` title is identical.

Folder titles show only the folder name. The subtitle identifies the owning account
as `Account name (TelegramUserID)`, without repeating its ID in the folder title.
This applies to suggestions, searches and restored selections. Folder searches
match the folder name, account name or account's Telegram user ID. Local account
record keys and folder identifiers remain internal. If the account's Telegram ID
is unavailable, the subtitle shows only the account name. The filter summary sorts
accounts by stable local identity.

After installing a signed build, select an account, then open both the folder and
chat pickers and confirm their suggestions still load. Repeat after selecting a
folder and a chat, and after reopening a saved filter. Check that selecting the
same item again does not add a duplicate, removing and re-adding still works,
same-name items remain independently selectable, and existing filters (including those
with repeated items) reopen with the intended selection. Also check a second
Focus mode: selecting an item in one mode must not remove it from another mode's
choices. Search for a known chat by name and Telegram ID, including one late in
a large catalogue; unrelated chats must disappear from the search results. Clear
the search and confirm that the full suggestions return.
After upgrading, also open Telegram and reopen an existing Focus filter: account
rows and the filter summary should show the positive Telegram user ID while
retaining the original selection and filtering behavior.

## Extension updates

The extension process is named `Telegram Focus Filters`, including its executable
and bundle display name. The internal target, `FocusIntents.appex` wrapper and
bundle identifier retain their names so existing system registration remains valid.
The only executable path is `Contents/MacOS/Telegram Focus Filters`; there is no
compatibility executable or symlink at `Contents/MacOS/FocusIntents`. New launches
use `CFBundleExecutable`, which names `Telegram Focus Filters`.

`FocusIntents` observes replacement of its own installed application. Telegram sends
an installation-check notification before account initialization on every launch,
covering direct updates, App Store updates and manual replacement. A lightweight
30-second timer also checks when Telegram has not restarted or a notification was
missed. Notifications are scoped by App Group and build channel; they only trigger
a check of the extension's original installation path, never unconditional exit.

The observer compares the running executable's Mach-O UUID and frozen file metadata
with the installed bundle. This detects development rebuilds with the same version
number, host-only updates and signed resource changes. Reading executable identity
is bounded to Mach-O headers and load commands, rather than loading the whole file.
Unavailable installation metadata or incomplete Mach-O headers postpone retirement. A changed
installation must remain stable for two seconds, with no active entity query,
notification-context calculation or configuration write, and two seconds since the
last such operation. The old process then exits successfully. No other process is
terminated, and saved Focus selections/configuration are not reset.

macOS starts the installed extension on the next request; Telegram does not launch
or manage the system's extension-host connections. This is cooperative retirement,
not an Apple API guaranteeing a transparent retry of an interrupted App Intents
request. The quiet interval allows replies to leave the extension but cannot prove
that the framework has delivered every XPC reply. Signed A-to-B update testing with
System Settings open remains required before release, including same-version
rebuilds, active queries, rule saving, and separate installed copies/build channels.
Confirm that the old PID exits and a subsequent picker request uses the new build
without losing saved selections or requiring manual process termination.

For the one-time development upgrade from a process named `FocusIntents`, or a
build without this observer, close System Settings and end that old process
manually. Its observer cannot follow an executable path that no longer exists.
Later builds using `Telegram Focus Filters` handle replacement automatically. Moving an application away without putting a
replacement at its original path does not trigger retirement.

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
updates. A fresh installation starts with filtering off. If the saved settings
cannot be read or decoded, Telegram delivers chat notifications for all accounts
using ordinary Telegram and macOS settings. The same fallback applies if a
notification rule needs folder membership and its catalogue cannot be loaded.
The chat list can still use the last configuration and catalogue held in memory.

Telegram shows a warning once per failure when the main window is ready. It
explains how to save the filter again in System Settings → Focus. Once the
required data is available, filtering resumes automatically. Explicitly disabling
the filter or starting without saved settings does not trigger a warning.

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

Browsing or searching accounts, folders and chats requires the corresponding
Telegram installation to be running and unlocked. Access starts denied before
decryption and is revoked before asynchronous passcode checks or lock-screen UI.
Screen locking and logout revoke it too. A live process permit is scoped to the
build channel, application directory and executable identity; another installed
copy cannot grant access. Multiple processes for the same installation must all
be unlocked. Process termination releases its permit, and absent owners, stale
installations and access failures deny catalogue reads.

Saved selections still resolve to their stable identities while locked, with
neutral placeholders instead of names or public Telegram IDs. Entity display
getters recheck access, including for objects created before locking. Configuration
restoration, notification predicates and intent execution remain available in the
background; locking does not disable a saved Focus rule or change notification
fallback behavior. This gate protects the extension's catalogue interface, not
the shared file against another process with App Group access. It cannot revoke
text already copied into System Settings' own rendering cache; that behavior
requires an installed, signed application check with the editor open.

While the filter is unavailable, new notifications carry a neutral criterion that
also passes the last predicate installed by the extension. Otherwise, notification
criteria contain the account, full peer identifier and folder tokens.
The system predicate matches stable tokens, so a folder's membership can change
without invalidating an old system predicate. Notification delivery must obtain
current per-chat folder membership before the local gate, sound and criteria are
created; the debounced picker catalogue is not a delivery-time authority.

Catalogue publication and delivery-time folder evaluation use the same application
adapter to resolve contact status and individual mute settings through the peer's
notification-settings identity, matching the chat-list view predicate. For a
secret chat these belong to the associated user; unread state, mention summaries,
pinned membership and exported chat identity still belong to the secret chat.
The catalogue enumerates root/archive chats without a folder predicate, then
applies each canonical folder predicate to the shared per-chat state in the same
transaction. Global settings are loaded once per catalogue snapshot, and chat
state is reused across folders. Changes to contacts and individual/global mute
settings continue to trigger catalogue updates through the existing subscriptions.

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
python3 tools/tests/focus-catalog-access/run.py
python3 tools/tests/focus-lock-state/run.py
python3 tools/tests/focus-extension-lifecycle/run.py
python3 tools/tests/focus-filters/build_extension.py
python3 tools/tests/focus-filters/build_extension.py --configuration Release
```

The chat-list test compiles the actual production predicate adapter with the
predicate and group type extracted from the pinned Postbox source. The catalogue
test uses lightweight transaction fixtures around the production projection.
The notification test combines the production catalogue projection, shared folder
state, live adapter and folder mapper with the pinned Postbox predicate and mute
resolver. It compares catalogue-derived chat-list policy with delivery-time policy
under both selection rules, including a newly unread chat before publication.
Secret-chat cases give the chat and associated user opposite contact/mute values,
cover global mute fallback and keep unread/mention lookups on the secret chat.
The associated user need not have an entry in the chat list. Repeated snapshots,
archive membership and pinned/include/exclude precedence use the same checks.
Injected resolver checks cover a configuration change during a pending lookup,
fallbacks and avoiding unnecessary lookups. Native-query checks compile actual
extension sources against isolated providers and verify ID-based uniqueness,
renaming, removal/reselection, same-name and cross-account items, ID labels/search,
stale identifiers, enum mappings, configuration and persistence failures. Repository
checks inject memory persistence/change delivery, verify callback execution outside the lock,
and distinguish missing files from permission failures.
These checks do not replace complete application compilation or a device test.

The catalogue-access check compiles the production permit implementation and
uses separate owner and reader processes for startup, revocation, crashes,
concurrent owners, installation replacement and failed-state recovery. The lock
state check compiles the production state-transition methods with lightweight
signal fixtures. Both also run with a Linux Swift compiler. On Linux,
`python3 tools/tests/focus-catalog-queries/run.py` additionally compiles the
production entity queries with display/protocol fixtures. It does not validate
App Intents serialization, metadata or system rendering; use the native intent
runner on macOS. Darwin file-lock semantics and Mach-O identity checks still
require macOS. Set `SWIFTC` for the access/query runners, or pass `--swiftc` to
the state runner, when the compiler is outside `PATH`.

On a signed macOS build, check every picker and search route while initially
locked, after unlocking, and after locking with the editor already open. Confirm
that existing names and IDs disappear from system-rendered results, saved
selections survive, and their rules still execute. Repeat with two installed
copies, simultaneous processes, crash/relaunch and an A-to-B application update.
Do not treat a passing getter test as proof that System Settings clears its cache.

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

## Review follow-up: 12 November 2026

Forum folder membership now obtains unread state from the same Postbox helper used by the folder view. It respects effective unread topic counts and the display-as-regular-chat fallback. The helper is exposed through the existing macOS Telegram-iOS preparation patch; the submodule revision remains unchanged. Regression cases cover disagreement between peer and topic read states, both selection modes, published chat-list membership and live notification membership.

Validation in the Linux maintenance environment: the preparation patch applied, reapplied idempotently, reversed, and applied again successfully. Native regression execution stopped because `xcrun` is unavailable; neither these Swift tests nor the macOS application build have been reported as passing.

The remaining requests in review comment https://github.com/TelegramMessenger/telegram-macos/pull/128#issuecomment-6819660757 are not resolved by this change:

- The picker still needs passcode-aware access control, including identifier resolution without breaking background activation of saved rules. A native test must cover locking while System Settings already holds entity names; hiding only subsequent query results cannot establish that cached names are cleared.
- Actual CPU, memory and update latency of catalog scanning must be measured against a large signed-in account. This environment has neither a running macOS Telegram instance nor such an account, so no performance measurements have been claimed.
- Configuration read failure deliberately retains the user-selected behavior: use ordinary Telegram/macOS notification settings with a visible warning until the filter can be restored. This behavior was not changed to match the reviewer's alternative suggestion.
