import Cocoa
import TGUIKit
import SwiftSignalKit
import InAppSettings
import InputDataUI
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import FilePanels

private final class Arguments {
    let select: (String) -> Void
    let selectCustom: () -> Void

    init(select: @escaping (String) -> Void, selectCustom: @escaping () -> Void) {
        self.select = select
        self.selectCustom = selectCustom
    }
}

private struct State: Equatable {
    var settings: AutomaticMediaDownloadSettings
}

private let _id_default = InputDataIdentifier("default")
private let _id_temporary = InputDataIdentifier("temporary")
private let _id_custom = InputDataIdentifier("custom")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    let defaultFolder = AutomaticMediaDownloadSettings.defaultSettings.downloadFolder
    let temporary = state.settings.usesTemporaryDownloadFolder
    let isDefault = !temporary && URL(fileURLWithPath: state.settings.downloadFolder).standardizedFileURL == URL(fileURLWithPath: defaultFolder).standardizedFileURL
    let custom = !temporary && !isDefault

    entries.append(.sectionId(0, type: .normal))
    entries.append(.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: _id_default, data: .init(name: "System Downloads Folder", color: theme.colors.text, type: .selectable(isDefault), viewType: .firstItem, description: defaultFolder, action: { //TODOLANG DataAndStorage.DownloadFolder.Default
        arguments.select(defaultFolder)
    })))
    entries.append(.general(sectionId: 1, index: 1, value: .none, error: nil, identifier: _id_temporary, data: .init(name: "Temporary Folder", color: theme.colors.text, type: .selectable(temporary), viewType: .innerItem, action: { //TODOLANG DataAndStorage.DownloadFolder.Temporary
        arguments.select(AutomaticMediaDownloadSettings.temporaryDownloadFolder)
    })))
    entries.append(.general(sectionId: 1, index: 2, value: .none, error: nil, identifier: _id_custom, data: .init(name: "Custom Folder", color: theme.colors.text, type: .selectable(custom), viewType: .lastItem, description: custom ? state.settings.downloadFolder : nil, action: arguments.selectCustom))) //TODOLANG DataAndStorage.DownloadFolder.Custom
    entries.append(.desc(sectionId: 1, index: 3, text: .plain("Files in the temporary folder are removed when you log out of this account. Use Save As to keep a permanent copy."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem))) //TODOLANG DataAndStorage.DownloadFolder.TemporaryInfo
    entries.append(.sectionId(2, type: .normal))
    return entries
}

func DownloadFolderController(context: any AccountContextProtocol, settings: AutomaticMediaDownloadSettings) -> InputDataController {
    let actionsDisposable = DisposableSet()
    let initialState = State(settings: settings)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> ViewController?)?
    let select: (String) -> Void = { folder in
        actionsDisposable.add(updateMediaDownloadSettingsInteractively(postbox: context.account.postbox, {
            $0.withUpdatedDownloadFolder(folder)
        }).start())
    }
    let arguments = Arguments(select: select, selectCustom: {
        selectFolder(for: bestWindow(context, getController?()), completion: select)
    })

    actionsDisposable.add((automaticDownloadSettings(postbox: context.account.postbox) |> deliverOnMainQueue).start(next: { settings in
        updateState { current in
            var current = current
            current.settings = settings
            return current
        }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    let controller = InputDataController(dataSignal: signal, title: strings().dataAndStorageDownloadFolder)
    getController = { [weak controller] in
        return controller
    }
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    return controller
}
