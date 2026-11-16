import Foundation

import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputDataUI
import Localization
import TelegramCallsCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramIconsTheme
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {
    public var title: String
    public var peer: PeerEquatable
    public var participantsCount: Int
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
        return JoinVoiceChatAlertRowItem(initialSize, stableId: stableId, account: arguments.context.account, peer: state.peer.peer, title: state.title, participantsCount: state.participantsCount)
    }))
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func JoinVoiceChatAlertController(context: any AccountContextProtocol, groupCall: GroupCallPanelData, peer: Peer, join: @escaping()->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    var close:(()->Void)? = nil
    
    let initialState = State(title: groupCall.info?.title ?? peer.displayTitle, peer: PeerEquatable(peer), participantsCount: groupCall.participantCount)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let arguments = Arguments(context: context)
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().chatVoiceChatJoinLinkTitle)
    controller.analyticsScreen = .groupCallInvitation
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        join()
        close?()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().chatVoiceChatJoinLinkOK, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(250, 250))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}


