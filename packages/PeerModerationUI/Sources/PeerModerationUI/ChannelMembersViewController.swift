import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import LocalAnimations
import GeneralRows
import ShortPeerRow
import AlertsUI
import SelectPeersUI
import ChatHistoryModel
import InputDataUI

struct ChannelMembersConfiguration {
    
    let hidden_members_group_size_min: Int32
    
    static func with(appConfiguration: AppConfiguration) -> ChannelMembersConfiguration {
        if let data = appConfiguration.data, let rawType = data["hidden_members_group_size_min"] as? String, let value = Int32(rawType) {
            return .init(hidden_members_group_size_min: value)
        } else {
            return .init(hidden_members_group_size_min: 1)
        }
    }
}

private final class ChannelMembersControllerArguments {
    let context: any AccountContextProtocol
    let peerId: PeerId

    let removePeer: (PeerId) -> Void
    let addMembers:()-> Void
    let inviteLink:()-> Void
    let openInfo:(RenderedChannelParticipant)->Void
    let openMemberInfo:(Peer)->Void
    let toggleHideMembers:(Bool)-> Void
    init(context: any AccountContextProtocol, peerId: PeerId, removePeer: @escaping (PeerId) -> Void, addMembers:@escaping()->Void, inviteLink:@escaping()->Void, openInfo:@escaping(RenderedChannelParticipant)->Void, openMemberInfo:@escaping(Peer)->Void, toggleHideMembers:@escaping(Bool)-> Void) {
        self.context = context
        self.peerId = peerId
        self.removePeer = removePeer
        self.addMembers = addMembers
        self.inviteLink = inviteLink
        self.openInfo = openInfo
        self.openMemberInfo = openMemberInfo
        self.toggleHideMembers = toggleHideMembers
    }

    func profileMenuItems(for peer: Peer, beforeAction: @escaping () -> Void = {}) -> [ContextMenuItem] {
        return [ContextMenuItem(strings().chatContextPeerOpenInfo, handler: {
            beforeAction()
            self.openMemberInfo(peer)
        }, itemImage: MenuAnimation.menu_open_profile.value)]
    }

