# Telegram App Events — Naming Rules

Version: schema 1 (draft)
Source of truth: [`events.yaml`](events.yaml). This document explains the rules; the YAML is what clients implement.

Privacy rules restrict whether an event may be collected at all. A name or value in the registry does not grant collection permission. [PLAN.md](PLAN.md) separates current implementation gaps from the proposed interaction vocabulary.

The goal is one shared event vocabulary for every Telegram client (macOS, iOS, Android, Desktop, Web), so that usage can be compared across platforms without per-client mapping tables.

## 1. Transport

Events are sent with `help.saveAppLog` as `inputAppEvent`:

| `inputAppEvent` field | Value |
|---|---|
| `time` | Unix time in seconds (double) when the event happened, not when it was sent |
| `type` | Event name from `events.yaml` |
| `peer` | Always `0` (see Privacy) |
| `data` | JSON object: common params + event params |

Clients must queue events persistently and send them in batches (recommended: up to 50 events per request, flushed every 30–60 s and when the app goes to background). One request per event is not acceptable for automatic events such as `screen.show`.

Events require an authorized account. Screens shown before login are not covered by schema 1.

## 2. Event names

```
<section>.<object>[.<object>].<action>
```

- Lowercase ASCII only: `[a-z0-9_]` inside a segment, `.` between segments.
- `snake_case` inside a segment: `chat_list.folder.select`.
- 2 to 5 segments.
- The first segment is a section from `sections` in the YAML, or a platform prefix (rule 5).
- The last segment is an action from `actions` in the YAML.
- Never reuse a name for a different meaning. Deprecate instead (rule 8).

Good: `chat.message.send`, `chat_list.folder.select`, `call.end`
Bad: `ChatMessageSent`, `chat.sendMessage`, `chat.message_sent`, `sidebar.folder.click`

## 3. Name product concepts, not UI widgets

The same feature looks different on each platform. Names describe what the user does in Telegram terms, never how a given client draws it.

These words are banned in event names, screen ids and menu ids:
`sidebar`, `window`, `tab_bar`, `sheet`, `popover`, `drawer`, `modal`, `dialog`, `button`, `click`, `right_click`, `long_press`, `swipe`, `hover`.

How the user triggered something goes into the `via` param, not the name:

```
chat.message.menu… → menu.open {menu: "chat.message", via: "right_click"}   (macOS)
                   → menu.open {menu: "chat.message", via: "long_press"}    (iOS)
```

Use the words from `glossary` in the YAML. Example: `folder`, never `filter` or `dialog_filter`. A glossary term may contain a banned word when the word is the product's own name, e.g. `inline_button` for the buttons attached to messages.

## 4. Screens, menus and feature events

There are three kinds of events.

**Screens.** All screens share two events, `screen.show` and `screen.hide`. The screen itself is the `screen` param, whose value is a dotted id from `screens` in the YAML (`settings.privacy`). One event with an enumerated param keeps the registry small and lets every screen be queried the same way. Modals, sheets, popovers and pushed pages are all just screens; how they are presented is a platform detail.

**Menus.** All context and action menus use `menu.open` and `menu.select`. The `menu` and `item` params come from `menus` in the YAML.

**Feature events.** Things that actually happened: `chat.message.send`, `call.start`, `settings.toggle`. An eligible feature event fires regardless of how the user got there: `chat.message.forward` fires whether the user used a menu, a shortcut or drag and drop. Use `via` for invocation method and `source` for the eligible initiating screen. Acquisition route and final submission method are different facts; preserve them through the task using reviewed registry params. A menu selection that leads to an action can produce both events; dashboards must not count them as two completed actions. Every event must define whether it means intent, local acceptance or remote completion.

**Flows.** For tasks where the path matters more than single clicks (editing a group, creating a channel, changing a privacy rule), the client records each step locally while the task runs and sends one `flow.end` event when it ends. The event carries the ordered step ids with timings, the outcome and the total duration. This shows how users really move through a screen: which options they look at, in what order, where they hesitate and where they give up.

- A flow and its steps are defined in `flows` in the YAML. Steps are ids, never values: `change_title`, not the new title.
- Existing screen flows run per eligible screen instance. New journeys can span controllers and must be owned by the user task, preserving origin and privacy scope through every handoff.
- The outcome is one of `flow_outcomes`. Closing the screen without saving or cancelling is `abandoned`.
- Persist only eligible, allowlisted flow state with bounded size and lifetime once privacy-safe recovery is implemented. After a crash, an eligible snapshot may produce `interrupted` once under its owning account. Exclusion, disable or opt-out discards it silently; do not recover it under another account. macOS recovery is not implemented yet.
- Consecutive repeats of the same step are recorded once: typing a username is one `edit_username`, not one per keystroke.
- Steps can be user actions (`select_public`) or what the app showed in response (`username_taken`); both describe the journey.
- At most 50 steps are sent; `step_count` keeps the real total.
- Eligible normal events can still fire during a flow (`screen.show`, `settings.change`, `menu.select`). Existing flows add a summary; new journeys must justify any intermediate events separately and define how reports avoid double counting.

