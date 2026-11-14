# Settings redesign implementation plan

Goal: apply the approved native settings prototype to Telegram settings, preserving Telegram icons, actions, navigation and window radii.

Architecture: opt settings tables into one shared layout in GeneralRows. Content determines row size independently of card position. Non-settings tables retain their current presentation. InputDataController carries the opt-in through its existing transition factory; direct entry tables apply it at their item factory.

Values: text 38pt, standard icon 43pt, two-line 53pt (System Settings Apple Account page), hub 45pt; 13pt titles, 11pt subtitles, 10pt inner insets and icon gap. Devices use 26pt icons. Sidebar uses 32pt pitch, 20pt icons, 8pt icon gap, 9pt left content inset inside a 3pt selection inset, based on the supplied 2x reference.

- [x] Add metrics and layout regression checks for card positions, accessories, long subtitles, narrow widths and sidebar selection.
- [x] Implement opt-in content geometry, fonts, scaled existing icons, centered accessories and inset separators.
- [x] Apply to settings entry factories and InputData screens, including section headers, footers and gaps.
- [x] Adapt the settings sidebar and device rows; retain existing assets and handlers.
- [x] Run available compiler checks and geometry tests; attempt the repository build/test path and record environmental blockers.

Validation must distinguish runnable geometry checks from a full Telegram build. The local machine currently has Command Line Tools only, without Xcode.

Validation: standalone metrics executable passes 15 checks. All 54 changed/new Swift files parse successfully; git diff --check passes. Full package testing with `swift test --package-path packages/GeneralRows --build-system native` stops in existing dependencies: OpusBinding cannot find `opus/opus_multistream.h`, and libwebp cannot find `decode.h`. `xcodebuild` is unavailable because only Command Line Tools are installed. XCTest integration cases were added but could not run in this environment. Production app visual comparison remains to be performed on a machine with the native dependencies and Xcode.

Review: an independent reviewer checked the diff. Addressed sidebar account alignment and removed label-width reservation for hidden sidebar arrows. Settings presentation is opt-in; window/panel radii, global themes and original icon assets are retained. The top-level settings list uses the latest sidebar reference rather than hub sizing. Hub metrics remain available for pages that use hub rows. Existing screen actions and notification controls are retained; this checkout does not contain the notification-category controls shown in the reference app, so this change does not invent notification functionality.