    func contextMenuItems(for participant: RenderedChannelParticipant, beforeAction: @escaping () -> Void = {}) -> Signal<[ContextMenuItem], NoError> {
        return context.account.postbox.loadedPeerWithId(peerId)
            |> take(1)
            |> deliverOnMainQueue
            |> map { peer in
                var items: [ContextMenuItem] = []
                let channel = peer as? TelegramChannel
                if let channel, !channel.isChannel,
                   channel.hasPermission(.manageRanks) || (participant.peer.id == self.context.peerId && channel.hasPermission(.editRank)) {
                    items.append(ContextMenuItem(strings().channelMemberEditTag, handler: {
                        beforeAction()
                        self.openInfo(participant)
                    }, itemImage: MenuAnimation.menu_tag_rename.value))
                }
                items.append(contentsOf: self.profileMenuItems(for: participant.peer._asPeer(), beforeAction: beforeAction))
                if let channel, channel.canRemoveParticipant(participant.participant, accountId: self.context.peerId) {
                    items.append(ContextSeparatorItem())
                    items.append(ContextMenuItem(strings().confirmDelete, handler: {
                        beforeAction()
                        self.removePeer(participant.peer.id)
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                return items
            }
    }
}

private enum ChannelMembersEntryStableId: Hashable {
    case peer(PeerId)
    case hideMembers
    case hideMembersInfo
    case addMembers
    case inviteLink
    case membersDesc
    case section(Int)
    case loading
    case contactsHeader
    case otherHeader
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .peer(peerId):
            hasher.combine(peerId)
        case .hideMembers:
            hasher.combine(0)
        case .hideMembersInfo:
            hasher.combine(1)
        case .addMembers:
            hasher.combine(2)
        case .inviteLink:
            hasher.combine(3)
        case .membersDesc:
            hasher.combine(4)
        case .loading:
            hasher.combine(5)
        case .contactsHeader:
            hasher.combine(6)
        case .otherHeader:
            hasher.combine(7)
        case let .section(sectionId):
            hasher.combine(-(sectionId))
        }
    }

}

private enum ChannelMembersEntry: Identifiable, Comparable {
    case peerItem(sectionId:Int, Int32, RenderedChannelParticipant, ShortPeerDeleting?, Bool, Bool, GeneralViewType)
    case hideMembers(sectionId:Int, Bool, GeneralViewType)
    case hideMembersInfo(sectionId:Int, String, GeneralViewType)
    case addMembers(sectionId:Int, Bool, GeneralViewType)
    case inviteLink(sectionId:Int, GeneralViewType)
    case membersDesc(sectionId:Int, String, GeneralViewType)
    case contactsHeader(sectionId:Int, String, GeneralViewType)
    case otherHeader(sectionId:Int, String, GeneralViewType)
    case section(sectionId:Int)
    case loading(sectionId: Int)
    
    var stableId: ChannelMembersEntryStableId {
        switch self {
        case let .peerItem(_, _, participant, _, _, _, _):
            return .peer(participant.peer.id)
        case .hideMembers:
            return .hideMembers
        case .hideMembersInfo:
            return .hideMembersInfo
        case .addMembers:
            return .addMembers
        case .inviteLink:
            return .inviteLink
        case .membersDesc:
            return .membersDesc
        case .contactsHeader:
            return .contactsHeader
        case .otherHeader:
            return .otherHeader
        case .loading:
            return .loading
        case let .section(sectionId):
            return .section(sectionId)
        }
    }
    
    
    var index:Int {
        switch self {
        case let .peerItem(sectionId, index, _, _, _, _, _):
            return (sectionId * 1000) + Int(index) + 100
        case let .addMembers(sectionId, _, _):
            return (sectionId * 1000) + 0
        case let .hideMembers(sectionId, _, _):
            return (sectionId * 1000) + 0
        case let .hideMembersInfo(sectionId, _, _):
            return (sectionId * 1000) + 0
        case let .inviteLink(sectionId, _):
            return (sectionId * 1000) + 1
        case let .membersDesc(sectionId, _, _):
            return (sectionId * 1000) + 2
        case let .contactsHeader(sectionId, _, _):
            return (sectionId * 1000) + 3
        case let .otherHeader(sectionId, _, _):
            return (sectionId * 1000) + 4
        case let .loading(sectionId):
            return (sectionId * 1000) + 5
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        }
    }
    
    
    static func <(lhs: ChannelMembersEntry, rhs: ChannelMembersEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(_ arguments: ChannelMembersControllerArguments, initialSize:NSSize) -> TableRowItem {
        switch self {
        case let .peerItem(_, _, participant, editing, enabled, _, viewType):

            let interactionType:ShortPeerItemInteractionType
            if let editing = editing {

                interactionType = .deletable(onRemove: { peerId in
                    arguments.removePeer(peerId)
                }, deletable: editing.editable)
            } else {
                interactionType = .plain
            }

            let label: String
            var badgeType: AdminBadgeType = .none
            switch participant.participant {
            case let .creator(_, _, rank):
                label = rank ?? strings().chatOwnerBadge
                badgeType = .owner
            case let .member(_, _, adminInfo, _, rank, _):
                if adminInfo != nil {
                    label = rank ?? strings().chatAdminBadge
                    badgeType = .admin
                } else {
                    label = rank ?? ""
                }
            }

            let generalType: GeneralInteractedType
            if badgeType != .none, !label.isEmpty {
                let badgeColor: NSColor = badgeType == .owner ? premiumGradient[1] : theme.colors.greenUI
                generalType = .contextColored(label, badgeColor)
            } else {
                generalType = .context(label)
            }

            let isPlain: Bool
            if case .plain = interactionType { isPlain = true } else { isPlain = false }
            return ShortPeerRowItem(initialSize, peer: participant.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: enabled, height:46, photoSize: NSMakeSize(32, 32), drawLastSeparator: true, inset: NSEdgeInsets(left: 20, right: 20), interactionType: interactionType, generalType: generalType, viewType: viewType, action: {
                if isPlain {
                    arguments.openMemberInfo(participant.peer._asPeer())
                }
            }, contextMenuItems: {
                return arguments.contextMenuItems(for: participant)
            }, menuOnAction: isPlain)
        case let .hideMembers(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().channelMembersGroupHideMembers, type: .switchable(value), viewType: viewType, action: {
                arguments.toggleHideMembers(!value)
            })
        case let .hideMembersInfo(_, string, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: string, viewType: viewType)
        case let .addMembers(_, isChannel, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: isChannel ? strings().channelMembersAddSubscribers : strings().channelMembersAddMembers, icon: theme.icons.peerInfoAddMember, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.addMembers()
            })
        case let .inviteLink(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().channelMembersInviteLink, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                arguments.inviteLink()
            })
        case let .membersDesc(_, string, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: string, viewType: viewType)
        case let .contactsHeader(_, string, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: string, viewType: viewType)
        case let .otherHeader(_, string, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: string, viewType: viewType)
        case .loading:
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: true)
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        }
    }
}


