# macOS sandbox admission regression

Run from the repository root:

```sh
python3 tools/tests/focus-sandbox-admission/run.py
```

This separate regression compiles the production permit and installation code.
It launches an owner from a temporary application and a reader from that
application's embedded `FocusIntents.appex`. The reader uses the production
`extensionBundle` initializer, including Darwin Mach-O identity checks.

The Darwin sandbox denies reads of the host application's `Info.plist` and
executable. The fixture first proves that both reads fail, then checks initial
denial, unlocking, relocking, verification failure/recovery and owner crash using
one persistent reader. Missing macOS or `sandbox-exec` fails the test instead of
reporting a successful skip.

The fixture binaries use ad-hoc signatures. Its temporary storage is not an
entitled App Group container, and the selective sandbox profile is not the full
App Sandbox profile generated for Telegram. This test does not install Telegram,
launch System Settings or prove that System Settings clears cached entity names.
Those scenarios still require the signed application and extension.
