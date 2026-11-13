# Shared-media edit availability

Run on macOS with the selected Xcode toolchain and Python 3, from any directory:

```sh
python3 -I tools/tests/shared-media-edit-availability/run.py
```

By default all results are automatically cleaned up. To retain logs, pass `--output /tmp/shared-media-edit-availability-results`; the destination must not exist and must not be a symlink. The runner accepts `--source-root`, `--baseline-ref` or `--baseline-source` (a preserved earlier controller file); the default baseline is `c64a3ea77750fa753da0913cf26610df9b237640`. It strips inherited `GIT_*` variables, invokes `swiftc -j 2`, and removes its temporary Swift sources, executables and module cache automatically. No package resolution, network, app build, GUI, account or persisted preferences are used. Only compile/test logs and source hashes remain in the requested output directory.

## Executed production source

The suite extracts the current `PeerMediaController` state observer, menu/capability methods when present, toolbar setup, title refresh, update method, controller lookup and complete tab-activation method. It extracts the selection-state branch from `notify` without changing its body. It also executes the real editable superclass state observer, `changeState` and `update(with:)`, the real story child menu callback, and the collection-mode enum. Visibility is relaxed in the temporary harness only. The same extraction and assertions run on the baseline and fixed source. Missing new capability methods are not synthesized into the baseline. The Members tests also extract the exact row-local `deletable`/enabled accumulation and existing `TelegramGroup`/`TelegramChannel.canRemoveParticipant` methods. Permission bits, participant models and delivery of the resulting child capability to the parent are boundary doubles. Both variants execute the current extracted row predicates in separate permission tests. Parent reactions are tested independently with explicit Boolean capability events; an older parent without the capability-update handler ignores those events. Tests cover creators/admins, ordinary members, self, creator targets, invited basic-group participants, admins promoted by this account, other admins, ban permission, disabled rows and empty lists. Invite/promote/tag rights alone do not invent a deletion action. No new moderation predicate replaces the existing helpers.

Twenty-two native XCTest cases cover unsupported Saved/Polls/Groups and other non-selection children, supported grid/list/member/story selection, Done, child-owned menus, separator-only menus, shared-message selection retention, switching selection owners, interactive tab activation, selection notifications, no-observer synchronization, delayed member-scroll callbacks, empty/no-rights Members, live eligibility changes, and basic-group/channel participant removal eligibility.

## UI boundary doubles and limits

The harness supplies minimal deterministic stand-ins for controls, containers, tables, signals, interactions, navigation and child controllers. These record the real extracted code's menu, visibility, selection and layout requests. A table deliberately queues scroll completions to exercise stale callbacks. Shared media child classes identify the actual controller kinds used by production lookup; Saved/Polls use non-sharing child instances. The story menu itself is extracted, not reimplemented. The mock superclass forwards toolbar refresh to the extracted title method, matching the production superclass.

This is not a full PeerInfoUI build and does not claim AppKit rendering, glass hit testing, animation timing, real database/message permissions, or VoiceOver integration coverage. Native compilation errors are fatal harness failures, never accepted negative controls. Success requires all fixed assertions to pass and the baseline to compile, execute all tests, and fail behavioral assertions. User acceptance should check Saved/Polls/Groups have no inert action, message-media tabs retain selection, leaving that selection domain clears Done and the bottom panel, and supported story/member controls still work. Escape routing is intentionally unchanged.
