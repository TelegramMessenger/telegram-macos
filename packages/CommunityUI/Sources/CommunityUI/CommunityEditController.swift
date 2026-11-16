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
import AvatarEditorUI
import FilePanels
import AppAnalytics

public enum CommunityAddChatsMode: Equatable {
    case allMembers
    case onlyAdmins
    public init(defaultBannedRights: TelegramChatBannedRights?) {
        self = (defaultBannedRights?.flags.contains(.banManageLinkedPeers) == true) ? .onlyAdmins : .allMembers
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let setTitle: (String) -> Void
    public let setMode: (CommunityAddChatsMode) -> Void
    public let openAdmins: () -> Void
    public let openPendingRequests: () -> Void
    public let openRemovedUsers: () -> Void
    public let deleteCommunity: () -> Void
    public let updatePhoto: () -> Void
    public let addChat: () -> Void
    public let removeChat: (PeerId) -> Void
    public let openPeer: (PeerId) -> Void
    public init(
        context: (any AccountContextProtocol),
        setTitle: @escaping (String) -> Void,
        setMode: @escaping (CommunityAddChatsMode) -> Void,
        openAdmins: @escaping () -> Void,
        openPendingRequests: @escaping () -> Void,
        openRemovedUsers: @escaping () -> Void,
        deleteCommunity: @escaping () -> Void,
        updatePhoto: @escaping () -> Void,
        addChat: @escaping () -> Void,
        removeChat: @escaping (PeerId) -> Void,
        openPeer: @escaping (PeerId) -> Void
    ) {
        self.context = context
        self.setTitle = setTitle
        self.setMode = setMode
        self.openAdmins = openAdmins
        self.openPendingRequests = openPendingRequests
        self.openRemovedUsers = openRemovedUsers
        self.deleteCommunity = deleteCommunity
        self.updatePhoto = updatePhoto
        self.addChat = addChat
        self.removeChat = removeChat
        self.openPeer = openPeer
    }
}

private struct State: Equatable {
    public var community: TelegramCommunity? = nil
    public var cachedData: CachedCommunityData? = nil
    public var currentTitle: String = ""
    public var initialTitle: String = ""
    public var mode: CommunityAddChatsMode = .allMembers
    public var initialMode: CommunityAddChatsMode = .allMembers
    public var isSaving: Bool = false
    public var isDeleting: Bool = false
    public var updatingPhotoState: PeerInfoUpdatingPhotoState? = nil
    public var peers: [PeerId: EnginePeer] = [:]
    public var memberCounts: [PeerId: Int32] = [:]

    public var hasChanges: Bool {
        return currentTitle != initialTitle || mode != initialMode
    }
    public var isAdmin: Bool {
        return community?.adminRights != nil || community?.flags.contains(.isCreator) == true
    }

