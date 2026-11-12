# Returning from Settings restores the sidebar

Run `python3 tools/tests/settings-sidebar/run.py` on macOS with Xcode installed.
`--baseline` runs the same fixture against upstream e18830989542a063dd66c5bdc4dbe6a70cbbd175; `--baseline-ref REF` selects another original revision.

The runner extracts the actual `checkSettings`, `backFromSettings` and navigation-listener methods and their stored state from MainViewController.swift. Swift collaborators model the navigation stack and sidebar selection; the production navigation decisions are not reimplemented. Twenty behavior checks cover Back, nested settings, repeated entry, explicit tab selection, a previous profile/empty pane, entry from Contacts, Calls-tab removal, single-column layout and the wallet-create exception. A separate source check verifies listener registration. The original code passes 9/20 behavior checks and fails listener registration; the patch passes all checks.

These checks establish controller/selection behavior with controlled navigation callbacks. They do not establish AppKit animation, gesture timing, or accessibility behavior. Native-client observations are recorded separately below.

## Full-client check

- macOS 27.0.1 (26A434), Debug arm64 Telegram build 283357.
- Before: integration 43cf267bf0691f6788be8a261e597acbd0bd8fb5.
- After: integration da53b896; the MainViewController change matches this branch. Both clients include unrelated integration fixes and use an isolated validation profile. The installed main Telegram app is unchanged.
- Open Saved Messages, open Settings with Command-comma, then press Escape. Before, the right pane returns to Saved Messages while the sidebar still says Settings. After, the sidebar heading and selected tab both return to Chats, and Saved Messages remains open.
- Reopen Settings and activate its Back button. The same restored chat/sidebar result is observed. Reopening and returning again does not leave Settings selected.
- No messages were sent and no account settings were changed.
- Nested settings and other layout exceptions are covered by the controlled checks, not claimed as native-client validation. Interactive swipe cancellation was not exercised.

`verification/before.png` and `after.png` are identical crops `(180, 14, 2900, 110)` from 3024x1770 native window screenshots. Only the sidebar heading and Saved Messages header are retained. Chat lists, account details and message contents are excluded. No interface content is reconstructed.

Review follow-up: the entry controller is tracked until it is removed by a Settings section that replaces the stack. Back within that new Settings stack does not accidentally select Chats when the saved target was the shared empty controller. A missing return tab falls back to Chats and clears the pending return state. The runner now passes 20/20 behavior checks plus registration; earlier native screenshots remain the same scenario.

The saved return page is now the nearest controller that survives a push, excluding removeAfterDisapper and keepLeft controllers. The fixture removes those controllers during push, matching native navigation instead of retaining every page. Four additional checks cover transient InputData and keepLeft detail pages before Settings; Back restores the actual surviving page and original sidebar.
