# Telegram App Events

One event vocabulary for every Telegram client, so usage can be compared across macOS, iOS, Android, Desktop and Web without per-client mapping.

**Current macOS status:** the hub defaults to disabled and requires explicit account-bound collection scopes. The core rejects unscoped legacy logging and enforces revocable account-store grants at persistence and dispatch. Payloads use generated schema validation before logging and enqueueing. Immutable privacy contexts now travel through the main chat attachment, paste, drop-preview, rich-editor and native-picker handoffs; broader UI propagation and native verification remain incomplete. The draft `chat.media_compose` task recorder preserves acquisition origin and aggregates local submission results, with partial entry-to-preview and observed-send wiring. Direct Shift-drop also has observed-send wiring; preview paste/drop additions, removal/reorder and basic options have partial wiring. Known editor results/confirmed discards and preview recovery also have partial wiring; remaining child outcomes and native route verification are incomplete. Do not enable collection until the secret-chat exclusion and account/queue isolation gates in [PLAN.md](PLAN.md) pass.

## Files

| File | What it is |
|---|---|
| [RULES.md](RULES.md) | Naming rules. Read first. |
| [PLAN.md](PLAN.md) | Current audit, unconditional secret-chat exclusion, interaction scenarios, implementation order and verification gates. Read before implementation. |
| [events.yaml](events.yaml) | The registry: every event, screen, menu, setting and flow. The source of truth. |
| [IMPLEMENTING.md](IMPLEMENTING.md) | The behavior contract a client implements. |
| [examples/macos-peer-info-visibility.md](examples/macos-peer-info-visibility.md) | One screen wired end to end on macOS. |
| [fixtures/flows.json](fixtures/flows.json) | Conformance cases; every client's tests must pass them. |
| [generated/events.json](generated/events.json) | The resolved registry for code generation in any language. Do not edit. |
| [tools/tg_events.py](tools/tg_events.py) | `lint` checks names against the rules; `gen` writes `generated/events.json` (and Swift for macOS); `coverage` checks that every screen in the macOS code has a decision. |
| [tools/macos_inventory.py](tools/macos_inventory.py) | Finds every controller, `InputDataController` screen, window, alert and file panel in the macOS code. |
| [coverage/macos-interactions.md](coverage/macos-interactions.md) | Source-audited media routes, expected semantics, exclusion matrix and per-route test evidence requirements. |
| [coverage/macos.yaml](coverage/macos.yaml) | The decision for every item in the macOS inventory: which registry screens it shows, or why it is not a screen. |
| [coverage/macos.md](coverage/macos.md) | Generated report: screens and their sources, ignored items, registry screens macOS does not have. |
| [tools/test_tg_events.py](tools/test_tg_events.py) | Tests for lint, the inventory scanner and the coverage check. |

## Changing names

```sh
pip install pyyaml
python3 tools/tg_events.py lint
python3 tools/tg_events.py gen
```

Edit `events.yaml`, run `lint` until it passes, run `gen`, and send the change for review. Add names; never rename or reuse them (RULES.md §8).

macOS also keeps its screen coverage complete. After adding, removing or renaming a screen in the code:

```sh
python3 tools/tg_events.py coverage
python3 tools/tg_events.py gen --check --swift ../../packages/AppAnalytics/Sources/AppAnalytics/AnalyticsRegistry.swift
python3 -m unittest discover -s tools -p 'test_*.py'
```

`coverage` fails when a controller, screen function, window, alert or file panel has no entry in `coverage/macos.yaml`, when an entry points to code that no longer exists, or when it names a screen that is not in `events.yaml`. It does not verify interaction-route coverage or privacy behavior. A mapped screen can still be excluded from collection by policy.

For a subclass that inherits its runtime screen tags, its mapping may declare `tags_from: "class:Module/BaseController"`. The tag check verifies that this is its unambiguous declared base class and that the parent also maps those screens, then checks the actual source tags through that chain. Missing, unrelated, ambiguous or cyclic references fail. Comments and string examples do not satisfy a tag check. This is a source audit; it does not prove that every override calls the inherited tagging code or that runtime privacy propagation is correct.

macOS also regenerates its Swift registry:

```sh
python3 tools/tg_events.py gen --swift ../../packages/AppAnalytics/Sources/AppAnalytics/AnalyticsRegistry.swift
```

## Implementing in another client with an AI agent

Copy this folder into your repo and give your agent this prompt:

> Implement Telegram App Events in this app following `docs/analytics`. Read `README.md`, `PLAN.md`, `RULES.md`, `IMPLEMENTING.md` and `examples/macos-peer-info-visibility.md` first. Keep collection disabled. First implement and test the exclusion policy, including secret contexts, inherited child surfaces, account changes, legacy transport bypasses and persistent queues. Generate typed constants from the reviewed registry; never use string literals for names. Build the flow recorder and run every case in `fixtures/flows.json`, plus the privacy and journey tests in PLAN.md. Build both the screen inventory and interaction-scenario ledger. Start route instrumentation with attach, paste and drop, preserving origin through completion, cancellation and retry. Propose missing registry names for review before using them. Done means the expanded IMPLEMENTING.md §8 checklist passes; enablement is a separate decision.
