# Widget interaction checks

The `chat-navigation` lab's `widgets` scenario checks actual chat widgets. It can
export their HTML, follow older loaded history, and run local control actions from
`actions.json`. These actions change the widget sandbox's local state. They do not
send chat messages.

Build Telegram Debug, quit the previous Debug instance, then launch:

```sh
open -n /path/to/Debug/Telegram.app --args \
  -PerfLab chat-navigation -PerfLabLabel widget-glitches \
  -PerfLabScenarios widgets -PerfLabPeerTitle "Widget Samples" \
  -PerfLabWidgetHistoryPasses 4 -PerfLabWidgetWait 1.5 \
  -PerfLabWidgetActions /absolute/path/to/tools/perflab/widget-glitches/actions.json \
  -PerfLabWidgetActionWait 0.5 \
  -PerfLabWidgetSources /tmp/widget-sources \
  -PerfLabOutput /tmp/widget-report
```

The group opens in its combined All topic. For Saved Messages replace the peer
title with `-PerfLabSavedMessages 1`. Omit `-PerfLabWidgetActions` for an opening and
sizing check without local clicks. `-PerfLabQuit` closes the app after the report.

Each matched widget records missing targets, height mismatches, the final sandbox
state, main-thread frame gaps, and captures before and after the sequence. Set
`-PerfLabWidgetCaptureActions 1` for a capture after every action; these diagnostic
captures add synchronous PNG work to the measured interval. Captures use layer
rendering, so they do not prove scanout smoothness or capture every native overlay.
Frame gaps include other work in the app; compare runs under similar system load.
The history pass count limits how often newly loaded rows are added to the check.

The exact chat payload repairs in `repaired/` can be prepared as standalone HTML
for WidgetBot. They preserve the original theme variables and local storage;
`repairs.json` records the original and repaired hashes. Two stopwatch and shortcut
variants are included because both versions appeared in the recorded chats.

```sh
python3 tools/perflab/widget-glitches/prepare-demo.py --out /tmp/widget-demo
```

Add `--bundled` to prepare the corresponding bundled demonstration variants.

Existing server messages retain their original HTML. Updating the bundled samples
does not rewrite those messages; send corrected HTML to WidgetBot to create new
widgets, then forward the results to Saved Messages. Keep Widget Samples read-only.

WidgetBot rejected the larger music and stopwatch repairs with
`INPUT_MEDIA_WIDGET_TOO_LARGE`. Their checked-in payloads are compacted below
4 KiB of gzip data while keeping their controls and theme behavior. Recheck
compressed size when expanding these demo payloads.
