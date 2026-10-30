# Reaction callback verification

Run `python3 tools/tests/reaction-permissions/run.py`: **106/106** controlled checks pass. The runner extracts production permission, eligibility, quick action, chip and picker bodies, including `ChatPresentationInterfaceState.canSendReactions(to:)`. Peers, cold signals and engine send counters are controlled; no server requests or paid Stars transfers are made.

Run `python3 tools/tests/reaction-permissions/run.py --revision de608bb0`: the immutable merge-base comparison passes **72/106**. `master-before.txt` and `current-checks.txt` contain this comparison. It exercises row retirement, current selection state, live rights, default-ban boost exemptions, personal bans, deletion and media replacement.

The static reaction picker looks the same at this merge-base, which already includes the boost exemption. The earlier boosted-picker images under boosts/ are historical diagnostics and do not demonstrate this PR's current change. The before/after distinction is callback execution after row refresh and live message validation, recorded by executable send counters instead of an unchanged layout screenshot.

The row-independent closures use the shared presentation permission helper, preserving upstream's boost semantics. Both restriction toasts carry the localization task marker. Paid actions re-read the message and pending media state before acting. Separate diagnostics under lifetime/ and boosts/ are optional sources, excluded from shipping membership; their native captures predate the current source fixture. Real restricted-group delivery, physical double-click preferences and another macOS version have not been verified.