private func channelMembersControllerEntries(view: PeerView, context: any AccountContextProtocol, state: PeerListEditingState, participants: [RenderedChannelParticipant]?, contacts: [RenderedChannelParticipant]?) -> [ChannelMembersEntry] {
    
    var entries: [ChannelMembersEntry] = []
    
    var sectionId:Int = 1
    
   
    if let participants = participants, let contacts = contacts {
        
        let participants = participants.filter { value in
            return !contacts.contains(where: { $0.peer.id == value.peer.id })
        }
        
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
        
        if let peer = peerViewMainPeer(view) as? TelegramChannel {
            
            let configuration = ChannelMembersConfiguration.with(appConfiguration: context.appConfiguration)
            
            if peer.groupAccess.canAddMembers, !peer.isChannel, let cachedData = view.cachedData as? CachedChannelData, let value = cachedData.membersHidden.knownValue?.value {
                let members = cachedData.participantsSummary.memberCount ?? 1
                if members >= configuration.hidden_members_group_size_min {
                    entries.append(.hideMembers(sectionId: sectionId, value, .singleItem))
                    entries.append(.hideMembersInfo(sectionId: sectionId, strings().channelMembersGroupHideMembersInfo, .textBottomItem))
                    entries.append(.section(sectionId: sectionId))
                    sectionId += 1
                }
            }


            if peer.hasPermission(.inviteMembers) {
                entries.append(.addMembers(sectionId: sectionId, peer.isChannel, .singleItem))
                if peer.isChannel {
                    entries.append(.membersDesc(sectionId: sectionId, strings().channelMembersMembersListDesc, .textBottomItem))
                }
                entries.append(.section(sectionId: sectionId))
                sectionId += 1
            }
            
            if !contacts.isEmpty {
                
                let contactsHeader: String
                if peer.isChannel {
                    contactsHeader = strings().channelMembersContacts
                } else {
                    contactsHeader = strings().channelMembersGroupContacts
                }
                entries.append(.contactsHeader(sectionId: sectionId, contactsHeader, .textTopItem))
                
                var index: Int32 = 0
                for (i, participant) in contacts.sorted(by: <).enumerated() {
                    
                    let editable = peer.canRemoveParticipant(participant.participant, accountId: context.peerId)
                    
                    var deleting:ShortPeerDeleting? = nil
                    if state.editing {
                        deleting = ShortPeerDeleting(editable: editable)
                    }
                    entries.append(.peerItem(sectionId: sectionId, index, participant, deleting, state.removingPeerId != participant.peer.id, editable, bestGeneralViewType(contacts, for: i)))
                    index += 1
                }
                if !participants.isEmpty {
                    entries.append(.section(sectionId: sectionId))
                    sectionId += 1
                }
            }

            if !contacts.isEmpty && participants.count > 0 {
                
                let otherHeader: String
                if peer.isChannel {
                    otherHeader = strings().channelMembersOtherMembers
                } else {
                    otherHeader = strings().channelMembersGroupOtherMembers
                }
                
                entries.append(.otherHeader(sectionId: sectionId, otherHeader, .textTopItem))
            }
           
            var index: Int32 = 0
            for (i, participant) in participants.sorted(by: <).enumerated() {
                
                let editable = peer.canRemoveParticipant(participant.participant, accountId: context.peerId)
                
                var deleting:ShortPeerDeleting? = nil
                if state.editing {
                    deleting = ShortPeerDeleting(editable: editable)
                }
                entries.append(.peerItem(sectionId: sectionId, index, participant, deleting, state.removingPeerId != participant.peer.id, editable, bestGeneralViewType(participants, for: i)))
                index += 1
            }
            
        }
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
    } else {
        entries.append(.loading(sectionId: sectionId))
    }
    
    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<ChannelMembersEntry>], right: [AppearanceWrapperEntry<ChannelMembersEntry>], initialSize:NSSize, arguments:ChannelMembersControllerArguments) -> TableUpdateTransition {
    
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}


private struct Result {
    let success:[PeerId]
    let failed:[(PeerId, AddChannelMemberError)]
}

open class ChannelMembersViewController<Context: AccountContextProtocol>: EditableViewController<TableView, Context> {
    
    private let peerId:PeerId
    
