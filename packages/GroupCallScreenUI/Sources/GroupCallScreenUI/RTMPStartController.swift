import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import GeneralRows
import InputDataUI
import Localization
import TelegramContext
import TelegramTheme
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    let copyToClipboard: (String)->Void
    let toggleHideKey:()->Void
    init(context: any AccountContextProtocol, copyToClipboard: @escaping(String)->Void, toggleHideKey:@escaping()->Void) {
        self.context = context
        self.copyToClipboard = copyToClipboard
        self.toggleHideKey = toggleHideKey
    }
}

private struct State : Equatable {
    var credentials: GroupCallStreamCredentials?
    var error: String? = nil
    var hideKey: Bool = true
}

private let _id_server_url = InputDataIdentifier("_id_server_url")
private let _id_stream_key = InputDataIdentifier("_id_stream_key")
private let _id_loading = InputDataIdentifier("_id_loading")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
//
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().voiceChatRTMPInfo), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    if let credentials = state.credentials {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_server_url, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return GroupCallScreenUIHooks.shared.makeRTMPServerUrlItem(initialSize, stableId, strings().voiceChatRTMPServerURL, strings().contextAlertCopied, theme.colors.text, theme.colors.accent, credentials.url, arguments.context, .firstItem, false, {
                arguments.copyToClipboard(credentials.url)
            }, true, true, {
                arguments.copyToClipboard(credentials.url)
            }, .code(.title))
        }))
        index += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_stream_key, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return GroupCallScreenUIHooks.shared.makeRTMPStreamKeyItem(initialSize, stableId, strings().voiceChatRTMPStreamKey, strings().contextAlertCopied, theme.colors.text, theme.colors.accent, credentials.streamKey, arguments.context, .lastItem, false, {
                arguments.copyToClipboard(credentials.streamKey)
            }, true, true, {
                arguments.copyToClipboard(credentials.streamKey)
            }, .code(.title), state.hideKey, arguments.toggleHideKey)
        }))
        index += 1
        
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().voiceChatRTMPDesc), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    } else if let error = state.error {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(error), data: .init(color: theme.colors.redUI, viewType: .textBottomItem)))
        index += 1
    } else {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .singleItem)
        }))
    }

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func RTMPStartController(context: any AccountContextProtocol, peerId: PeerId, scheduleDate: Date?, completion: @escaping(PeerId, Date?, Bool)->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    var close:(()->Void)? = nil
    
    let arguments = Arguments(context: context, copyToClipboard: {  value in
        copyToClipboard(value)
        showModalText(for: context.window, text: strings().shareLinkCopied)
    }, toggleHideKey: {
        updateState { current in
            var current = current
            current.hideKey = !current.hideKey
            return current
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().voiceChatRTMPTitle)
    controller.analyticsScreen = .groupCallStreamSetup
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        completion(peerId, scheduleDate, true)
        return .success(.custom({
            close?()
        }))
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().voiceChatRTMPOK, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    let getSignal = context.engine.calls.getGroupCallStreamCredentials(peerId: EnginePeer.Id.init(peerId.toInt64()), isLiveStream: true, revokePreviousCredentials: false)
    
    actionsDisposable.add(getSignal.start(next: { credentials in
        updateState { current in
            var current = current
            current.credentials = credentials
            current.error = nil
            return current
        }
    }, error: { error in
        updateState { current in
            var current = current
            current.credentials = nil
            current.error = strings().unknownError
            return current
        }
    }))
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
}


