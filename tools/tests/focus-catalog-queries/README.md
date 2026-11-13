# Linux Focus catalog query regression tests

On Linux, run `python3 tools/tests/focus-catalog-queries/run.py` with `swiftc` on `PATH`, or set `SWIFTC` to the compiler executable. The fixture runner rejects other platforms. On macOS, run the native `tools/tests/focus-intents/run.py` suite instead.

The runner compiles the complete production `FocusEntities.swift` and the real `FocusFilterCore` sources. A small test module supplies only the unavailable AppIntents entity/query protocols, display value types and identity string localization. The storage fixture supplies deterministic access changes and counts catalog reads. No production query or redaction implementation is copied into the fixtures.

The tests exercise all nine account/folder/chat query entry points, name/public ID/account name/blank searches, denial before catalog reads, revocation during the provider and after projection, restoration after unlocking, default access wiring, redaction of previously created entity displays and stable normalized saved identifiers and hashes. They also check that catalog projection does not invoke live display checks for each row.

This is an executable regression test for the production query logic, not native AppIntents validation. It does not validate Apple protocol requirements, real localized resources, interprocess admission, macOS System Settings caching, signed extension execution, or configuration/appContext/perform. Run `tools/tests/focus-intents/run.py` on macOS for the native intent suite; verify cached picker content manually in the signed application.
