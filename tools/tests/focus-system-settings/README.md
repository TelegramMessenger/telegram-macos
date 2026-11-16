# System Settings Focus editor integration

The separate `Focus System Settings UI (macOS)` PR check runs XCTest against the
real `com.apple.systempreferences` application on a disposable GitHub-hosted Mac.
It opens Focus → Do Not Disturb → Add Filter → Telegram Focus CI and exercises
account, folder and chat selection/search, locked access, unlock recovery, and
locking while a chat picker is already open. Retained names cause a failure.

The fixture host embeds the production FocusIntents extension built from the
production target. Its storage, admission, queries, entity displays and intent
implementation are unchanged. The host seeds synthetic data and controls the
production live permit through two test buttons; it does not log in to Telegram.

The generated project uses separate bundle IDs and the real test App Group
`group.org.telegram.FocusSettingsCI`. Both targets are ad-hoc signed. The tests
handle only fixture-specific App Group access consent prompts. No production
signing credentials or real Telegram data are used. This verifies consent-based
App Group integration, not Telegram's distribution provisioning, actual passcode
UI, complete application build or notification delivery.

`run.py` refuses to operate outside GitHub-hosted runners. It never changes the
local machine's accessibility or privacy permissions. `build.py --output <path>`
is build-only and can be used locally without opening any application.

Failures to build, obtain access, discover the extension, navigate the editor or
satisfy an assertion fail the job. Tests are not silently skipped. Every run
uploads logs and an `.xcresult` bundle with screenshots and accessibility trees
for seven days; these show whether a failure is in setup, UI navigation or the
actual behavior being tested. Existing native unit/regression jobs remain
independent.
