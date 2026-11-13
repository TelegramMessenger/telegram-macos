# General Settings repeated toggles

Run from the repository root on macOS with Xcode selected:

```sh
python3 -I tools/tests/general-settings-toggle/run.py
python3 -I tools/tests/general-settings-toggle/run.py --baseline-ref c64a3ea7
```

The baseline command is expected to fail repeated-toggle persistence checks. The runner resolves the repository from its own location, strips inherited `GIT_*` variables for baseline reads, and invokes `xcrun swiftc` with a temporary module cache. No SPM dependencies are required. `--emit-only /absolute/path/main.swift` extracts the harness without invoking the compiler.

Coverage includes Copy Text Formatting, Send Large Photos, and Replace Emoji Automatically: unset defaults, initially on/off, four consecutive toggles using the same row, direct switch and whole-row actions, rapid mixed actions with a pending first commit, retained callbacks, rebuilt rows, and unrelated-setting preservation. Persistence is checked through a reopened Foundation `UserDefaults` instance in a unique suite, removed after each run; Telegram's preferences and account data are never accessed.

The harness extracts the exact row callbacks, controller writers, FastSettings accessors, SwitchView commit methods, and GeneralInteractedRowView action/state routing. It doubles row construction, drawing/animation, layers, accessibility notifications, and window state. Pending commits are completed explicitly. It does not test actual pointer delivery, animation timing, the full reactive table pipeline, or launch any GUI/app. Native SettingsUI tests require the wider app dependency graph and initialized submodules; manual app acceptance remains separate.
