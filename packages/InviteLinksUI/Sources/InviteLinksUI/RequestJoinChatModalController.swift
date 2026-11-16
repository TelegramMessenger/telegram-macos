import Cocoa

import Foundation
import TGUIKit
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import ShortPeerRow
import LocalAnimations
import InAppSettings
import ColorPalette
import DateUtils
import TelegramIconsTheme
import InputView
import InputTextView
import SwiftSignalKit
import Postbox
import TelegramCore
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {
    let flags: ExternalJoiningChatState.Invite.Flags
    let title: String
    let about: String?
    let photoRepresentation: TelegramMediaImageRepresentation?
    let participantsCount: Int32
    let isChannelOrMegagroup: Bool
    
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
  
    // entries
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("value"), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
        return RequestJoinChatRowItem(initialSize, stableId: stableId, context: arguments.context, photo: state.photoRepresentation, title: state.title, about: state.about, participantsCount: Int(state.participantsCount), flags: state.flags, isChannelOrMegagroup: state.isChannelOrMegagroup, viewType: .singleItem)
    }))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("about"), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
        return GeneralBlockTextRowItem(initialSize, stableId: stableId, viewType: .singleItem, text: state.flags.isChannel ? strings().requestJoinDescChannel : strings().requestJoinDescGroup, font: .normal(.text), color: theme.colors.text)
    }))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func RequestJoinChatModalController(context: any AccountContextProtocol, joinhash: String, invite: ExternalJoiningChatState, interaction:@escaping(Peer)->Void) -> InputDataModalController {
    return RequestJoinChatModalController(context: context, joinhash: joinhash, invite: invite, analyticsContext: nil, interaction: interaction)
}

public func RequestJoinChatModalController(context: any AccountContextProtocol, joinhash: String, invite: ExternalJoiningChatState, analyticsContext: AnalyticsContext?, interaction: @escaping (Peer) -> Void) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let action = InviteJoinAction()


    switch invite {
    case let .invite(state):

        let initialState = State(flags: state.flags, title: state.title, about: state.about, photoRepresentation: state.photoRepresentation, participantsCount: state.participantsCount, isChannelOrMegagroup: state.flags.isChannel && state.flags.isBroadcast)
        
        var close:(()->Void)? = nil
        
        let statePromise = ValuePromise(initialState, ignoreRepeated: true)
        let stateValue = Atomic(value: initialState)
        let _: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify (f))
        }

        let arguments = Arguments(context: context)
        
        
        
        let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
            return InputDataSignalValue(entries: entries(state, arguments: arguments))
        }
        
        let controller = InputDataController(dataSignal: signal, title: state.title)
        controller.analyticsScreen = .linkJoinRequest
        controller.analyticsContext = origin
        
        controller.onDeinit = {
            action.close()
        }

        let modalInteractions = ModalInteractions(acceptTitle: strings().requestJoinButton, accept: { [weak controller] in
            _ = controller?.returnKeyAction()
        }, singleButton: true)
        
        let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, closeHandler: { finish in
            action.close()
            finish()
        })
        modalController.analyticsContext = origin
        
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
            modalController?.close()
        })
        
        close = { [weak modalController] in
            action.close()
            modalController?.modal?.close()
        }
        
        controller.afterTransaction = { controller in
            
        }
        
        controller.returnKeyInvocation = { _, _ in
            guard let attempt = action.begin(), let takeResult = action.detach(attempt) else { return .default }
            let presentation = origin.beginPresentation()
            defer { presentation.end() }
            close?()
            _ = performInviteJoin(context: context, hash: joinhash, window: context.window, analyticsContext: origin, requestSentAsSuccess: true, takeResult: takeResult, close: {}, interaction: interaction)
            return .default
        }

        return modalController
    default:
        fatalError("I thought it's impossible.")
    }
    
}
