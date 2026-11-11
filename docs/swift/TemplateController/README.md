# Template Controller

Read this before building a new screen. Most list, settings and form screens are an `InputDataController` built from
[TemplateController.swift](TemplateController.swift). The template is not part of any target; copy it, never import it.

## Data Flow

`State` → `entries(state, arguments)` → `[InputDataEntry]` → `InputDataController` table

- `State` is an `Equatable` struct with everything the screen shows
- `Arguments` holds the context and the action closures rows call
- `entries` is a pure function that turns the state into rows
- `updateState` is the only way to change the state; the table diffs and animates the result

## Steps

1. Pick the feature package the screen belongs to (see "Adding a Feature" in [AGENTS.md](../../../AGENTS.md)) and copy `TemplateController.swift` into its `Sources/<Package>/`
2. Rename `TemplateController` and `TemplateModalController` to the screen name, e.g. `MyScreenController`. Keep `Arguments`, `State` and `entries` private
3. Remove the imports you do not use and make sure the package declares every module you keep, nothing more
4. Put the screen's data in `State` and the row actions in `Arguments`
5. Build the rows in `entries`
6. Load data into the state and add every subscription to `actionsDisposable`
7. Replace the `" "` title with a string and open the screen

## Rows

Each section starts with `.sectionId` and every row takes the current `sectionId` and an increasing `index`.

```swift
entries.append(.sectionId(sectionId, type: .normal))
sectionId += 1

entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().myScreenHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
index += 1

entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add, data: .init(name: strings().myScreenAdd, color: theme.colors.accent, type: .next, viewType: .singleItem, action: arguments.add)))
index += 1
```

| Entry | Use it for |
|---|---|
| `.sectionId(_, type:)` | Section break: `.normal`, `.legacy`, `.custom(height)`, `.customModern(height)` |
| `.desc` | Header or footer text: `.plain`, `.markdown(_, linkHandler:)`, `.attributed` |
| `.general` | Tappable row; `type:` sets the accessory: `.next`, `.switchable(Bool)`, `.selectable(Bool)`, `.context(String)`, `.loading`, `.none` |
| `.input` | Text field, read back through `validateData` or `updateDatas` |
| `.selector`, `.dateSelector`, `.dataSelector` | Value pickers |
| `.custom` | Any `TableRowItem`, for rows `.general` cannot draw |
| `.search`, `.loading` | Search field, loading row |

- Identifiers are file-level `InputDataIdentifier("_id_name")` constants; list rows use a function such as `_id_peer(_ peerId: PeerId)`
- `viewType` places the row inside its block: `.singleItem`, `.firstItem`, `.innerItem`, `.lastItem`, `.textTopItem`, `.textBottomItem`. For a list use `bestGeneralViewType(items, for: item)`
- A `.custom` row redraws only when `equatable` changes: `equatable: InputDataEquatable(state.value)`

## Loading Data

```swift
actionsDisposable.add(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)).startStrict(next: { peer in
    updateState { current in
        var current = current
        current.peer = peer
        return current
    }
}))
```

## Forms

Pass `hasDone: true` and validate the input values:

```swift
let controller = InputDataController(dataSignal: signal, title: strings().myScreenTitle, validateData: { data in
    if data[_id_name]?.stringValue?.isEmpty ?? true {
        return .fail(.fields([_id_name: .shake]))
    }
    return .success(.navigationBack)
}, hasDone: true)
```

## Presenting

- Push: `context.bindings.rootNavigation().push(XController(context: context))`
- Modal: `showModal(with: XModalController(context: context), for: context.window)`; the modal variant from the template adds the accept button and the close header
- A screen in another package is opened through a `FeatureNavigationHooks` closure, never by importing that package
- If the screen needs something only the app has, add a hooks struct to the package (see [AGENTS.md](../../../AGENTS.md))

## Rules

- No code comments; new user-facing strings get a `//TODOLANG` marker until they are localized
- Use `theme.colors` and `theme.icons`, never hardcoded colors or images
- In a modal with a header, `InputDataController` draws a leading `.normal` section 10px tall instead of 20px; keep starting screens with `.sectionId(0, type: .normal)`
- Public entry points take `any AccountContextProtocol`, not the app `AccountContext`

## Examples

- `packages/GroupsInCommonUI/Sources/GroupsInCommonUI/GroupsInCommonViewController.swift` - Peer list and its hooks
- `packages/SettingsUI/Sources/SettingsUI/LiteModeController.swift` - Switches and a `.custom` row
- `packages/SettingsUI/Sources/SettingsUI/NotificationSoundController.swift` - Selectable list
- `packages/SettingsUI/Sources/SettingsUI/EditThemeController.swift` - Input fields in a modal
- `packages/PasskeysUI/Sources/PasskeysUI/PasskeysController.swift` - Custom row item and view
- `packages/InputDataUI/Sources/InputDataUI/InputDataControllerEntries.swift` - Every entry type and its parameters