    private let statePromise = ValuePromise(PeerListEditingState(), ignoreRepeated: true)
    private let stateValue = Atomic(value: PeerListEditingState())
    private let removePeerDisposable:MetaDisposable = MetaDisposable()
    
    private let disposable:MetaDisposable = MetaDisposable()
    private var isChannel: Bool = true
    private var memberActions: ChannelMembersControllerArguments?

    public init(_ context: Context, peerId:PeerId) {
        self.peerId = peerId
        super.init(context)
    }

    open override var defaultBarTitle: String {
        return isChannel ? strings().peerInfoSubscribers : strings().peerInfoMembers
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            self.searchChannelUsers()
            return .invoked
        }, with: self, for: .F, priority: .low, modifierFlags: [.command])
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        let context = self.context
        let peerId = self.peerId
        
        genericView.contentInsets = NavigationBarView.contentTopInset
        
        genericView.getBackgroundColor = {
            theme.colors.listBackground
        }
        
        let updateState: ((PeerListEditingState) -> PeerListEditingState) -> Void = { [weak self] f in
            if let strongSelf = self {
                strongSelf.statePromise.set(strongSelf.stateValue.modify { f($0) })
            }
        }
        
        let actionsDisposable = DisposableSet()
        let peersPromise = Promise<[RenderedChannelParticipant]?>(nil)
        let contactsPromise = Promise<[RenderedChannelParticipant]?>(nil)

        let arguments = ChannelMembersControllerArguments(context: context, peerId: peerId, removePeer: { [weak self] memberId in
            
            updateState {
                return $0.withUpdatedRemovingPeerId(memberId)
            }
            
            self?.removePeerDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: memberId, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: 0)) |> deliverOnMainQueue).start(completed: {
                updateState {
                    return $0.withUpdatedRemovingPeerId(nil)
                }
                
            }))
        }, addMembers: {
            
            
            let signal = selectModalPeers(window: context.window, context: context, title: strings().channelMembersSelectTitle, settings: [.contacts, .remote, .excludeBots]) |> mapToSignal { memberIds -> Signal<Result, NoError> in
                return showModalProgress(signal: context.peerChannelMemberCategoriesContextsManager.addMembersAllowPartial(peerId: peerId, memberIds: memberIds), for: context.window) |> map { failed -> Result in
                    let success = memberIds.filter { memberId in
                        return !failed.contains(where: { $0.0 == memberId })
                    }
                    return .init(success: success, failed: failed)
                }
            } |> deliverOnMainQueue
            
            actionsDisposable.add(signal.start(next: { result in
                
                var forbidden: [TelegramForbiddenInvitePeer] = []
                
                for (_, failed) in result.failed {
                    switch failed {
                    case let .restricted(peer):
                        if let peer {
                            forbidden.append(peer)
                        }
                    default:
                        break
                    }
                }
                
                let failed = result.failed.filter {
                    switch $0.1 {
                    case .notMutualContact, .limitExceeded, .tooMuchJoined, .generic, .kicked, .restricted:
                        return true
                    default:
                        return false
                    }
                }
                let botFailed = result.failed.filter {
                    switch $0.1 {
                    case .bot:
                        return true
                    default:
                        return false
                    }
                }
                                
                if !failed.isEmpty {
                    FeatureNavigationHooks.shared.showInvitePrivacyLimited(context, peerId, failed.map { $0.0 }, forbidden)
                } else if let first = botFailed.first {
                    if case let .bot(memberId) = first.1 {
                        let _ = (context.account.postbox.transaction { transaction in
                            return transaction.getPeer(peerId)
                            }
                            |> deliverOnMainQueue).start(next: { peer in
                                guard let peer = peer as? TelegramChannel else {
                                    alert(for: context.window, info: strings().unknownError)
                                    return
                                }
                                if peer.hasPermission(.addAdmins) {
                                    verifyAlert_button(for: context.window, information: strings().channelAddBotErrorHaveRights, ok: strings().channelAddBotAsAdmin, successHandler: { _ in
                                        if let controller = FeatureNavigationHooks.shared.makeChannelAdminController(context, peerId, memberId, nil, { _ in }, { _,_  in }) { showModal(with: controller, for: context.window) }
                                    })
                                } else {
                                    alert(for: context.window, info: strings().channelAddBotErrorHaveRights)
                                }
                            })
                    }
                }
                
            }, completed: {
            }))
        }, inviteLink: { [weak self] in
            if let strongSelf = self {
                if let controller = FeatureNavigationHooks.shared.makeLinkInvitationController(strongSelf.context, strongSelf.peerId) { strongSelf.navigationController?.push(controller) }
            }
        }, openInfo: { participant in
            showModal(with: ChannelParticipantController(context: context, peerId: peerId, participant: participant), for: context.window)
        }, openMemberInfo: { [weak self] peer in
            self?.navigationController?.push(PeerModerationUIHooks.shared.makePeerInfoController(context, peer))
        }, toggleHideMembers: { value in
            let signal = context.engine.peers.updateChannelMembersHidden(peerId: peerId, value: value)
            actionsDisposable.add(signal.start())
        })
        self.memberActions = arguments
        
        let peerView = context.account.viewTracker.peerView(peerId)

        let (contactsDisposable, _) = context.peerChannelMemberCategoriesContextsManager.contacts(peerId: peerId, updated: { state in
            contactsPromise.set(.single(state.list))
        })
        actionsDisposable.add(contactsDisposable)
                                                                    
        let (disposable, loadMoreControl) = context.peerChannelMemberCategoriesContextsManager.recent(peerId: peerId, updated: { state in
            peersPromise.set(.single(state.list))
        })
        actionsDisposable.add(disposable)
        
        
        
        
        let initialSize = atomicSize
        let previousEntries:Atomic<[AppearanceWrapperEntry<ChannelMembersEntry>]> = Atomic(value: [])
        
        
        let signal = combineLatest(statePromise.get(), peerView, peersPromise.get(), contactsPromise.get(), appearanceSignal)
            |> deliverOnMainQueue
            |> map { state, view, peers, contacts, appearance -> (TableUpdateTransition, PeerView) in
                let entries = channelMembersControllerEntries(view: view, context: context, state: state, participants: peers, contacts: contacts).map{AppearanceWrapperEntry(entry: $0, appearance: appearance)}
                return (prepareTransition(left: previousEntries.swap(entries), right: entries, initialSize: initialSize.modify{$0}, arguments: arguments), view)
        } |> afterDisposed {
            actionsDisposable.dispose()
        }

        self.disposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] transition, view in
            if let strongSelf = self {
                if let peer = peerViewMainPeer(view) as? TelegramChannel {
                    if strongSelf.isChannel != peer.isChannel {
                        strongSelf.isChannel = peer.isChannel
                        strongSelf.setCenterTitle(strongSelf.defaultBarTitle)
                    }
                }
                strongSelf.genericView.merge(with: transition)
                strongSelf.readyOnce()
            }
        }))
        
        genericView.setScrollHandler { position in
            if let loadMoreControl = loadMoreControl {
                switch position.direction {
                case .bottom:
                    context.peerChannelMemberCategoriesContextsManager.loadMore(peerId: peerId, control: loadMoreControl)
                default:
                    break
                }
            }
        }
    }
    
    deinit {
        disposable.dispose()
        removePeerDisposable.dispose()
    }
    
    open override func update(with state: ViewControllerState) {
        super.update(with: state)
        self.statePromise.set(stateValue.modify({$0.withUpdatedEditing(state == .Edit)}))
    }
    
    private func searchChannelUsers() {
        let peerId = self.peerId
        let behavior = SelectChannelMembersBehavior(peerId: peerId, peerChannelMemberContextsManager: context.peerChannelMemberCategoriesContextsManager, limit: 1, settings: [])
        behavior.contextMenuItems = { [weak self, weak behavior] peer, closeSearch in
            guard let arguments = self?.memberActions else { return .single([]) }
            if let participant = behavior?.participants[peer.id] {
                return arguments.contextMenuItems(for: participant, beforeAction: closeSearch)
            }
            return .single(arguments.profileMenuItems(for: peer, beforeAction: closeSearch))
        }
        _ = (selectModalPeers(window: context.window, context: context, title: strings().selectPeersTitleSearchMembers, behavior: behavior) |> deliverOnMainQueue |> map {$0.first}).start(next: { [weak self] selectedPeerId in
            guard let selectedPeerId, let arguments = self?.memberActions else { return }
            _ = (arguments.context.account.postbox.loadedPeerWithId(selectedPeerId) |> deliverOnMainQueue).start(next: { peer in
                arguments.openMemberInfo(peer)
            })
        })
    }
    
    open override func loadView() {
        super.loadView()
        stackedBar.insertButton(at: 0, image: theme.icons.chatSearch, handler: { [weak self] in
            self?.searchChannelUsers()
        })
    }
    
}
