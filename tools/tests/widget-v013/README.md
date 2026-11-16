# Manual widget check

1. Build the Debug app, then quit it with **Command-Q**.
2. Double-click `manual-new.command` for the fixes, or `manual-old.command` for the previous app behavior. `manual.command` also defaults to NEW.
3. Telegram opens a local **Widgets — NEW** or **Widgets — OLD** chat once your Debug account is signed in.
4. Scroll through the five numbered cards. There are ordinary filler messages between them.

| Card | Try | Pass |
|---|---|---|
| 1. New zlib | Click the counter | The card appears and the count increases |
| 2. Older gzip | Click the counter | The card appears and the count increases |
| 3. Top edge | Add/remove rows with the card near the middle of the window | The top stays still; it grows/shrinks at the bottom |
| 4. Bottom edge | Add/remove rows with the card near the middle of the window | The bottom stays still; it grows/shrinks at the top |
| 5. Drag sideways | Drag the blue track horizontally, then scroll vertically over it | The number changes when dragged; vertical scrolling moves the chat |

Keep some messages above and below the resize card: the ends of the chat limit scroll compensation. Scroll several screens away and back, then repeat. Watch for sudden position jumps, blank cards and flickering. In NEW mode, “Resize API missing” or “Widget unavailable” is a failure.

## Compare OLD and NEW

Quit Debug Telegram with **Command-Q** between modes. The fixtures are identical; the three interactive cards use gzip so they load in both modes.

| Check | OLD | NEW |
|---|---|---|
| Card 1, zlib | “Widget unavailable” | Loads and clicks work |
| Card 2, gzip | Loads | Loads |
| Card 3, top anchor, Add row | Guesses from the clicked button and content; may hold the bottom | Keeps the top still |
| Card 4, bottom anchor, Add row | Guesses from the clicked button and content; may hold the top | Keeps the bottom still |
| Vertical wheel/trackpad scrolling | Scrolls the chat | Scrolls the chat |

OLD replays the previous Mac app integration's gzip-only decoder, resize heuristic and wheel-event routing in the same binary. It uses the current sandbox, so the resize API remains available; the app ignores its requested anchor in OLD. This is not an archived v0.1.2 binary or a replay of its cross-platform touch policy. The switch applies only to the Debug manual synthetic-widget harness; Release and normal launches keep NEW behavior.

These are local `TelegramMediaWidget` messages in the real chat renderer. The harness reads precompressed zlib/gzip bytes and passes them through the normal payload decoder, storage and row layout. It does not send messages or verify bot/server delivery. Use Back to leave; quit and run the launcher again to repeat.

`manual.py --behavior old` and `manual.py --behavior new` select the mode. The launch flag is `-PerfLabWidgetBehavior old|new` with the manual chat harness flags. `manual.py --prepare-only` creates the fixtures and a manifest without opening the app. `--app /path/to/Telegram.app` selects a different Debug build. Generated files and reports are in `.build/widget-v013-manual/`.

The focused automated checks are `python3 tools/tests/widget-v013/run.py`: payload decoding, the anchor kept next to prepared, live and cached heights, the list's scroll compensation for both anchors, and the renderer keeping the old pixels on the anchored edge when no press is recent.

Pass `--cache .build/widget-review/cache/payload` to reuse Debug and Release binaries when the extracted code, linked Swift sources, compiler version, platform and SDK environment match. Cache entries are locked and binaries published atomically. Tests and fixture generation still run on every invocation. The [layered widget harness](../widgets/README.md) enables this cache and supplies writable module caches automatically.

## Renderer checks

The widget renderer is twidget `c3fbe26` (its main for widget-sandbox v0.1.3). Its conformance runner plays the v0.1.3 automatic set on the Mac renderer:

```sh
TW_CONFORMANCE=1 swift test --package-path third-party/twidget --scratch-path /tmp/twidget-tests --disable-sandbox --enable-xctest --disable-swift-testing -Xlinker -framework -Xlinker QuartzCore --filter ConformanceRunnerTests
```

`auto/09-transforms-effects-a` (`translateX(%)`, `calc()` inside a transform) and `auto/24-resize-anchor` pass. Known non-passes: `auto/23-gestures` keeps its two vertical touch-drag checks pending (the runner sends mouse input), and `auto/17-drag-hover` reports `movementX` 133 instead of 160. At this commit `GestureClaimTests.testTheClaimCarriesHoldOnlyFromTouchActionNone` still expects the v0.1.2 claim `y: true` for `touch-action: none`; v0.1.3 never claims vertical drags, so the renderer's `y: false` is the expected value.

## Anchored edge, measured

`anchors.py` checks on screen that a widget bubble keeps its anchored edge still while it grows and shrinks. It opens the Debug app in a local chat with one probe widget (a red bar at its top, a blue bar at its bottom, Add and Remove buttons), finds the probe on screen, clicks its buttons through real mouse events, records the screen at 60 fps and tracks both bars in every frame. A run passes when the anchored bar sits on the same pixel row in every frame where it is drawn and the other edge moves.

```sh
cd tools/tests/widget-v013
python3 anchors.py --anchor bottom
python3 anchors.py --anchor top
python3 anchors.py --anchor bottom --timer
```

The bottom probe has its buttons above the rows and the top probe below them, so the renderer's own guess from the clicked button points at the other edge; `--timer` resizes from a script timer, with no press. The terminal running it needs Accessibility and Screen Recording access, and the Mac must be left alone while it runs. Each line also reports the frames in which the anchored bar is not drawn: a shrink currently shows one such frame, the same with or without the pin of twidget `c3fbe26`.

## Weekend trips carousel

After rebuilding and restarting Debug Telegram, open the carousel shown in the bot chat. Click and hold a card, drag left or right, then release. The cards should follow the drag and snap to the card matching the blue dot. Click a card to select its trip. Vertical trackpad scrolling over the carousel should still scroll the chat.

Two-finger trackpad scrolling does not generate the pointer drag this fixture listens for. Use click-and-drag for the horizontal check. Both OLD and NEW harness modes use the same pinned renderer.
