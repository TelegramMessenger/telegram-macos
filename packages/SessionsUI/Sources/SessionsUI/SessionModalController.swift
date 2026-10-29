import Cocoa
import Foundation
import SwiftSignalKit
import TelegramCore
import TGUIKit
import DateUtils
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import LocalAnimations
import ColorPalette
import TelegramIconsTheme
import Postbox

private final class Arguments {
    public let context: any AccountContextProtocol
    public let toggleChats:(Bool)->Void
    public let toggleIncomingCalls: (Bool) -> Void
    public let rename: (NSView) -> Void
    public init(context: any AccountContextProtocol, toggleChats:@escaping(Bool)->Void, toggleIncomingCalls: @escaping(Bool) -> Void, rename: @escaping(NSView) -> Void) {
        self.context = context
        self.toggleChats = toggleChats
        self.toggleIncomingCalls = toggleIncomingCalls
        self.rename = rename
    }
}

private struct State : Equatable {
    public let session: RecentAccountSession
    public let deviceModel: String?
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
//
    let icon = iconForSession(state.session)
    if let sticker = icon.1, state.session.isCurrent {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return SessionHeaderItem(initialSize, stableId: stableId, context: arguments.context, sticker: sticker, stickerSize: NSMakeSize(60, 60), bgColor: icon.2, modify: icon.3, name: state.deviceModel ?? state.session.deviceModel, date: DateUtils.string(forLastSeen: state.session.activityDate), rename: arguments.rename)
        }))
        index += 1
    } else if let sticker = icon.1 {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: nil, comparable: nil, item: { initialSize, stableId in
            
            let attr: NSMutableAttributedString = .init()
            
            _ = attr.append(string: state.session.deviceModel, color: theme.colors.text, font: .medium(.title))
            _ = attr.append(string: "\n", color: theme.colors.text, font: .medium(.title))
            _ = attr.append(string: DateUtils.string(forLastSeen: state.session.activityDate), color: theme.colors.listGrayText, font: .normal(.text))

            return SessionsHooks.shared.makeStickerHeaderItem(initialSize, stableId, arguments.context, sticker, attr, NSMakeSize(60, 60), icon.2, icon.3)
        }))
        index += 1

    }
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("application"), data: InputDataGeneralData(name: strings().sessionPreviewApp, color: theme.colors.text, type: .context(state.session.appName + ", " + state.session.appVersion), viewType: state.session.ip.isEmpty ? .singleItem : .firstItem, enabled: true)))
    index += 1
    
    if !state.session.ip.isEmpty {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("ip"), data: InputDataGeneralData(name: strings().sessionPreviewIp, color: theme.colors.text, type: .context(state.session.ip), viewType: .innerItem, enabled: true)))
        index += 1
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("location"), data: InputDataGeneralData(name: strings().sessionPreviewLocation, color: theme.colors.text, type: .context(state.session.country), viewType: .lastItem, enabled: true)))
        index += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().sessionPreviewIpDesc), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1

    }

    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().sessionPreviewAcceptHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1


    
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("secret"), data: InputDataGeneralData(name: strings().sessionPreviewAcceptSecret, color: theme.colors.text, type: .switchable(state.session.flags.contains(.acceptsSecretChats)), viewType: .firstItem, enabled: true, action: {
        arguments.toggleChats(!state.session.flags.contains(.acceptsSecretChats))
    })))
    index += 1
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("calls"), data: InputDataGeneralData(name: strings().sessionPreviewAcceptCalls, color: theme.colors.text, type: .switchable(state.session.flags.contains(.acceptsIncomingCalls)), viewType: .lastItem, enabled: true, action: {
        arguments.toggleIncomingCalls(!state.session.flags.contains(.acceptsIncomingCalls))
    })))
    index += 1
    
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func SessionModalController(context: any AccountContextProtocol, session: RecentAccountSession) -> InputDataModalController {

    var close:(()->Void)? = nil
    var isUpdating = false
    var deviceModelUpdates = 0
    let deviceModelDisposable = renamedDeviceModel.get().start(next: { _ in
        deviceModelUpdates += 1
    })

    let updateSession: (Signal<Never, UpdateSessionError>) -> Void = { signal in
        guard !isUpdating else {
            return
        }
        isUpdating = true
        var finished = false
        let signal = signal |> afterDisposed {
            Queue.mainQueue().async {
                if !finished {
                    isUpdating = false
                    context.activeSessionsContext.loadMore()
                }
            }
        }
        _ = showModalProgress(signal: signal, for: context.window).start(error: { _ in
            finished = true
            isUpdating = false
            context.activeSessionsContext.loadMore()
            alert(for: context.window, info: strings().unknownError)
        }, completed: {
            finished = true
            isUpdating = false
        })
    }

    let arguments = Arguments(context: context, toggleChats: { updated in
        updateSession(context.activeSessionsContext.updateSessionAcceptsSecretChats(session, accepts: updated))
    }, toggleIncomingCalls: { updated in
        updateSession(context.activeSessionsContext.updateSessionAcceptsIncomingCalls(session, accepts: updated))
    }, rename: { source in
        showModal(with: RenameDeviceController(context: context), for: context.window, morphSource: { [weak source] in
            return source
        })
    })
    
    let signal = combineLatest(context.activeSessionsContext.state, renamedDeviceModel.get())
    |> map { state, deviceModel in
        return State(session: state.sessions.first(where: { $0.hash == session.hash }) ?? session, deviceModel: session.isCurrent ? deviceModel : nil)
    }
    |> distinctUntilChanged
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().sessionPreviewTitle)
    
    let modalInteractions: ModalInteractions
    if session.isCurrent {
        modalInteractions = ModalInteractions(acceptTitle: strings().modalOK, accept: {
            close?()
        }, drawBorder: false, height: 50, singleButton: true)
    } else {
        modalInteractions = ModalInteractions(acceptTitle: strings().sessionPreviewTerminateSession, accept: {
            verifyAlert_button(for: context.window, information: strings().recentSessionsConfirmRevoke, successHandler: { _ in
                _ = showModalProgress(signal: context.activeSessionsContext.remove(hash: session.hash), for: context.window).start(error: { error in
                    let text: String
                    switch error {
                    case .freshReset:
                        text = strings().recentSessionsErrorFreshReset
                    case .generic:
                        text = strings().unknownError
                    }
                    alert(for: context.window, info: text)
                }, completed: {
                    close?()
                })
            })
        }, singleButton: true)
    }
    
    DispatchQueue.main.async {
        modalInteractions.updateDone { button in
            if session.isCurrent {
                button.set(background: theme.colors.accent, for: .Normal)
            } else {
                button.set(background: theme.colors.redUI, for: .Normal)
            }
        }
    }
    
    controller.onDeinit = {
        deviceModelDisposable.dispose()
    }

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, closeHandler: { _ in
        close?()
    })
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close(animationType: deviceModelUpdates > 1 ? .noMorph : .common)
    }
    
    /*

     */
    
    return modalController
    
}


/*
 
 */



