# Focus extension lifecycle subprocess checks

Run on macOS with Xcode command-line tools:

```sh
python3 tools/tests/focus-extension-lifecycle/run.py
```

The test compiles the production `FocusFilterCore` and `FocusFilterInfrastructure` sources and two standalone executable fixtures inside a temporary directory. It does not start or modify the installed Telegram application, read its account data, or register a real app extension.

Both fixtures use the current executable name `Telegram Focus Filters`, the same application path, bundle identifiers, and `CFBundleVersion`. Neither build contains the old executable path `FocusIntents`; the test rejects that path even if it is a dangling symlink. Each fixture checks its Foundation process name, executable name, and bundle name. This covers future updates using the current name. For the initial transition from the old name, the user manually ends the old `FocusIntents` process once; no compatibility alias is provided.

The first fixture retains an active request for 35 seconds. The test replaces its application bundle with the second build using directory renames without sending an update notification. It verifies that the production periodic check detects the replacement at the current executable path, allows the active request to finish, waits for the retirement grace period, and exits successfully. The second fixture must remain alive for 45 seconds through repeated same-build launch notifications and a periodic check; its explicit normal-exit marker distinguishes that completion from accidental retirement.

Allow approximately 90 seconds plus compilation. The script removes its temporary files on success or failure and, if necessary, terminates only the child processes that it started. Each fixture also has a 60-second failure deadline. Notification names use a fresh identifier for each run.

This exercises real filesystem replacement, loaded executable identity, timers, request guards, and process retirement. The fixtures are standalone processes, not signed sandboxed AppIntents extensions hosted by System Settings. The test does not establish that macOS retries an interrupted AppIntents request or launches the updated extension automatically; that requires a signed application update test through the system interface.
