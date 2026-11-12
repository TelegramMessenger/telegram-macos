# Context menu screen position

```sh
python3 -I tools/tests/menu-screen-position/run.py \
  --signal-kit /path/to/telegram-ios/submodules/SSignalKit
```

The runner copies the branch's TGUIKit and its small native dependency graph into a temporary package, then compiles the actual target and test sources. No menu/controller/window implementation is replaced by an adapter. It runs `AppMenuScreenPositionTests` together with the existing bubble-animation, context-menu-item and table-row-menu-lifecycle suites.

Position tests create real non-fullscreen windows, set their frames to the screen's visible desktop area, and present real context menus from synthetic right-click events. They check first presentation near the top edge, several menu heights, cursor-relative placement away from the edge, smaller windows, `betterInside`, bottom clamping/anchoring, existing horizontal adjustments, hover presentation and every connected screen. Menu handlers are inert; no sticker pack is removed. The two padding rows in a native MenuView are included in row-count assertions.

```sh
python3 -I tools/tests/menu-screen-position/run.py \
  --signal-kit /path/to/telegram-ios/submodules/SSignalKit \
  --source-revision 7b3a0836
```

The baseline option changes only production `AppMenuController.swift` in the temporary package, retaining the same regression tests. On 2026-10-31 the four suites report 42 cases, with 41 passing, one existing opt-in case skipped and no failures; all ten new positioning cases pass. The same tests compile against `7b3a0836` and fail six positioning cases with 19 assertions. The other suites remain green. These are behavioral assertion failures, not extraction or dependency errors.

## Boundaries

Tests use the available macOS display configuration and do not initiate a Spaces fullscreen transition. They inspect real window frames immediately after presentation; they do not load live sticker packs or send network mutations. This fix changes only the upper vertical bound for existing non-fullscreen adjustment. Fullscreen behavior, horizontal menu-placement policy, menu actions and pack contents are unchanged. Temporary copied dependencies and compilation outputs are removed after each run.
