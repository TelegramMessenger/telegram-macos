# Saved Messages forwarding options

Run from the repository root:

```sh
python3 -I tools/tests/saved-forward-options/run.py
```

For an unpopulated worktree, supply the existing local dependency checkout:

```sh
python3 -I tools/tests/saved-forward-options/run.py --signal-kit /path/to/SSignalKit
```

The runner extracts the complete production `ForwardMessagesObject.performForward` and `Sender.forwardMessages` methods plus delivery-result helpers into a temporary XCTest package, using real SwiftSignalKit. It does not copy test sources into an application target or leave a build directory in the repository.

Coverage includes:

- Saved-origin messages forwarded to Saved Messages prepare a draft without enqueueing.
- The main Saved Messages history is reused only when its composer is usable after clearing selection.
- Pinned, scheduled, editing, and tag-filtered views open a normal history composer instead.
- An active recording blocks saved-origin draft forwarding before navigation or selection changes, with a notice to finish or discard it first. Retrying after recording finishes prepares the draft; external quick-save remains available.
- Extracted `ChatController.ableToNextController` and `confirmDiscardRecordingIfNeeded` bodies exercise both confirmation outcomes through the navigation adapter. Recording guard tests assert that neither a discard confirmation nor a controller factory is reached.
- Saved-thread targets normalize to the main Saved Messages composer, not a read-only saved thread.
- Existing input and explicit comments, refreshed IDs, mixed sources, albums, missing messages/peers, and readiness emissions.
- External-to-Saved quick saving and other-recipient topic routing remain unchanged.
- Sender constructs the expected forward-option attributes for all sender/caption flag combinations; hiding captions also hides sender attribution.

On 2026-10-30 the recording follow-up passes all 44 tests. The same fixture against the previous PR revision `93a36b54` compiles and runs, with 5 failing recording cases (27 assertions):

```sh
python3 -I tools/tests/saved-forward-options/run.py --source-revision 93a36b54
```

The original 37-test suite at `93a36b54` also established the initial forwarding fix against upstream `f7d4e807ced64412e676ba86533164112ba8a1e9`: 25 failing cases / 122 assertions before the fix.

The baseline invocation is expected to exit unsuccessfully. Extraction hashes and test counts are printed by the runner.

## Verification boundaries

Model/composer-state derivation, Postbox access, controller factories/navigation, success UI, and enqueue destinations are adapters. The tests exercise the actual routing method and Sender attribute construction, not the live AppKit menu, database, server delivery, wire serialization, or editability of delivered copies. Verify those with ordinary forwarded text and a photo with a caption in the running application. Rich Messages and inline-bot/media types retain their existing editing and Premium restrictions.

The separate multi-recipient `ShareMessageObject` flow, such as the gallery Share button, is unchanged.