Name a screen by where it lives, not by the route to it: `peer_info`, not `chat.header.peer_info`. The route is the `source` param, which clients fill in automatically with the previous screen id.

## 5. Platform-only events

Events and screens that exist on one platform only are prefixed with the platform: `macos.`, `ios.`, `android.`, `tdesktop.`, `web.`.

```
macos.menu_bar.open
ios.widget.open
android.bubble.open
```

The core (unprefixed) set is the contract between clients: comparing a prefixed event across platforms is meaningless. When a second platform gets the same feature, promote the event into the core under an unprefixed name and deprecate the prefixed one.

## 6. Params

- Param names are `snake_case`.
- Types: `enum`, `bool`, `int`, `ms` (integer milliseconds), `bucket` (an enum of ranges), and registry references: `screen_id`, `menu_id`, `menu_item`, `setting_id`, `setting_value`, `flow_id`, `flow_outcome`, `step_list`.
- Every `enum` lists all of its values in the YAML. Clients must not send values that are not listed; add them to the YAML first.
- Prefer buckets over exact numbers for anything user-related: `{count: "2_5"}`, not `{count: 4}`.
- Reusable params are defined once under `params` and referenced by name.
- An event may only send the params listed for it, plus the common params. `flow.end` additionally accepts only the selected flow's declared params, never fields from other flows. Flow params cannot override envelope or common fields.
- A flow param may declare `outcomes: [success]` (or other registered outcomes) when its presence is meaningful only for those outcomes. Such conditions are part of runtime validation, not just descriptions.
- A flow may declare `timing_resolution_ms`, an integer from 1 to 60,000 (default 1). Its step and total durations must be multiples of that value. New media journeys use 1,000 ms resolution; keep existing flow semantics unchanged.

### Common params

Added by the client's analytics layer to every event, never at call sites:

| Param | Type | Example |
|---|---|---|
| `platform` | enum | `macos` |
| `app_version` | string | `11.12` |
| `build` | string | `283305` |
| `schema_version` | int | `1` |
| `session_id` | string | random UUID, new on each foreground session |
| `seq` | int | 0-based order of the event within the session |
| `layout` | enum | `compact`, `regular`, `wide` |

## 7. Privacy

These rules are part of the contract. A client that breaks them is not compliant with the schema.

- Secret-chat activity is unconditionally excluded, including creation/opening, descendant screens, menus, previews, editors, failures and delayed callbacks. No collection, recorder state, debug payload, persistence or transport is allowed. Never emit an exclusion/suppression event. See PLAN.md §3 for the boundary and transition policy.
- Resolve and propagate privacy/account scope before recording. Unknown scope is denied; a missing `peer_type` is not permission. Recheck before enqueue and dispatch. Legacy direct logging must obey the same exclusion.
- Disable and opt-out stop collection as well as transport and purge pending product analytics. Revoked flows cannot be replayed on re-enable. Account changes must not redirect events or flows to another account.
- No message text, captions, search queries, usernames, names, phone numbers, links or file names.
- No user, chat, message, story or any other ids. `inputAppEvent.peer` is always `0`. Describe peers only with `peer_type`.
- No free-form strings. Every string value is an enum value from the YAML (except the common params above).
- No exact counts of user data (contacts, chats, members, stars balance); use buckets.
- No clipboard contents/polling, content hashes, raw key/pointer streams, behavioral fingerprints or stable cross-session tracking IDs. Use bounded route enums and coarse timings for new interaction journeys.
- Optional client analytics is untrusted evidence, never sufficient by itself to classify a user as a bot or restrict an account. Missing telemetry means unknown.
- Enablement, opt-out, retention and access behavior must be defined before rollout. An authorized transport and `peer = 0` do not make events anonymous.

The existing events in `legacy` predate these rules and may carry ids; their vocabulary is retained for server compatibility and must not be copied. Compatibility is not an exemption from secret-chat exclusion or disable policy. Audit and gate direct legacy callers before enabling the new system.

## 8. Changing the registry

- Every change to `events.yaml` is reviewed by the registry owners before any client ships it.
- New events, screens, menus and enum values: add with `since: <schema_version>`. Adding is backward compatible and does not bump the schema version.
- Renaming or changing the meaning of an event or param: not allowed. Add a new one and mark the old one `status: deprecated` with `replaced_by`.
- Removing a value or a param, or changing a type: bump `schema_version`.
- Each entry lists the `platforms` that implement it, so analysts know where data can exist.

## 9. Tooling and implementation

- `tools/tg_events.py lint` enforces these rules on `events.yaml`: format, sections, actions, banned UI words, glossary terms, param types and values. A registry change is reviewable only when lint passes.
- `tools/tg_events.py gen` writes `generated/events.json`, the resolved registry every client generates its typed constants from. Do not write names as string literals.
- Client behavior (transport, common params, flow recorder, screens, debug checks) is specified in [IMPLEMENTING.md](IMPLEMENTING.md) and verified with `fixtures/flows.json`.
