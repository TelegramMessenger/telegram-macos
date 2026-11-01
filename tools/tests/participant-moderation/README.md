# Participant moderation menus

Run `python3 -I tools/tests/participant-moderation/run.py` on macOS with Xcode and the repository's native dependencies built. Additional arguments are forwarded to `xcodebuild`, for example `-derivedDataPath /path/to/dedicated-test-build` and local linker overrides needed for native dependencies.

The runner uses the `PeerModerationUITests` workspace scheme to compile the actual PeerModerationUI and ChatUI modules against TelegramCore, Postbox, TGUIKit and SwiftSignalKit. It selects `ChannelParticipantModerationMenuTests` and the existing `ChatAvatarMenuBindingTests`. It does not extract production source or replace Telegram models with stubs. Run it in an isolated build workspace rather than using a running app's derived-data directory.

Moderation items are initially disabled while fresh channel/participant authorization is pending, including when an allowed historical participant snapshot exists. Other menu items remain immediately usable. Authorized results enable the existing item instances; denied, unavailable, empty or timed-out results remove moderation items and clean up separators and empty author submenus. Invocation-time authorization remains separate from the menu lookup.

The native tests cover nil snapshots resolving to owners and uneditable admins; ordinary members and editable admins; allowed stale snapshots; missing, mismatched and revoked permission results; synchronous completion before menu attachment; timeout; disposal and late results; fresh invocation authorization; and delayed authorization across same-context avatar refresh, semantic rebinding and removal. The existing avatar suite covers the broader metadata and semantic-binding matrix.

These are native menu/model/signal tests. They do not contact Telegram servers, modify account data or establish real-client manual moderation behavior. Older external extracted-source moderation/service harness results are historical and are not evidence for this gate.
