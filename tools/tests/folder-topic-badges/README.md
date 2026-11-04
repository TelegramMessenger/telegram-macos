# Folder badges and muted topics

Run from the repository root with Swift installed and `submodules/telegram-ios` checked out:

```sh
python3 tools/tests/folder-topic-badges/run.py
python3 tools/tests/folder-topic-badges/run.py --macos-revision origin/master
```

The second command checks the original macOS calculation against the updated Postbox source and should fail the muted-only folder scenarios.

The harness compiles the actual `UnreadMessageCountsView.swift` and `makeChatListFilterItems` source, with controlled storage, peer records and synchronous signal fixtures. It covers folder counts and highlighting, mixed folders, regular chats, whole-group mute, membership, initial snapshots, transaction replay with an unchanged unread count, external refresh and changes between thread-based and regular peers.

It does not run a signed-in client, SQLite, the Postbox view tracker or asynchronous signal delivery. The shared Postbox regression tests in `submodules/telegram-ios/submodules/Postbox/Tests/ForumReadCountersViewTests.swift` cover the real in-memory Postbox and view tracker when run with the upstream iOS test target.

If the machine has a compiler/SDK mismatch, select a compatible installed SDK for this command with `SDKROOT`; do not change the system developer directory.