    public static func == (lhs: State, rhs: State) -> Bool {
        if lhs.community?.id != rhs.community?.id { return false }
        if lhs.community?.title != rhs.community?.title { return false }
        if lhs.community?.photo != rhs.community?.photo { return false }
        if lhs.updatingPhotoState != rhs.updatingPhotoState { return false }
        if lhs.community?.defaultBannedRights != rhs.community?.defaultBannedRights { return false }
        if lhs.community?.adminRights != rhs.community?.adminRights { return false }
        if lhs.community?.flags != rhs.community?.flags { return false }
        if lhs.cachedData?.adminsCount != rhs.cachedData?.adminsCount { return false }
        if lhs.cachedData?.kickedCount != rhs.cachedData?.kickedCount { return false }
        if lhs.cachedData?.pendingRequests != rhs.cachedData?.pendingRequests { return false }
        if lhs.cachedData?.linkedPeers != rhs.cachedData?.linkedPeers { return false }
        if lhs.peers != rhs.peers { return false }
        if lhs.memberCounts != rhs.memberCounts { return false }
        if lhs.currentTitle != rhs.currentTitle { return false }
        if lhs.initialTitle != rhs.initialTitle { return false }
        if lhs.mode != rhs.mode { return false }
        if lhs.initialMode != rhs.initialMode { return false }
        if lhs.isSaving != rhs.isSaving { return false }
        if lhs.isDeleting != rhs.isDeleting { return false }
        return true
    }
}

private let _id_photo = InputDataIdentifier("_id_photo")
private let _id_title = InputDataIdentifier("_id_title")
private let _id_mode_all = InputDataIdentifier("_id_mode_all")
private let _id_mode_admins = InputDataIdentifier("_id_mode_admins")
private let _id_admins = InputDataIdentifier("_id_admins")
private let _id_pending = InputDataIdentifier("_id_pending")
private let _id_removed = InputDataIdentifier("_id_removed")
private let _id_delete = InputDataIdentifier("_id_delete")
private let _id_add_chat = InputDataIdentifier("_id_add_chat")
private func _id_chat(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_edit_chat_\(id.toInt64())")
}

private struct PhotoTuple: Equatable {
    public let photo: [TelegramMediaImageRepresentation]
    public let updating: PeerInfoUpdatingPhotoState?
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_photo, equatable: InputDataEquatable(PhotoTuple(photo: state.community?.photo ?? [], updating: state.updatingPhotoState)), comparable: nil, item: { initialSize, stableId in
        return CommunityPhotoItem(initialSize, stableId: stableId, context: arguments.context, peer: state.community, updatingPhotoState: state.updatingPhotoState, select: arguments.updatePhoto)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.currentTitle), error: nil, identifier: _id_title, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().communityEditCommunityName, filter: { $0 }, limit: 128))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityEditWhoCanAddChats), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_mode_all, data: .init(name: strings().communityEditAllMembers, color: theme.colors.text, type: .selectableLeft(state.mode == .allMembers), viewType: .firstItem, enabled: !state.isSaving, description: strings().communityEditAllMembersDescription, action: {
        arguments.setMode(.allMembers)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_mode_admins, data: .init(name: strings().communityEditOnlyAdmins, color: theme.colors.text, type: .selectableLeft(state.mode == .onlyAdmins), viewType: .lastItem, enabled: !state.isSaving, description: strings().communityEditOnlyAdminsDescription, action: {
        arguments.setMode(.onlyAdmins)
    })))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    let adminsCount = state.cachedData?.adminsCount ?? 0
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_admins, data: .init(name: strings().communityEditAdministrators, color: theme.colors.text, icon: TelegramThemeHooks.shared.image(.iconChatAdmins).precomposed(flipVertical: true), type: .nextContext("\(adminsCount)"), viewType: .firstItem, enabled: !state.isSaving && !state.isDeleting, action: {
        arguments.openAdmins()
    })))
    index += 1

    let pendingCount = state.cachedData?.pendingRequests ?? 0
    if pendingCount > 0 {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_pending, data: .init(name: strings().communityEditPendingRequests, color: theme.colors.text, icon: TelegramThemeHooks.shared.image(.iconCommunityPendingRequests).precomposed(flipVertical: true), type: .badge("\(pendingCount)", theme.colors.accent), viewType: .innerItem, enabled: !state.isSaving && !state.isDeleting, action: {
            arguments.openPendingRequests()
        })))
        index += 1
    }

    let kickedCount = state.cachedData?.kickedCount ?? 0
    let removedType: GeneralInteractedType = kickedCount > 0 ? .nextContext("\(kickedCount)") : .next
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_removed, data: .init(name: strings().communityEditRemovedUsers, color: theme.colors.text, icon: theme.icons.profile_removed, type: removedType, viewType: .lastItem, enabled: !state.isSaving && !state.isDeleting, action: {
        arguments.openRemovedUsers()
    })))
    index += 1

    if let cachedData = state.cachedData {
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

        let resolved = cachedData.linkedPeers.compactMap { linked -> (peer: EnginePeer, visible: Bool)? in
            guard let peer = state.peers[linked.peerId] else { return nil }
            return (peer, linked.visible ?? true)
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityEditChatsCountOther(resolved.count)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        let canManage = state.isAdmin
        let peersLimit = Int(arguments.context.appConfiguration.getGeneralValue("community_peers_limit", orElse: 100))
        let canAddMore = resolved.count < peersLimit
        if canAddMore {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_chat, data: .init(name: strings().communityEditAddChatToCommunity, color: theme.colors.accent, icon: theme.icons.peerInfoAddMember, type: .none, viewType: resolved.isEmpty ? .singleItem : .firstItem, enabled: !state.isSaving && !state.isDeleting, action: {
                arguments.addChat()
            })))
            index += 1
        }

        for (i, item) in resolved.enumerated() {
            let peer = item.peer
            let viewType: GeneralViewType
            if canAddMore {
                viewType = i == resolved.count - 1 ? .lastItem : .innerItem
            } else {
                viewType = bestGeneralViewType(resolved, for: i)
            }
            var parts: [String] = []
            if let count = state.memberCounts[peer.id], count > 0 {
                parts.append(strings().communityEditMembersCountOther(Int(count)))
            }
            if !item.visible {
                parts.append(strings().communityEditHidden)
            }
            let status: String? = parts.isEmpty ? nil : parts.joined(separator: ", ")
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_chat(peer.id), equatable: InputDataEquatable(PeerEquatable(peer._asPeer())), comparable: nil, item: { initialSize, stableId in
                return ShortPeerRowItem(initialSize, peer: peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, status: status, inset: NSEdgeInsets(left: 20, right: 20), generalType: .none, viewType: viewType, action: {
                    arguments.openPeer(peer.id)
                }, contextMenuItems: {
                    guard canManage else { return .single([]) }
                    return .single([ContextMenuItem(strings().communityEditRemoveFromCommunity, handler: {
                        arguments.removeChat(peer.id)
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)])
                })
            }))
            index += 1
        }
    }

    // Only the creator can delete a community (mirrors iOS, which gates Delete on `.isCreator`).
    if state.community?.flags.contains(.isCreator) == true {
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_delete, data: .init(name: strings().communityEditDeleteCommunity, color: theme.colors.redUI, type: .none, viewType: .singleItem, enabled: !state.isSaving && !state.isDeleting, action: {
            arguments.deleteCommunity()
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

public func CommunityEditController(_ context: (any AccountContextProtocol), communityId: PeerId) -> InputDataController {
    let actionsDisposable = DisposableSet()
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    var getNavController: (() -> NavigationViewController?)? = nil

    let updatePhotoDisposable = MetaDisposable()
    actionsDisposable.add(updatePhotoDisposable)

    let uploadPhoto: (String) -> Void = { path in
        let cancel = {
            updatePhotoDisposable.set(nil)
            updateState { var c = $0; c.updatingPhotoState = nil; return c }
        }
        let updateSignal = Signal<String, NoError>.single(path) |> map { path -> TelegramMediaResource in
            return LocalFileReferenceMediaResource(localFilePath: path, randomId: arc4random64())
        } |> beforeNext { _ in
            updateState { var c = $0; c.updatingPhotoState = PeerInfoUpdatingPhotoState(progress: 0, image: NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil), cancel: cancel); return c }
        } |> castError(UploadPeerPhotoError.self) |> mapToSignal { resource -> Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> in
            return context.engine.peers.updatePeerPhoto(peerId: communityId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(resource)), mapResourceToAvatarSizes: { resource, representations in
                return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
            })
        }
        updatePhotoDisposable.set((updateSignal |> deliverOnMainQueue).start(next: { status in
            updateState { current in
                var c = current
                switch status {
                case .complete:
                    c.updatingPhotoState = nil
                case let .progress(progress):
                    c.updatingPhotoState = c.updatingPhotoState?.withUpdatedProgress(progress)
                }
                return c
            }
        }, error: { _ in
            updateState { var c = $0; c.updatingPhotoState = nil; return c }
            alert(for: context.window, info: strings().communityEditSomethingWentWrong)
        }, completed: {
            updateState { var c = $0; c.updatingPhotoState = nil; return c }
        }))
    }

    let selectPhoto: () -> Void = {
        filePanel(with: photoExts, allowMultiple: false, canChooseDirectories: false, for: context.window, completion: { paths in
            guard let path = paths?.first, let image = NSImage(contentsOfFile: path) else { return }
            _ = (putToTemp(image: image, compress: true) |> deliverOnMainQueue).start(next: { tempPath in
                CommunityHooks.shared.cropImage(context, URL(fileURLWithPath: tempPath), { url in
                    uploadPhoto(url.path)
                }, {
                    removeFile(at: tempPath)
                })
            })
        })
    }

    let arguments = Arguments(
        context: context,
        setTitle: { newTitle in
            updateState { var c = $0; c.currentTitle = newTitle; return c }
        },
        setMode: { newMode in
            updateState { var c = $0; if !c.isSaving { c.mode = newMode }; return c }
        },
        openAdmins: {
            getNavController?()?.push(CommunityAdminsController(context, communityId: communityId))
        },
        openPendingRequests: {
            showModal(with: CommunityRequestsController(context, communityId: communityId), for: context.window)
        },
        openRemovedUsers: {
            CommunityHooks.shared.openBlacklist(context, communityId)
        },
        deleteCommunity: {
            guard !stateValue.with({ $0.isDeleting || $0.isSaving }) else { return }
            verifyAlert(for: context.window, header: strings().communityEditDeleteCommunity, information: strings().communityEditDeleteCommunityConfirm, ok: strings().communityEditDelete, successHandler: { _ in
                updateState { var c = $0; c.isDeleting = true; return c }
                actionsDisposable.add((context.engine.peers.deleteChannel(peerId: communityId) |> deliverOnMainQueue).start(error: { _ in
                    updateState { var c = $0; c.isDeleting = false; return c }
                    alert(for: context.window, info: strings().communityEditSomethingWentWrong)
                }, completed: {
                    _ = context.engine.peers.joinedCommunities().start()
                    getNavController?()?.back()
                }))
            })
        },
        updatePhoto: {
            selectPhoto()
        },
        addChat: {
            let excluded = stateValue.with { ($0.cachedData?.linkedPeers ?? []).map { $0.peerId } }
            actionsDisposable.add(CommunityHooks.shared.selectChatToAdd(context, strings().communityEditAddAChatToCommunity, excluded).start(next: { peerIds in
                guard let peerId = peerIds.first else { return }
                showModal(with: CommunityAddController(context, communityId: communityId, peerId: peerId, completed: {
                    context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)
                }), for: context.window)
            }))
        },
        removeChat: { peerId in
            verifyAlert(for: context.window, information: strings().communityEditRemoveChatConfirm, ok: strings().communityEditRemove, successHandler: { _ in
                actionsDisposable.add((context.engine.peers.toggleCommunityPeerLink(communityId: communityId, peerId: peerId, action: .unlink) |> deliverOnMainQueue).start(error: { _ in
                    alert(for: context.window, info: strings().communityEditSomethingWentWrong)
                }, completed: {
                    context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)
                }))
            })
        },
        openPeer: { peerId in
            CommunityHooks.shared.openChat(context, peerId)
        }
    )

    actionsDisposable.add(combineLatest(
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId)),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.CachedData(id: communityId))
    ).start(next: { peer, cachedData in
        var community: TelegramCommunity? = nil
        if case let .community(c) = peer { community = c }
        let cached = cachedData as? CachedCommunityData
        updateState { current in
            var c = current
            c.community = community
            c.cachedData = cached
            if !c.hasChanges && !c.isSaving {
                if let comm = community {
                    c.initialTitle = comm.title
                    c.currentTitle = comm.title
                    c.initialMode = CommunityAddChatsMode(defaultBannedRights: comm.defaultBannedRights)
                    c.mode = c.initialMode
                }
            }
            return c
        }
    }))
    context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)

    let linkedPeerIds = statePromise.get()
        |> map { ($0.cachedData?.linkedPeers ?? []).map { $0.peerId } }
        |> distinctUntilChanged

    actionsDisposable.add(linkedPeerIds.start(next: { ids in
        for id in ids { context.account.viewTracker.forceUpdateCachedPeerData(peerId: id) }
    }))

    let peersSignal = linkedPeerIds |> mapToSignal { ids -> Signal<([PeerId: EnginePeer], [PeerId: Int32]), NoError> in
        if ids.isEmpty { return .single(([:], [:])) }
        return combineLatest(
            context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })),
            context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.CachedData(id: $0) }))
        ) |> map { peers, cachedDatas in
            var peerMap: [PeerId: EnginePeer] = [:]
            var counts: [PeerId: Int32] = [:]
            for id in ids {
                if let maybePeer = peers[id], let peer = maybePeer { peerMap[id] = peer }
                let cached: CachedPeerData? = cachedDatas[id] ?? nil
                if let c = cached as? CachedChannelData, let memberCount = c.participantsSummary.memberCount { counts[id] = memberCount }
                else if let c = cached as? CachedGroupData, let p = c.participants { counts[id] = Int32(p.participants.count) }
            }
            return (peerMap, counts)
        }
    }
    actionsDisposable.add((peersSignal |> deliverOnMainQueue).start(next: { peers, counts in
        updateState { var c = $0; c.peers = peers; c.memberCounts = counts; return c }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().communityEditTitle, removeAfterDisappear: false, hasDone: true)
    controller.analyticsScreen = .communitySettings

    controller.updateDatas = { data in
        if let titleValue = data[_id_title]?.stringValue {
            updateState { var c = $0; c.currentTitle = titleValue; return c }
        }
        return .fail(.none)
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        let trimmedTitle = state.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return .fail(.fields([_id_title: .shake]))
        }
        if !state.hasChanges {
            return .success(.navigationBack)
        }
        return .fail(.doSomething(next: { f in
            let state = stateValue.with { $0 }
            guard let community = state.community else {
                f(.success(.navigationBack))
                return
            }
            updateState { var c = $0; c.isSaving = true; return c }

            let trimmedTitle = state.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleChanged = trimmedTitle != state.initialTitle
            let modeChanged = state.mode != state.initialMode

            var titleSignal: Signal<Void, NoError> = .single(())
            if titleChanged {
                titleSignal = context.engine.peers.updatePeerTitle(peerId: communityId, title: trimmedTitle)
                    |> `catch` { _ in Signal<Void, NoError>.single(()) }
            }

            var rightsSignal: Signal<Void, NoError> = .single(())
            if modeChanged {
                let existingFlags = community.defaultBannedRights?.flags ?? TelegramChatBannedRightsFlags()
                let existingUntil = community.defaultBannedRights?.untilDate ?? Int32.max
                var newFlags = existingFlags
                if state.mode == .onlyAdmins {
                    newFlags.insert(.banManageLinkedPeers)
                } else {
                    newFlags.remove(.banManageLinkedPeers)
                }
                let newRights = TelegramChatBannedRights(flags: newFlags, untilDate: existingUntil)
                rightsSignal = context.engine.peers.updateDefaultChannelMemberBannedRights(peerId: communityId, rights: newRights)
                    |> mapToSignal { (_: Never) -> Signal<Void, NoError> in .single(()) }
            }

            let saveSignal = combineLatest(titleSignal, rightsSignal) |> map { _, _ in () }
            actionsDisposable.add((saveSignal |> deliverOnMainQueue).start(completed: {
                updateState { var c = $0; c.isSaving = false; return c }
                f(.success(.navigationBack))
            }))
        }))
    }

    getNavController = { [weak controller] in controller?.navigationController }
    controller.onDeinit = { actionsDisposable.dispose() }
    return controller
}

