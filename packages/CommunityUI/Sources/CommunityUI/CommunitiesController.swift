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

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let createCommunity: () -> Void
    public let selectCommunity: (EnginePeer) -> Void
    public init(context: (any AccountContextProtocol), createCommunity: @escaping () -> Void, selectCommunity: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.createCommunity = createCommunity
        self.selectCommunity = selectCommunity
    }
}

private struct CommunityEntry: Equatable {
    public let peer: EnginePeer
    public let chatCount: Int
}

private struct State: Equatable {
    public var subjectPeer: EnginePeer?
    public var communities: [CommunityEntry] = []
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_create = InputDataIdentifier("_id_create")
private func _id_community(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_community_\(id.toInt64())")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    let subtitle: String
    if case let .channel(channel) = state.subjectPeer, case .broadcast = channel.info {
        subtitle = strings().communitiesSubtitleChannel
    } else if case .user = state.subjectPeer {
        subtitle = strings().communitiesSubtitleBot
    } else {
        subtitle = strings().communitiesSubtitleGroup
    }

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: InputDataEquatable(state.subjectPeer), comparable: nil, item: { initialSize, stableId in
        return CommunityModalHeaderItem(initialSize, stableId: stableId, context: arguments.context, peer: state.subjectPeer?._asPeer(), title: strings().communitiesTitle, subtitle: subtitle, communityStyle: true)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_create, data: .init(name: strings().communitiesCreateCommunity, color: theme.colors.accent, icon: theme.icons.peerInfoAddMember, type: .none, viewType: .singleItem, enabled: true, action: {
        arguments.createCommunity()
    })))
    index += 1

    // Communities already at the linked-peers cap can't take another chat (the server rejects with
    // COMMUNITY_PEERS_TOO_MUCH) — hide them from the picker.
    let peersLimit = Int(arguments.context.appConfiguration.getGeneralValue("community_peers_limit", orElse: 100))
    let availableCommunities = state.communities.filter { $0.chatCount < peersLimit }

    if !availableCommunities.isEmpty {
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communitiesAddToExisting), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        let items = availableCommunities
        for (i, item) in items.enumerated() {
            let viewType = bestGeneralViewType(items, for: i)
            let status: String = strings().communitiesChatsOther(Int(item.chatCount))
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_community(item.peer.id), equatable: InputDataEquatable(item), comparable: nil, item: { initialSize, stableId in
                return ShortPeerRowItem(initialSize, peer: item.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, status: status, inset: NSEdgeInsets(left: 20, right: 20), viewType: viewType, action: {
                    arguments.selectCommunity(item.peer)
                })
            }))
            index += 1
        }
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

public func CommunitiesController(_ context: (any AccountContextProtocol), peerId: PeerId) -> InputDataController {
    let actionsDisposable = DisposableSet()
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    var pop: (() -> Void)? = nil

    let arguments = Arguments(context: context, createCommunity: {
        showModal(with: CommunityCreateController(context, peerId: peerId, completed: {
            pop?()
        }), for: context.window)
    }, selectCommunity: { community in
        showModal(with: CommunityAddController(context, communityId: community.id, peerId: peerId, completed: {
            pop?()
        }), for: context.window)
    })

    actionsDisposable.add(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)).start(next: { peer in
        updateState { var c = $0; c.subjectPeer = peer; return c }
    }))

    let communitiesSignal = context.engine.peers.updatedCommunitiesState()
        |> mapToSignal { communitiesState -> Signal<[CommunityEntry], NoError> in
            let ids = communitiesState.communityIds ?? []
            if ids.isEmpty { return .single([]) }
            for id in ids { context.account.viewTracker.forceUpdateCachedPeerData(peerId: id) }
            return combineLatest(
                context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })),
                context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.CachedData(id: $0) }))
            ) |> map { peers, cachedDatas -> [CommunityEntry] in
                return ids.compactMap { id -> CommunityEntry? in
                    guard let maybePeer = peers[id], let peer = maybePeer else { return nil }
                    // Only communities where the user can add linked peers can take the bot/chat — mirrors
                    // iOS `canAddChats`; hides communities the user can't add to.
                    guard case let .community(community) = peer, community.hasPermission(.manageLinkedPeers) else { return nil }
                    let cachedData: CachedPeerData? = cachedDatas[id] ?? nil
                    let count = (cachedData as? CachedCommunityData)?.linkedPeers.count ?? 0
                    return CommunityEntry(peer: peer, chatCount: count)
                }
            }
        }
    actionsDisposable.add(communitiesSignal.start(next: { communities in
        updateState { var c = $0; c.communities = communities; return c }
    }))
    actionsDisposable.add(context.engine.peers.joinedCommunities().start())

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "", removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .communityIntro
    controller.onDeinit = { actionsDisposable.dispose() }
    pop = { [weak controller] in controller?.navigationController?.back() }
    return controller
}

