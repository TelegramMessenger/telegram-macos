# Focus macOS CI

The separate `.github/workflows/focus-macos.yml` workflow adds three visible PR
checks: native tests, a Debug extension build, and a Release extension build.
It runs for changes to the Focus implementation, its test inputs, or the workflow.
It also supports manual dispatch once the workflow is available on the default
branch. The workflow checks out GitHub's PR merge revision, so failures can expose
integration problems with the target branch as well as the proposed changes.

The jobs use GitHub's `macos-26` image and its default Xcode. Exact macOS, Xcode,
Swift and tested Git revision are recorded in the logs. Each job uploads logs
for seven days, including on failure. There are no signing secrets or write
permissions. Only the pinned Telegram-iOS submodule is fetched for Postbox and
SwiftSignalKit tests; unrelated native dependencies are not downloaded.

## Coverage

- Swift package policy, persistence and installation identity tests.
- Actual App Intents types, entity queries, display redaction and saved rules.
- Darwin record locks, startup denial, lock/unlock, crashes, copies and channels.
- New `../focus-sandbox-admission/run.py`: the production extension reader inside
  a test `.appex`, with host file reads explicitly denied by macOS sandbox rules.
- Verified application lock-state transitions and catalogue projection.
- Chat-list predicates, notification folder membership and Focus-empty folders,
  using source declarations from the pinned Postbox revision.
- Standalone extension replacement and cooperative retirement.
- Isolated production extension compilation and App Intents metadata validation
  in Debug and Release, including both arm64 and x86_64 Release binaries.

## Limits

The sandbox fixture deliberately uses a small command-line application and a
temporary shared directory. It does not establish signed App Group entitlement
behavior, system extension discovery, or behavior of System Settings' Focus editor.
The extension builds are unsigned and do not build or install the full Telegram
application. Open-editor cached names, real notifications, signed updates and
large-account performance still require separate integration checks.

A fork PR in the upstream repository may wait for a maintainer to approve its
workflow. A missing or waiting run is not a passing test result.
