import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import DateUtils
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ShortPeerRow
import AvatarUI
import TelegramMediaUtils
import AlertsUI
import LocalAnimations
import MessageTextUtils
import AppAnalytics

private enum CommunityAddVisibility: Equatable {
    case visible
    case hidden
    public var isVisible: Bool { return self == .visible }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let selectVisibility: (CommunityAddVisibility) -> Void
    public init(context: (any AccountContextProtocol), selectVisibility: @escaping (CommunityAddVisibility) -> Void) {
        self.context = context
        self.selectVisibility = selectVisibility
    }
}

private struct State: Equatable {
    public var peer: EnginePeer?
    public var memberCount: Int32?
    public var visibility: CommunityAddVisibility = .visible
    public var isSaving: Bool = false
}

private let _id_peer = InputDataIdentifier("_id_peer")
private let _id_visible = InputDataIdentifier("_id_visible")
private let _id_hidden = InputDataIdentifier("_id_hidden")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    if let peer = state.peer {
        let status: String?
        if let count = state.memberCount, count > 0 {
            status = strings().communityAddMembersOther(Int(count))
        } else {
            status = nil
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, height: 62, photoSize: NSMakeSize(50, 50), status: status, inset: NSEdgeInsets(left: 20, right: 20), viewType: .singleItem)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityAddChatVisibility), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_visible, data: .init(name: strings().communityAddVisible, color: theme.colors.text, type: .selectableLeft(state.visibility == .visible), viewType: .firstItem, enabled: !state.isSaving, description: strings().communityAddVisibleInfo, action: {
        arguments.selectVisibility(.visible)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_hidden, data: .init(name: strings().communityAddHidden, color: theme.colors.text, type: .selectableLeft(state.visibility == .hidden), viewType: .lastItem, enabled: !state.isSaving, description: strings().communityAddHiddenInfo, action: {
        arguments.selectVisibility(.hidden)
    })))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityAddVisibilityFooter), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

public func CommunityAddController(_ context: (any AccountContextProtocol), communityId: PeerId, peerId: PeerId, completed: @escaping () -> Void) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    var close: (() -> Void)? = nil

    let arguments = Arguments(context: context, selectVisibility: { v in
        updateState { var c = $0; if !c.isSaving { c.visibility = v }; return c }
    })

    actionsDisposable.add(combineLatest(
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.CachedData(id: peerId))
    ).start(next: { peer, cachedData in
        var memberCount: Int32? = nil
        if let cachedData = cachedData as? CachedChannelData {
            memberCount = cachedData.participantsSummary.memberCount
        } else if let cachedData = cachedData as? CachedGroupData, let participants = cachedData.participants {
            memberCount = Int32(participants.participants.count)
        }
        updateState { var c = $0; c.peer = peer; c.memberCount = memberCount; return c }
    }))
    context.account.viewTracker.forceUpdateCachedPeerData(peerId: peerId)

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().communityAddTitle, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .communityAddChat
    controller.onDeinit = { actionsDisposable.dispose() }

    let performAdd: () -> Void = {
        let state = stateValue.with { $0 }
        if state.isSaving || state.peer == nil { return }
        updateState { var c = $0; c.isSaving = true; return c }
        actionsDisposable.add((context.engine.peers.toggleCommunityPeerLink(communityId: communityId, peerId: peerId, action: .link(visible: state.visibility.isVisible)) |> deliverOnMainQueue).start(error: { error in
            switch error {
            case .requestCreated:
                close?(); completed()
            case .peersTooMuch:
                updateState { var c = $0; c.isSaving = false; return c }
                alert(for: context.window, info: strings().communityAddErrorLimitReached)
            case .adminRequired:
                updateState { var c = $0; c.isSaving = false; return c }
                alert(for: context.window, info: strings().communityAddErrorAdminRequired)
            case .generic:
                updateState { var c = $0; c.isSaving = false; return c }
                alert(for: context.window, info: strings().communityAddErrorGeneric)
            case let .serverProvided(text):
                updateState { var c = $0; c.isSaving = false; return c }
                alert(for: context.window, info: text)
            }
        }, completed: {
            close?(); completed()
        }))
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().communityAddConfirm, accept: {
        performAdd()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 400))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().communityAddTitle)

    close = { [weak modalController] in modalController?.close() }
    return modalController
}
