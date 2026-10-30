# Boost permission component evidence

The current executable permission suite has 106 checks: `python3 tools/tests/reaction-permissions/run.py`. It tests the production decision and callbacks with controlled peers/send counters, including live restrictions and full message eligibility. Sufficient boosts only exempt default bans; personal bans remain effective.

RenderedBoostHarness.swift is optional diagnostic source under tools. It constructs actual TelegramCore peers/messages and a production row/picker with controlled boost state and available assets from a test account. Temporarily install it in a disposable full checkout and call codexInstallBoostReactionEvidence(source: chatInteraction, parent: genericView) from ChatController.viewDidAppear. It has distinct BoostReactionEvidence symbols so it can coexist with the other diagnostics. Output is created below TELEGRAM_BOOST_EVIDENCE (or the temporary directory), in reaction-boost. It is not a shipping target member and sends no reactions.

The before/after images and native reports are historical controlled-component evidence from the earlier boost patch, not a fresh live server test of the 106-check callback follow-up. Only the recorded macOS 27.0.1 Debug environment was available. A live restricted group and a physical double-click-to-react preference have not been verified.
