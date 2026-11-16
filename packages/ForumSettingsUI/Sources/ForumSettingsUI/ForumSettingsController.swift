import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import InAppSettings
import LocalAnimations
import SidebarUI
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public let toggleForum: ()->Void
    public let selectMode: (ForumDisplayMode)->Void
    public init(context: any AccountContextProtocol, toggleForum: @escaping()->Void, selectMode: @escaping(ForumDisplayMode)->Void) {
        self.context = context
        self.toggleForum = toggleForum
        self.selectMode = selectMode
    }
}

private struct State : Equatable {
    public var isForum: Bool = false
    public var mode: ForumDisplayMode = .tabs
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_toggle = InputDataIdentifier("_id_toggle")
private let _id_monoforum = InputDataIdentifier("_id_monoforum")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return ForumSettingsHooks.shared.makeStickerHeaderItem(initialSize, stableId, arguments.context, LocalAnimatedSticker.topics, .initialize(string: strings().forumSettingsTopicInfo, color: theme.colors.listGrayText, font: .normal(.text)), NSMakeSize(120, 120), nil, nil)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

  
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_toggle, data: .init(name: strings().forumSettingsEnable, color: theme.colors.text, type: .switchable(state.isForum), viewType: .singleItem, action: arguments.toggleForum)))
    
    
    if state.isForum {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().forumSettingsDisplayAs), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_monoforum, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return ForumDisplayModeItem(initialSize, stableId: stableId, mode: state.mode, select: arguments.selectMode)
        }))
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().forumSettingsDisplayAsInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1

    }
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func ForumSettingsController(context: any AccountContextProtocol, peerId: PeerId) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    
    actionsDisposable.add(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)).start(next: { peer in
        if let peer {
            switch peer {
            case let .channel(channel):
                updateState { current in
                    var current = current
                    current.isForum = channel.flags.contains(.isForum)
                    if channel.flags.contains(.displayForumAsSidebar) {
                        current.mode = .sidebar
                    } else if channel.flags.contains(.displayForumAsTabs) {
                        current.mode = .tabs
                    } else {
                        current.mode = .list
                    }
                    return current
                }
            default:
                break
            }
        }
    }))
    
    let update:()->Void = {
        let state = stateValue.with { $0 }
        _ = showModalProgress(signal: context.engine.peers.setChannelForumMode(id: peerId, isForum: state.isForum, displayForumAsTabs: state.mode != .list, displayForumAsSidebar: state.isForum && state.mode == .sidebar), for: context.window).start()
    }

    let arguments = Arguments(context: context, toggleForum: {
        updateState { current in
            var current = current
            current.isForum = !current.isForum
            return current
        }
        update()
    }, selectMode: { mode in
        updateState { current in
            var current = current
            current.mode = mode
            return current
        }
        update()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().forumSettingsTitle, hasDone: false)
    controller.analyticsScreen = .peerInfoTopics
    
    controller.afterDisappear = {
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
    
}