private final class CommunityPhotoItem: GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peer: TelegramCommunity?
    fileprivate let updatingPhotoState: PeerInfoUpdatingPhotoState?
    fileprivate let textLayout: TextViewLayout
    fileprivate let select: () -> Void

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), peer: TelegramCommunity?, updatingPhotoState: PeerInfoUpdatingPhotoState?, select: @escaping () -> Void) {
        self.context = context
        self.peer = peer
        self.updatingPhotoState = updatingPhotoState
        self.select = select
        let text: String
        if updatingPhotoState != nil {
            text = strings().communityEditUpdatingPhoto
        } else if peer?.photo.isEmpty == false {
            text = strings().communityEditChangePhoto
        } else {
            text = strings().communityEditSetPhoto
        }
        let color = updatingPhotoState != nil ? theme.colors.grayText : theme.colors.accent
        self.textLayout = TextViewLayout(.initialize(string: text, color: color, font: .normal(.text)), maximumNumberOfLines: 1)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: width - 40)
        return true
    }

    public override var height: CGFloat {
        return 16 + 90 + 8 + textLayout.layoutSize.height + 16
    }

    public override func viewClass() -> AnyClass {
        return CommunityPhotoView.self
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        select()
        return true
    }
}

private final class CommunityPhotoView: GeneralRowView {
    private let avatar = AvatarControl(font: .avatar(30))
    private let photoEditable = PeerInfoPhotoEditableView(frame: NSMakeRect(0, 0, 90, 90))
    private let textView = TextView()
    private let control = Control()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        avatar.setFrameSize(NSMakeSize(90, 90))
        avatar.userInteractionEnabled = false
        photoEditable.layer?.cornerRadius = 30
        photoEditable.layer?.masksToBounds = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isEventLess = true
        addSubview(avatar)
        addSubview(photoEditable)
        addSubview(textView)
        photoEditable.setup = { [weak self] _, _ in
            if let item = self?.item as? CommunityPhotoItem {
                item.select()
            }
        }
        control.set(handler: { [weak self] _ in
            if let item = self?.item as? CommunityPhotoItem {
                item.select()
            }
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? CommunityPhotoItem else { return }
        if let peer = item.peer {
            avatar.setState(account: item.context.account, state: .PeerAvatar(peer, peer.displayLetters, peer.smallProfileImage, peer.namePeerColor, nil, NSMakeSize(90, 90), true, nil))
        }
        textView.update(item.textLayout)
        control.setAccessibilityLabel(item.textLayout.attributedString.string)
        photoEditable.updateState(item.updatingPhotoState, animated: animated)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        control.frame = bounds
        avatar.centerX(y: 16)
        photoEditable.frame = avatar.frame
        textView.centerX(y: avatar.frame.maxY + 8)
    }
}
