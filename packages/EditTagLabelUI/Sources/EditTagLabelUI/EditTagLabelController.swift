import Foundation
import Postbox
import TelegramCore
import Cocoa
import TGUIKit
import SwiftSignalKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramTheme
import ColorPalette
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {
    public var value: String?
}

private let _id_input = InputDataIdentifier("_id_input")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.value), error: nil, identifier: _id_input, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().chatReactionEditTagPlaceholder, filter: { $0 }, limit: 12))
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatReactionContextEditTagInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func EditTagLabelController(context: any AccountContextProtocol, reaction: MessageReaction.Reaction, label: String?, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }

    let actionsDisposable = DisposableSet()

    let initialState = State(value: label)
    
    var close: (()->Void)? = nil
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let arguments = Arguments(context: context)
    
    let signal = origin.preservingPresentation(statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().chatReactionContextEditTag)
    controller.analyticsContext = origin
    controller.analyticsScreen = .chatSavedTagName
    
    controller.updateDatas = { data in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        updateState { current in
            var current = current
            current.value = data[_id_input]?.stringValue
            return current
        }
        return .none
    }
    
    controller.validateData = { _ in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let signal = context.engine.stickers.setSavedMessageTagTitle(reaction: reaction, title: stateValue.with { $0.value })
        _ = origin.preservingPresentation(signal).start()
        close?()
        _ = origin.preservingPresentation(showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 0.5)).start()
        return .none
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    modalController.analyticsContext = origin

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}




