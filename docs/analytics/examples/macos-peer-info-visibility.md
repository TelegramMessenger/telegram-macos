# Example: `peer_info.visibility` on macOS

The screen where a group or channel owner chooses public or private, edits usernames and links, and sets who can write and whether content can be saved. On macOS it is `ChannelVisibilityController` in `packages/ChannelSettingsUI`.

This example shows the required scoped recorder API. Its UI entry point must supply a scope inherited from an eligible task under [../PLAN.md](../PLAN.md); the existing controller still needs that migration. `init(engine:scope:)` verifies the account and is inert without a valid scope. Apply and test the remaining privacy foundation before enabling collection or expanding this pattern.

## Registry entry

From `events.yaml`:

```yaml
flows:
  peer_info.visibility:
    screen: peer_info.visibility
    params:
      peer_type:              # channel or group
      entry: [create, edit]
      initial: [public, private]
      result: [public, private]   # only with outcome success
    steps: [select_public, select_private, edit_username, username_available,
            username_purchase_available, username_taken, username_invalid,
            revoke_other_public_link, toggle_extra_username, reorder_usernames,
            copy_link, share_link, open_link, revoke_link, manage_links,
            set_write_everyone, set_write_members, toggle_approve_members,
            toggle_restrict_forwarding, save, save_failed_limit, save_failed]
```

## Where each step is recorded

| Step | Recorded when |
|---|---|
| `select_public` / `select_private` | the user taps the Public or Private option |
| `edit_username` | the username text changes (consecutive edits collapse into one) |
| `username_available` / `_taken` / `_invalid` / `_purchase_available` | the server's availability check returns |
| `revoke_other_public_link` | the user confirms freeing a username held by another of their channels (shown at the public link limit) |
| `toggle_extra_username` | the user confirms activating or deactivating a collectible username |
| `reorder_usernames` | the user finishes dragging a username to a new position |
| `copy_link`, `share_link`, `open_link`, `manage_links` | the matching action on the invite link |
| `revoke_link` | the user confirms revoking the invite link |
| `set_write_everyone` / `set_write_members` | the user changes who can send messages (discussion groups) |
| `toggle_approve_members` | the user flips "approve new members"; not recorded when choosing "everyone" turns it off implicitly |
| `toggle_restrict_forwarding` | the user flips content protection |
| `save` | the user taps Done |
| `save_failed_limit` / `save_failed` | saving fails (too many public links / other error); the flow stays open so a retry is recorded |

Outcome: `success` right before the screen reports completion, with `result` set. Leaving the screen any other way is `abandoned`, sent when the controller is deallocated.

## Code

```swift
private let flow: AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>

init(..., analyticsScope: AnalyticsScope?) {
    self.flow = AnalyticsFlow(engine: context.engine, scope: analyticsScope)
    self.flow.set(entry: isNew ? .create : .edit)
}

// first peer update
flow.setIfAbsent(peerType: peer.isChannel ? .channel : .group)
flow.setIfAbsent(initial: peer.addressName?.isEmpty == false ? .public : .private)

// user actions
updateCurrentType: { type in
    flow.step(type == .publicChannel ? .selectPublic : .selectPrivate)
    ...
}

// save succeeded
flow.set(result: updatedAddressNameValue.isEmpty ? .private : .public)
flow.finish(.success)

deinit {
    flow.finish(.abandoned)
}
```

Every name comes from the generated `AnalyticsRegistry.swift`; a typo is a compile error.

## Resulting event

A private channel made public; the first username was taken:

```json
{
  "type": "flow.end",
  "data": {
    "flow": "peer_info.visibility",
    "outcome": "success",
    "entry": "edit",
    "peer_type": "channel",
    "initial": "private",
    "result": "public",
    "steps": [["select_public", 1200], ["edit_username", 2900], ["username_taken", 3400],
              ["edit_username", 5100], ["username_available", 5600],
              ["toggle_restrict_forwarding", 8300], ["save", 9700]],
    "step_count": 7,
    "duration_ms": 9900,
    "platform": "macos",
    "schema_version": 1,
    "app_version": "11.12",
    "build": "283305"
  }
}
```
