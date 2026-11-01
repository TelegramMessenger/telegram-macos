import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import InputDataUI
import GeneralRows
import TelegramTheme
import Localization
import ApiCredentials
import TelegramContext

let renamedDeviceModel = ValuePromise<String?>(nil, ignoreRepeated: true)

private struct State : Equatable {
    var value: String?
    var systemDeviceModel: String?
}

private let _id_input = InputDataIdentifier("_id_input")

private func entries(_ state: State) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("DEVICE NAME"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem))) //TODOLANG
    index += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.value), error: nil, identifier: _id_input, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: state.systemDeviceModel ?? "", filter: { $0 }, limit: Int32(ApiEnvironment.deviceModelMaxLength)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("This name is shown in the list of active sessions on your other devices."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem))) //TODOLANG
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

func RenameDeviceController(context: any AccountContextProtocol) -> InputDataModalController {

    let initialState = State(value: ApiEnvironment.customDeviceModel, systemDeviceModel: ApiEnvironment.systemDeviceModel)

    var close: (()->Void)? = nil
    var saved: String? = nil

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let signal = (statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        return InputDataSignalValue(entries: entries(state))
    }

    let controller = InputDataController(dataSignal: signal, title: "Rename Device") //TODOLANG

    controller.updateDatas = { data in
        updateState { current in
            var current = current
            current.value = data[_id_input]?.stringValue
            return current
        }
        return .none
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        ApiEnvironment.customDeviceModel = state.value
        saved = ApiEnvironment.customDeviceModel ?? state.systemDeviceModel
        close?()
        return .none
    }

    controller.didDisappear = { _ in
        if let saved = saved {
            renamedDeviceModel.set(saved)
            context.activeSessionsContext.loadMore()
        }
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalSave, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
