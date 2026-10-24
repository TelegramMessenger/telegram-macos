# Focused chat-header checks

Run on macOS with Xcode and the pinned `telegram-ios` checkout available:

```
python3 tools/tests/chat-header/run.py
```

To reuse compiler outputs between runs:

```
python3 tools/tests/chat-header/run.py --scratch-path /tmp/telegram-chat-header-build
```

The runner copies the production `ChatHeaderInlineLayout.swift` and its six XCTest tests unchanged into a temporary package. It also compiles the actual translation-menu functions and extracts the production header eligibility, accessory geometry, placement, history-inset, search-layout and typing-activity methods into controlled fixtures. Extraction fails when the expected source sections are missing.

The integration executable builds and links the real TGUIKit and Translate packages, including SwiftSignalKit, ObjcUtils, ColorPalette and KeyboardKey. It uses real `ContextMenu`, `ContextMenuItem`, `SearchView`, `ImageButton`, `View` and layout transitions, and loads the five images needed by TGUIKit's default theme from the app's assets. Search checks cover both optional buttons, six widths, keyboard focus, query retention, bounds and hit testing.

Chat presentation, account actions, localization and animated menu images use test doubles. The tests exercise translation availability, selection/toggle actions, language and tone menus, paywall handling, weak captures, pinned/search placement, auxiliary-row fallbacks, scroll insets and typing reflow. They do not compile the entire ChatUI target, link Telegram, run server-backed search/translation or validate Liquid Glass rendering. WebRTC, Rust engines and generated native media libraries are not required.