private final class CreateArguments {
    public let context: (any AccountContextProtocol)
    public let selectVisibility: (Bool) -> Void
    public init(context: (any AccountContextProtocol), selectVisibility: @escaping (Bool) -> Void) {
        self.context = context
        self.selectVisibility = selectVisibility
    }
}

private struct CreateState: Equatable {
    public var title: String = ""
    public var peer: EnginePeer?
    public var memberCount: Int32?
    public var visible: Bool = true
    public var isCreating: Bool = false
}

private let _id_title = InputDataIdentifier("_id_title")
private let _id_source_peer = InputDataIdentifier("_id_source_peer")
private let _id_visible = InputDataIdentifier("_id_visible")
private let _id_hidden = InputDataIdentifier("_id_hidden")

private func createEntries(_ state: CreateState, arguments: CreateArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.title), error: nil, identifier: _id_title, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().communitiesCommunityName, filter: { $0 }, limit: 128))
    index += 1

    if let peer = state.peer {
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
        let status: String?
        if let count = state.memberCount, count > 0 {
            status = strings().communitiesMembersOther(Int(count))
        } else {
            status = nil
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_source_peer, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, height: 62, photoSize: NSMakeSize(50, 50), status: status, inset: NSEdgeInsets(left: 20, right: 20), viewType: .singleItem)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communitiesChatVisibility), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_visible, data: .init(name: strings().communitiesVisible, color: theme.colors.text, type: .selectableLeft(state.visible), viewType: .firstItem, enabled: !state.isCreating, description: strings().communitiesVisibleInfo, action: {
        arguments.selectVisibility(true)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_hidden, data: .init(name: strings().communitiesHidden, color: theme.colors.text, type: .selectableLeft(!state.visible), viewType: .lastItem, enabled: !state.isCreating, description: strings().communitiesHiddenInfo, action: {
        arguments.selectVisibility(false)
    })))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communitiesCantChangeLater), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

private func CommunityCreateController(_ context: (any AccountContextProtocol), peerId: PeerId, completed: @escaping () -> Void) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let initialState = CreateState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((CreateState) -> CreateState) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    var close: (() -> Void)? = nil

    let arguments = CreateArguments(context: context, selectVisibility: { visible in
        updateState { var c = $0; if !c.isCreating { c.visible = visible }; return c }
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
        return InputDataSignalValue(entries: createEntries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().communitiesNewCommunity, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .communityCreation
    controller.onDeinit = { actionsDisposable.dispose() }

    controller.updateDatas = { data in
        if let titleValue = data[_id_title]?.stringValue {
            updateState { var c = $0; c.title = titleValue; return c }
        }
        return .fail(.none)
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        if state.isCreating { return .fail(.none) }
        let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return .fail(.fields([_id_title: .shake]))
        }
        updateState { var c = $0; c.isCreating = true; return c }
        actionsDisposable.add((context.engine.peers.createCommunity(title: title, about: nil, peerId: peerId, visible: state.visible) |> deliverOnMainQueue).start(next: { _ in
            close?()
            completed()
        }, error: { error in
            updateState { var c = $0; c.isCreating = false; return c }
            switch error {
            case .adminRequired:
                alert(for: context.window, info: strings().communitiesAdminRequired)
            case .generic:
                alert(for: context.window, info: strings().communitiesSomethingWentWrong)
            }
        }))
        return .fail(.none)
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().communitiesCreate, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 400))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().communitiesNewCommunity)

    close = { [weak modalController] in modalController?.close() }
    return modalController
}
