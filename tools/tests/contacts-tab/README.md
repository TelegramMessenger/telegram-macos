# Contacts-only tab visibility

```sh
python3 -I tools/tests/contacts-tab/run.py
```

Contacts remains visible by default and when decoding settings without the new preference key. The harness checks the stored Contacts preference, its encoding, and its preservation when other General settings change.

The harness compiles the real settings model/Codable implementation and extracted tab-update methods with a minimal tab-controller adapter. It checks 449 assertions over 64 visibility/selection transitions, persistence, preservation of the preference through other settings mutations, and repeated updates. Source checks cover the settings action/order, Calls shortcut and theme indexing, and unchanged TGUIKit/localization files. The tests do not constrain unrelated feature names or preferences.

This is not a full application build or an AppKit event test.
