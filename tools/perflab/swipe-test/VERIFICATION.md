# Native widget scrolling verification

The exact `swipe-test.html` initially failed to scroll through the production widget host. Its overflow values were rewritten to hidden, vertical wheel events were intercepted by the chat wrapper, horizontal scroll eligibility used only overflow-y, and scroll event subscriptions were filtered.

The macOS native host now explicitly enables native scrolling. The default shared profile remains unchanged. Wheel events reach the native scroll view, horizontal navigation yields over horizontal scroll regions, each overflow axis is checked independently, and opted-in widgets receive scroll events.

## Evidence

- Before: the exact HTML fails six assertions; both offsets and JavaScript counters stay zero (`evidence/before.txt`).
- After: 28 native scroll tests pass. Real wheel events through the renderer's view move the vertical list to 234 px and the horizontal strip to 240 px. The HTML's own labels report the same offsets (`evidence/after.txt`).
- Enabled → disabled → enabled host checks pass. Default hosts remain clipped and expose no wheel regions.
- 38 validator tests and four native capability unit tests pass (`evidence/validator.txt`, `packages/core/tests/unit/native-scrolling.test.ts` in widget-sandbox).
- Final arm64 Telegram Debug build succeeds and was restarted with the fix.

The unchanged HTML remains 1894 UTF-8 bytes. These checks cover native macOS wheel/trackpad scrolling. The shared policy reserving vertical touch drags for the parent chat is unchanged. Actual hardware interaction remains a separate manual check; native tests route constructed wheel events through the view.

App routing commit: `9463d6ccb4`. Native renderer commit: `84dea17`. Widget host/validator commits: `15d58d5`, `b37c2b6`, `9c22c78`.

## Update: vertical swipes belong to the chat

Vertical swipes over a widget always scroll the chat; a widget only takes horizontal swipes. `HTMLTwidgetContainer` now routes each trackpad gesture once: zero-delta start events are held until the first movement, horizontal movement over a horizontal scroll region goes to the widget, and everything else goes to the chat. Widget scroll containers clamp at their edges without rubber banding or a settle spring.

Checked in the running app with phased gestures posted through the HID event tap: horizontal swipes starting with a zero-delta `began` move the strip, momentum stops flush at both ends, the vertical list stays at 0, and vertical swipes over widgets scroll the chat with momentum.
