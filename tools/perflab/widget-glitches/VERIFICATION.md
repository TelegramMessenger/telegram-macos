# Widget repair verification — 26 October 2026

The supplied 12:03 and 12:07 recordings exposed visual failures that earlier scheduling and resting-height checks missed. Verification now includes native pixels during the first frames after input, cached native surfaces, and the complete repaired chat corpus.

## Final changes

- Survival Portuguese keeps consistent row insets and natural-height reveals without sliding its list panels.
- Packing keeps 20×20 checkboxes and full-width contained rows. Counts and the progress ring update immediately.
- Music restores emoji controls, holds header/control geometry stable, retains playlist nodes across track changes, and paints a changing waveform.
- Reviews, shortcut variants, Sprint, and the slot paytable no longer fade or slide their content on routine navigation. Meaningful game, keypress, answer, and celebration feedback remains.
- Both stopwatch variants show chart bars immediately and preserve them through pause/resume instead of rebuilding and replaying the chart.
- Explicit hidden-state rules prevent inactive panels and empty placeholders from occupying space. This fixes the observed Sprint empty-message overlap and Whack-a-mole menu/countdown overlap.
- Corresponding bundled examples and portable corpus samples contain the changes.

## Widget Bot

All 19 final repaired payloads have been accepted by `@asmico_widget_bot`, and every returned HTML file exactly matches its SHA-256 in `repairs.json`. The final thirteen replacements were posted at 12:54 PM; packing, Portuguese, and music replacements were posted at 12:29 PM. Use the latest returned version of each widget. Existing messages retain their previous HTML. Widget Samples remained read-only.

Exact message IDs and hashes are retained in [final-payload-map.json](evidence/2026-10-26-rescue/final-payload-map.json). All nineteen scripts pass syntax checks; gzip sizes are 3122–3968 bytes, below the 4096-byte payload limit.

## Verification

- Final Telegram Debug workspace build succeeded for arm64 macOS and ran in windowed mode.
- The final real-chat run matched all 19 exact final payloads and completed **144 actions with zero missing targets or bubble-height mismatches**. The scan covered 36 messages containing widgets, with zero script errors, dead sandboxes, or unavailable widgets.
- That run recorded 3137 main-thread frame samples, three scheduling gaps, no long hitch, and a worst gap of 33.332 ms. This is scheduling evidence for the tested sequences, not a universal display-deadline guarantee.
- Eight native core, media, and geometry tests passed in 26.267 seconds. Coverage includes actual pointer input, background execution, animation settlement, pause/resume, ancestor visibility, stale raster tiles, production binary/canvas protocol settings, and light/dark music rendering.
- Six additional native tests passed in 28.121 seconds. They cover stationary/opaque routine navigation, immediate stopwatch bars, **364 sampled states across 52 real-pointer actions**, and all 19 samples’ hidden elements.
- First-frame checks sample 0, 8, 16, 33, 66, 120, and 220 ms after input at widths 320 and 440. They check both fresh composed pixels and actual prepared IOSurface tile/canvas pixels: stable headers and controls, full-size checkbox ink, consistent row insets, contained content, painted artwork, and a nonblank waveform. The retained filmstrip shows representative prepared surfaces at four times.
- All 33 startup elements marked hidden have zero layout bounds and contribute no painted pixels across the nineteen samples.
- The same frame-independent packing/Portuguese checks against saved pre-repair HTML fail 42 assertions; repaired versions pass. This proves the basic UI no longer depends on animation frames to settle.
- Actual app screenshots confirmed the repaired appearance, changing waveform output, and accepted final Bot replies.

## Evidence and limits

Retained evidence is in [evidence/2026-10-26-rescue](evidence/2026-10-26-rescue/): native logs, first-frame filmstrip, complete motion audit, final interaction report, and payload hashes. Full temporary working evidence is in `/private/tmp/widget-rescue/`.

Native composition and prepared-surface captures verify the content submitted for display. They do not directly measure render-server scanout. Per-action app layer captures add PNG work and are used for layout evidence; the final scheduling run omits that overhead. The UI automation tool could not click embedded controls directly, so real-pointer coverage runs through native renderer tests. No speculative renderer production patch was added where the intermittent recorded core failure could not be reproduced.

Each logical change is committed locally. Nothing has been pushed.
