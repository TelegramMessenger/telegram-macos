# Header layout verification

Run `python3 tools/tests/chat-header/run.py --dependency-root /path/to/full/checkout --scratch-path /tmp/header-validation` on macOS. The runner compiles the actual inline-layout XCTest cases and extracted header, translation-menu and control methods against native TGUIKit and Translate, with controlled account/strings collaborators.

Only search without tags, pinned messages and Reopen Topic compact inline. Explanatory and request banners and stacked controls remain separate. The fixtures check narrow fallback, natural slot heights, insets, typing-status reflow, menu actions and Reopen Topic control label/callback behavior. See chat-search-integration/VALIDATION.md and current output for exact limits. Screenshots under screenshots are historical actual-client crops with neutral/public context; component assertions do not replace a current authenticated-client pass.
