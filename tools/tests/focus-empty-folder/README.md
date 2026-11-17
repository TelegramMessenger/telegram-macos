# Focus folder empty state

Run from the repository root:

```sh
python3 tools/tests/focus-empty-folder/run.py
```

For an isolated worktree without populated submodules, pass an existing Telegram-iOS source checkout:

```sh
python3 tools/tests/focus-empty-folder/run.py --telegram-ios-source /path/to/telegram-ios
```

The check compiles the production Focus filtering, support, predicate and text sources with the actual SwiftSignalKit sources and the pinned Postbox predicate/group declarations. Small account and chat-list fixtures provide independent live baseline and filtered views. All compiled files, caches and the localization test bundle are created in an automatically removed temporary directory.

Coverage includes:

- Active allow/exclude rules hide every chat, while a genuinely empty folder retains its ordinary reason even if another folder has chats.
- Partially visible folders, loading, incomplete pages, ordinary lists, forums, notification-only effects and untargeted accounts do not use the Focus message.
- The baseline uses the selected folder and its initial page independently of the currently displayed page.
- Live baseline membership and loading changes refresh the reason without restarting the filtered query; disabling Focus restores the unfiltered folder.
- Actual bundled Russian/English strings follow the application language, custom-language fallback and downloaded translation priority.

This isolated check does not render the row or exercise the full Postbox database, signed application, VoiceOver or live system Focus settings. Verify the visible message and accessibility text after rebuilding the application.
