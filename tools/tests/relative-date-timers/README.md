# Relative date update regression checks

Relative date entities in messages and chat-list previews should update at the
next change of their displayed value. The old 1/60/1800-second repeating interval
was selected once, and the last relative entity overwrote all preceding ones.

Run on macOS with Swift/Xcode:

```sh
python3 tools/tests/relative-date-timers/run.py
python3 tools/tests/relative-date-timers/run.py --configuration release
python3 tools/tests/relative-date-timers/compare.py
python3 tools/tests/relative-date-timers/compare.py --baseline
```

The final command intentionally exits with status 1 and reports five baseline
failures. `--output <directory>` on either runner saves logs, input hashes or
comparison JSON. No account, network access or native framework setup is needed.

## What is exercised

The XCTest runner copies the production `RelativeDateTimeEntity.swift` and
`RelativeDateUpdateTimer.swift` without modifying them into a temporary package.
It runs the same tests registered in TelegramUtilsTests and MessageTextUtilsTests.
Foundation, AppKit, Dispatch timers, notification centers and main-queue delivery
are real. Other Telegram modules are excluded from this small package; this is
not a full-package or application test.

Twenty tests cover:

- Every second in a four-day window (345,601 starting points), checked against an
  independently evaluated version of the original rounding rules.
- Seconds/minutes/hours/days, future and past values, fractional seconds, zero,
  entity order, duplicate dates and empty inputs.
- 20,000 deterministic wide-range date/current-time pairs and Int32 endpoints,
  including differences that require Int64 arithmetic.
- Real one-shot timer rearming on the main queue, cancellation, deinitialization
  and cancellation from inside a callback.
- Forward/backward clock changes, wake notifications, superseded deadlines and
  delayed main-queue delivery.
- Boundaries crossed while constructing a row or executing its update callback.
  The callback-boundary test was observed failing before preserving the update's
  starting timestamp, then passing after that fix.

The comparison runner compiles the frozen original interval selector and relative
formatter, the current relative formatter branch and the production planner.
It also compiles both current row-setup slices against recording adapters to
check date collection, callback routing, empty inputs and weak ownership. These
adapters do not exercise complete ChatMessageItem or ChatListRowItem objects.

Reference fragments and the eight existing English format strings come from
upstream `35a0182637c683686a1db1d33ef48c8c3adb2e97` (see the exact commit in
Reference/provenance.json). They are immutable test fixtures, not language-pack
updates. 20,000 additional comparisons verify identical formatted output.

## Replayed before/after results

The clock starts at Unix time 1780000000 and advances one integer second per
step. Rows stay alive for the entire scenario; callbacks run on time. Counts
exclude exceptional refreshes caused by clock changes or wake notifications.

| Scenario | Before callbacks | After callbacks | Before stale seconds | After stale seconds |
|---|---:|---:|---:|---:|
| Date one second old, over one hour | 3600 | 119 | 0 | 0 |
| Date one week old, over one day | 48 | 1 | 0 | 0 |
| Event initially two hours away, through the event | 4 | 121 | 5337 | 0 |
| Dates 10 seconds and 2 hours old, recent first, over one hour | 2 | 111 | 3579 | 0 |
| Same dates, old first, over one hour | 3600 | 111 | 0 | 0 |

Thirty seconds before the future event, the old schedule still displays
`in 30 minutes`; the new schedule displays `in 30 seconds`. Future events need
more callbacks as they approach. Cutting that work would preserve the bug.

These are deterministic callback counts and text comparisons, not measured
hardware wakeups, CPU, scrolling performance, memory or battery savings. The
fresh-past scenario removes 96.7% of scheduled update callbacks; that percentage
must not be presented as an application-wide CPU or energy improvement.

## Scheduling design

Formatting and scheduling share the same unit/count value, including the existing
Float rounding. The planner brackets and bisects the next integer-second change
of that value without formatting localized strings or scanning every second.
It chooses the earliest deadline across the dates. One wall-clock Dispatch timer
per affected row is rearmed after updates; rows without relative entities create
no timer.

The first deadline uses the timestamp captured before row formatting. Subsequent
deadlines use the timestamp captured before the update callback, so boundaries
crossed during either operation are refreshed promptly. Early timer delivery is
checked against the deadline. Wake and system-clock changes force a refresh;
invalidation cancels the timer and removes observers.

See Apple's documentation for [wall-clock Dispatch timers](https://developer.apple.com/documentation/dispatch/dispatchsourcetimer)
and [system-clock change notifications](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nssystemclockdidchange).

## Integration still to check

Open a signed-in client with messages containing multiple relative date entities,
verify the chat and preview around unit boundaries, switch away/back, edit the
message and close its screen. Confirm text selection/context menus and item
lifetime. Unit tests and recording adapters do not replace that check.
