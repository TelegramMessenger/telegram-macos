# Birthday picker initial value regression

Run from the repository root on macOS with Python 3 and the installed Swift/XCTest toolchain:

```sh
python3 -I tools/tests/birthday-picker-initial-value/run.py
python3 -I tools/tests/birthday-picker-initial-value/run.py --revision c64a3ea7 --expect-regression
```

Optional `--output <new-directory>` retains `result.json`, `build.log`, and `tests.log`. The directory must not exist, including an empty directory. Without it, no build products or evidence remain. The runner strips inherited `GIT_*` variables, reads a requested revision through `git -C ... show`, builds with two jobs in an automatically cleaned temporary package, and places compiler/SwiftPM caches there. It does not resolve third-party dependencies, launch Telegram, open windows, or access account data.

## Production source coverage

The runner extracts the actual birthday action from `EditAccountInfoController.swift`, the hook property from `SettingsNavigationHooks.swift`, its installation from `SettingsHooksInstall.swift`, and the add-birthday action from `SelectivePrivacySettingsController.swift`. The same fixture compiles both old and new hook signatures; the production action, not a copied initializer, determines the selected date.

It also compiles the full `CalendarController.swift`, `CalendarMonthInteractions`, `CalendarMonthStruct`, the month controller initializer and previous/next eligibility properties, the existing `TelegramBirthday.dateForPicker` and `Date.birthday` conversion bodies, and the unmodified Objective-C `CalendarUtils.h/.m` sources. Imports and access modifiers are adjusted for the isolated test target; decision bodies, date construction, the real clock, and callback ordering are unchanged. `result.json` includes whole-file and extracted-block SHA-256 hashes.

Disclosed doubles replace TGUIKit views/navigation, modal presentation, the Settings editor row/state/context, and the account-update callback. The month controller's drawing/header methods are omitted. No UI is rendered; a recorded callback stands in for a server update. Foundation/Gregorian calendar operations and Objective-C CalendarUtils are real. The suite proves initialization and callback behavior, not visual acceptance or a full application build.

## Cases and negative control

Twelve XCTest cases cover saved day/month/year and highlight, no-year birthdays, February 29 with and without a year across four time zones, absent/invalid birthday fallback without mutation, reopening with updated state, cancel and retained callbacks, explicit selection and duplicate suppression, month browsing, privacy setup, normal calendar initialization, future/limited-date constraints, and range selection.

The fixed source passes all twelve tests. The original `c64a3ea7` source builds successfully and fails five cases with 111 assertion failures: the saved birthday is replaced by today, including the optional-year/leap-day cases and the eventual explicit selection's month/year. Seven non-regression cases still pass. `--expect-regression` accepts only a successful compile followed by XCTest assertion failures; compiler failure is never counted as reproduction.

The older `tools/tests/birthday-ui` save-lifecycle fixture is adapted to the new hook signature. Its fake calendar still ignores the initial date; initialization assertions belong to this suite. That older dependency-backed suite is not required by this standalone runner.
