# Native clipboard formatting comparison

Environment: macOS 27.0.1 (26A434), Xcode 27.1, Telegram 13.1.0 (283357), Debug arm64. Both complete workspace builds succeeded using real dependencies in the integration checkout. That checkout contains other pending UI work and local SDK/profile overrides excluded from this PR.

The temporary `RenderedCopyHarness.swift` creates production ChatMessageItem rows with controlled entities, invokes the actual application Copy callback through LinkHooks, reads the system pasteboard, decodes its real .kInApp data, and renders the resulting attributed text in a native ChatInputTextView. It also checks send preparation without sending anything. The matching screenshots use the same message and public channel context. The diagnostic window is explicitly labeled and does not recreate message or input rendering.

- Before: **32/60** checks pass. Inline and block code and quote metadata are lost during the clipboard round trip. The displayed draft becomes plain text. [Image](before.png), [checks](before-models.json).
- After: **60/60** historical checks pass (56 clipboard-path checks and 4 direct normalization checks). Code, language metadata, quote boundaries and collapsed state survive. [Image](after.png), [checks](after-models.json).

Cases cover inline code; preformatted blocks with missing, ordinary and long language identifiers; adjacent quotes; collapsed quotes; UTF-16 partial selection containing code and bold text; plain text; adjacent code blocks with different languages; and adjacent collapsed/expanded quote boundaries. Expected entities are independently clipped to the selection and trimmed for send preparation; the expected path does not use the production normalization being tested.

Reproduce with `python3 tools/tests/copied-message-formatting/build.py --source-root /path/to/full/checkout --derived-data /path/to/derived-data`. Use `--baseline <revision>` for the comparison. Open a chat in the resulting app, click Clipboard formatting validation, then Copy message → Paste draft → Check. Set TELEGRAM_COPY_EVIDENCE to choose the output directory; the fixture writes to its telegram-copy-formatting subdirectory. Build prerequisites and account setup are the normal application's requirements. The script now clones the supplied source checkout into a disposable APFS copy before injecting diagnostics. Hard termination can leave only that temporary copy, not changes in the supplied checkout. The hook and diagnostic window are committed under tools and are not members of the shipping target.

Boundaries: this exercises the production clipboard writer and codec followed by native draft rendering and send preparation. It does not simulate a physical context-menu selection or invoke the app's keyboard paste command. No messages were sent. Only this macOS version and Debug configuration were available. Other-app rich-text paste and a second macOS version were not tested.

## Current review checks

`python3 tools/tests/copied-message-formatting/review-tests.py` compiles the actual production parser, `textInputState()` mapping, markdown conversion, legacy conversion and inheritance block. **44/44 checks pass**. The previous identity stub for state conversion has been removed. The PeerId fixture supports the current nested ID API. Cases additionally cover syntax-highlighted code as one entity, code-key mapping, typed enclosing fences around pasted/edited structured code, literal fences inside an existing block, and adjacent blocks with different languages. Cases cover legacy fenced edits, rich-paste isolation, typed custom emoji and avatar-menu mentions inside bold/spoiler/quote text, retaining the inserted target metadata and excluding preceding mention/link/date/emoji metadata from inheritance.

The font refresh preserves code metadata and monospace. The shared copy callback affects all input fields; structured `.pre` state also reaches draft restore, editing and fact-check input. The retained 60-check native comparison predates these follow-ups.

The diagnostic launcher weakly captures ChatInteraction. Closing its window clears the global evidence owner, and the window disables release-on-close to avoid an over-release when its owning evidence is torn down. Opening another fixture closes the earlier one first. These are diagnostic lifecycle changes, not shipping UI.

Rendered block selections ignore the inline monospace marker when the same range has structured code metadata, preventing overlapping Pre/Code entities for Translate. Inline monospace still produces Code. The shared message-entity concatenation also affects rendering: touching quotes and touching code blocks with different languages remain separate in received messages as well as on copy.

Typing plain text or choosing an emoji strictly inside an existing link, mention or date preserves that semantic run. Insertion past its endpoint does not extend it, and explicit inserted metadata keeps its own target. The current 44-case suite against immutable 8c6edffa passes 38/44, reproducing the six in-run insertion failures. review-before.txt and review-checks.txt are this current comparison.
