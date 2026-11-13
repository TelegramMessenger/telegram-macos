# Preview grouping preference

Run on macOS with the Xcode Swift toolchain:

```sh
python3 -I tools/tests/preview-grouping-preference/run.py
```

The runner extracts the actual preview-state initializer, Grouped/Ungrouped menu actions and preference accessor into a temporary XCTest package. The accessor uses an isolated, randomly named UserDefaults suite instead of the application's defaults. The suite is cleared by the tests; real preferences and accounts are not read or changed.

Coverage includes the unset default, saved grouping choices, reopening after menu selection, media/file modes, incompatible attachments and existing slow-mode grouping/archive fallback. Attachment capability and chat context are controlled stand-ins. No sends, live GUI or server operations occur.

Use `--output /absolute/new/directory` to retain generated test/build output outside the checkout. Without it, temporary files are removed automatically.

The same tests can check an earlier revision:

```sh
python3 -I tools/tests/preview-grouping-preference/run.py --baseline <revision>
```

Original code that ignores the saved preference is expected to fail. Manual preview/menu acceptance is still needed.
