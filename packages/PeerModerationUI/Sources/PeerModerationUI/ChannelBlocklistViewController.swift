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
import AppAnalytics





private final class ChannelBlacklistControllerArguments {
    let context: any AccountContextProtocol
    
    let removePeer: (PeerId) -> Void
    let openInfo:(PeerId) -> Void
    let addMember:()->Void
    let returnToGroup:(PeerId) -> Void
    init(context: any AccountContextProtocol, removePeer: @escaping (PeerId) -> Void, openInfo:@escaping(PeerId) -> Void, addMember:@escaping()->Void, returnToGroup: @escaping(PeerId) -> Void) {
        self.context = context
        self.removePeer = removePeer
        self.openInfo = openInfo
        self.addMember = addMember
        self.returnToGroup = returnToGroup
    }
}

private enum ChannelBlacklistEntryStableId: Hashable {
    case peer(PeerId)
    case empty
    case addMember
    case section(Int32)
    case header(Int32)
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .peer(peerId):
            hasher.combine(peerId)
        case .empty:
            hasher.combine(0)
        case .section:
            hasher.combine(1)
        case .header:
            hasher.combine(2)
        case .addMember:
            hasher.combine(3)
        }
    }
    
}

private enum ChannelBlacklistEntry: Identifiable, Comparable {
    case peerItem(Int32, Int32, RenderedChannelParticipant, ShortPeerDeleting?, Bool, Bool, GeneralViewType)
    case empty(Bool, Bool)
    case header(Int32, Int32, String, GeneralViewType)
    case section(Int32, CGFloat)
    case addMember(Int32, Int32, GeneralViewType)
    var stableId: ChannelBlacklistEntryStableId {
        switch self {
        case let .peerItem(_, _, participant, _, _, _, _):
            return .peer(participant.peer.id)
        case .empty:
            return .empty
        case let .section(section, _):
            return .section(section)
        case let .header(_, index, _, _):
            return .header(index)
        case .addMember:
            return .addMember
        }
    }
    

    
    var index:Int32 {
        switch self {
        case let .section(section, _):
            return (section * 1000) - section
        case let .header(section, index, _, _):
            return (section * 1000) + index
        case let .addMember(section, index, _):
            return (section * 1000) + index
        case .empty:
            return 0
        case let .peerItem(section, index, _, _, _, _, _):
            return (section * 1000) + index

        }
    }
    
    static func <(lhs: ChannelBlacklistEntry, rhs: ChannelBlacklistEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(_ arguments: ChannelBlacklistControllerArguments, initialSize:NSSize) -> TableRowItem {
        switch self {
        case let .peerItem(_, _, participant, editing, enabled, isChannel, viewType):
            
            let interactionType:ShortPeerItemInteractionType
            if let editing = editing {
                
                interactionType = .deletable(onRemove: { peerId in
                    arguments.removePeer(peerId)
                }, deletable: editing.editable)
            } else {
                interactionType = .plain
            }
            
            var string:String = strings().peerStatusRecently
            
            if case let .member(_, _, _, banInfo, _, _) = participant.participant {
                if let banInfo = banInfo, let peer = participant.peers[banInfo.restrictedBy] {
                    if banInfo.rights.flags.contains(.banReadMessages) {
                        string = strings().channelBlacklistBlockedBy(peer._asPeer().displayTitle)
                    } else {
                        string = strings().channelBlacklistRestrictedBy(peer._asPeer().displayTitle)
                    }
                } else {
                    if let peer = participant.peer._asPeer() as? TelegramUser, let botInfo = peer.botInfo {
                        string = botInfo.flags.contains(.hasAccessToChatHistory) ? strings().peerInfoBotStatusHasAccess : strings().peerInfoBotStatusHasNoAccess
                    } else if let presence = participant.presences[participant.peer.id] as? TelegramUserPresence {
                        let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                        (string,_, _) = stringAndActivityForUserPresence(presence, timeDifference: arguments.context.timeDifference, relativeTo: Int32(timestamp))
                    }
                }
            }

            return ShortPeerRowItem(initialSize, peer: participant.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: enabled, height:50, photoSize: NSMakeSize(36, 36), status: string, drawLastSeparator: true, inset: NSEdgeInsets(left: 20, right: 20), interactionType: interactionType, generalType: .none, viewType: viewType, action: {
                if case .plain = interactionType {
                    arguments.openInfo(participant.peer.id)
                }
            }, contextMenuItems: {
                var items:[ContextMenuItem] = []
               
                if !isChannel {
                    items.append(ContextMenuItem(strings().channelBlacklistContextAddToGroup, handler: {
                        arguments.returnToGroup(participant.peer.id)
                    }, itemImage: MenuAnimation.menu_plus.value))
                }
                if !items.isEmpty {
                    items.append(ContextSeparatorItem())
                }
                items.append(ContextMenuItem(strings().channelBlacklistContextRemove, handler: {
                    arguments.removePeer(participant.peer.id)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                return .single(items)
            })
        case let .empty(progress, isCommunity):
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: progress, text: isCommunity ? strings().channelBlocklistCommunityEmptyDescription : strings().channelBlacklistEmptyDescrpition)
        case let .header(_, _, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: viewType)
        case let .addMember(_, _, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().channelBlacklistRemoveUser, nameStyle: blueActionButton, viewType: viewType, action: {
                arguments.addMember()
            })
        case .section(_, let height):
            return GeneralRowItem(initialSize, height: height, stableId: stableId, viewType: .separator)
        }
    }
}

private func channelBlacklistControllerEntries(view: PeerView, state: PeerListEditingState, participants: [RenderedChannelParticipant]?, inSearch: Bool) -> [ChannelBlacklistEntry] {
    
    var entries: [ChannelBlacklistEntry] = []
    
    var index:Int32 = 10
    var sectionId:Int32 = 1
    
   
    
   
    if let peer = peerViewMainPeer(view) as? TelegramChannel {
        
        entries.append(.section(sectionId, inSearch ? 50 : 20))
        sectionId += 1
       
        if peer.hasPermission(.banMembers), !inSearch {
            entries.append(.addMember(sectionId, 0, .singleItem))
            entries.append(.header(sectionId, 1, peer.isGroup || peer.isSupergroup ? strings().channelBlacklistDescGroup : strings().channelBlacklistDescChannel, .textBottomItem))
        }
        if let participants = participants {
            if !participants.isEmpty, peer.hasPermission(.banMembers) || inSearch {
                entries.append(.section(sectionId, 20))
                sectionId += 1
            }
            
            if !participants.isEmpty {
                
                entries.append(.header(sectionId, index, strings().channelBlacklistBlocked, .textTopItem))
                index += 1
                for (i, participant) in participants.sorted(by: <).enumerated() {
                    var editable = true
                    if case .creator = participant.participant {
                        editable = false
                    }
                    
                    var deleting:ShortPeerDeleting? = nil
                    if state.editing {
                        deleting = ShortPeerDeleting(editable: editable)
                    }
                    
                    entries.append(.peerItem(sectionId, index, participant, deleting, state.removingPeerId != participant.peer.id, peer.isChannel, bestGeneralViewType(participants, for: i)))
                    index += 1
                }
            }
        }
        entries.append(.section(sectionId, 20))
        sectionId += 1
    }
    if entries.isEmpty {
        entries.append(.empty(participants == nil, peerViewMainPeer(view)?.isCommunity == true))
    }
    
    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<ChannelBlacklistEntry>], right: [AppearanceWrapperEntry<ChannelBlacklistEntry>], initialSize:NSSize, arguments:ChannelBlacklistControllerArguments, inSearch: Bool, searchData: TableSearchVisibleData) -> TableUpdateTransition {
    
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    let searchState: TableSearchViewState?
    if inSearch {
        searchState = .visible(searchData)
    } else {
        searchState = .none
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true, searchState: searchState)
}


open class ChannelBlacklistViewController<Context: AccountContextProtocol>: EditableViewController<TableView, Context> {

    private let peerId:PeerId
    
    private let statePromise = ValuePromise(PeerListEditingState(), ignoreRepeated: true)
    private let stateValue = Atomic(value: PeerListEditingState())
    private let removePeerDisposable:MetaDisposable = MetaDisposable()
    private let updatePeerDisposable = MetaDisposable()
    private let disposable:MetaDisposable = MetaDisposable()
    
    private let _inSearch: ValuePromise<Bool> = ValuePromise(false)
    private var inSearch: Bool = false {
        didSet {
            _inSearch.set(self.inSearch)
        }
    }
    public init(_ context:Context, peerId:PeerId) {
        self.peerId = peerId
        super.init(context)
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        genericView.contentInsets = NavigationBarView.contentTopInset
        let context = self.context
        let peerId = self.peerId
        
        
        
        genericView.getBackgroundColor = {
            theme.colors.listBackground
        }
        
        let actionsDisposable = DisposableSet()
        
        let updateState: ((PeerListEditingState) -> PeerListEditingState) -> Void = { [weak self] f in
            if let strongSelf = self {
                strongSelf.statePromise.set(strongSelf.stateValue.modify { f($0) })
            }
        }
        
        let blacklistPromise = Promise<[RenderedChannelParticipant]?>(nil)
        let listDisposable = MetaDisposable()
        
        let viewValue:Atomic<PeerView?> = Atomic(value: nil)
        
        let restrict:(PeerId, Bool) -> Void = { [weak self] memberId, unban in
            let signal = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: memberId, bannedRights: unban ? nil : TelegramChatBannedRights(flags: [.banReadMessages], untilDate: Int32.max)) |> ignoreValues
            
            self?.updatePeerDisposable.set(showModalProgress(signal: signal, for: context.window).start(completed: {
                updateState {
                    return $0.withUpdatedRemovingPeerId(nil)
                }
            }))
        }
        
        let arguments = ChannelBlacklistControllerArguments(context: context, removePeer: { memberId in
            
            updateState {
                return $0.withUpdatedRemovingPeerId(memberId)
            }
            
           restrict(memberId, true)
        }, openInfo: { [weak self] peerId in
            if let navigation = self?.navigationController {
                PeerModerationUIHooks.shared.pushPeerInfo(navigation, context, peerId)
            }
        }, addMember: {
            let behavior = SelectChannelMembersBehavior(peerId: peerId, peerChannelMemberContextsManager: context.peerChannelMemberCategoriesContextsManager, limit: 1)
            
            _ = (selectModalPeers(window: context.window, context: context, title: strings().channelBlacklistSelectNewUserTitle, limit: 1, behavior: behavior, confirmation: { peerIds in
                if let peerId = peerIds.first {
                    var adminError:Bool = false
                    if let participant = behavior.participants[peerId] {
                        if case let .member(_, _, adminInfo, _, _, _) = participant.participant {
                            if let adminInfo = adminInfo {
                                if !adminInfo.canBeEditedByAccountPeer && adminInfo.promotedBy != context.account.peerId {
                                    adminError = true
                                }
                            }
                        } else {
                            adminError = true
                        }
                    }
                    if adminError {
                        alert(for: context.window, info: strings().channelBlacklistDemoteAdminError)
                        return .single(false)
                    }
                }
                return .single(true)
            }) |> map {$0.first} |> filter {$0 != nil} |> map {$0!}).start(next: { memberId in
                restrict(memberId, false)
            })
        }, returnToGroup: { [weak self] memberId in
            updateState {
                return $0.withUpdatedRemovingPeerId(memberId)
            }
            
            let signal = context.peerChannelMemberCategoriesContextsManager.addMember(peerId: peerId, memberId: memberId) |> ignoreValues
            
            self?.updatePeerDisposable.set(showModalProgress(signal: signal, for: context.window).start(completed: {
                updateState {
                    return $0.withUpdatedRemovingPeerId(nil)
                }
            }))
        })
        
        let peerView = context.account.viewTracker.peerView(peerId)
        
        
        var (disposable, loadMoreControl) = context.peerChannelMemberCategoriesContextsManager.banned(peerId: peerId, updated: { listState in
            if case .loading(true) = listState.loadingState, listState.list.isEmpty {
                blacklistPromise.set(.single(nil))
            } else {
                blacklistPromise.set(.single(listState.list))
            }
        })
        
        listDisposable.set(disposable)
        
        actionsDisposable.add(listDisposable)
        
        let initialSize = atomicSize
        let previousEntries:Atomic<[AppearanceWrapperEntry<ChannelBlacklistEntry>]> = Atomic(value: [])

        
        let searchData = TableSearchVisibleData(cancelImage: theme.icons.chatSearchCancel, cancel: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.inSearch = !strongSelf.inSearch
            
            (disposable, loadMoreControl) = context.peerChannelMemberCategoriesContextsManager.banned(peerId: peerId, updated: { listState in
                if case .loading(true) = listState.loadingState, listState.list.isEmpty {
                    blacklistPromise.set(.single(nil))
                } else {
                    blacklistPromise.set(.single(listState.list))
                }
            })
            listDisposable.set(disposable)
            
        }, updateState: { state in
            if let state = state, !state.request.isEmpty {
                (disposable, loadMoreControl) = context.peerChannelMemberCategoriesContextsManager.restrictedAndBanned(peerId: peerId, searchQuery: state.request, updated: { listState in
                    blacklistPromise.set(.single(listState.list))
                })
                listDisposable.set(disposable)
            } else {
                (disposable, loadMoreControl) = context.peerChannelMemberCategoriesContextsManager.banned(peerId: peerId, updated: { listState in
                    if case .loading(true) = listState.loadingState, listState.list.isEmpty {
                        blacklistPromise.set(.single(nil))
                    } else {
                        blacklistPromise.set(.single(listState.list))
                    }
                })
                listDisposable.set(disposable)
            }
        })
        
      
        let signal = combineLatest(statePromise.get(), peerView, blacklistPromise.get(), appearanceSignal, _inSearch.get())
            |> deliverOnMainQueue
            |> map { state, view, blacklist, appearance, inSearch -> (TableUpdateTransition, PeerView) in
                _ = viewValue.swap(view)
                let entries = channelBlacklistControllerEntries(view: view, state: state, participants: blacklist, inSearch: inSearch).map {AppearanceWrapperEntry(entry: $0, appearance: appearance)}
                return (prepareTransition(left: previousEntries.swap(entries), right: entries, initialSize: initialSize.modify{$0}, arguments: arguments, inSearch: inSearch, searchData: searchData), view)
        } |> afterDisposed {
            actionsDisposable.dispose()
        } |> deliverOnMainQueue
        
        self.disposable.set(signal.start(next: { [weak self] transition, peerView in
            guard let `self` = self else {
                return
            }
            if peerViewMainPeer(peerView)?.isCommunity == true {
                self.analyticsScreen = .communityRemovedUsers
            } else {
                self.analyticsScreen = .peerInfoRemovedUsers
            }
            self.genericView.merge(with: transition)
            self.readyOnce()
            self.rightBarView.isHidden = self.genericView.item(at: 0) is SearchEmptyRowItem
            if let peer = peerViewMainPeer(peerView) as? TelegramChannel {
                self.rightBarView.isHidden = self.rightBarView.isHidden || !peer.hasPermission(.banMembers)
            }
            
            var hasItems: Bool = false
            self.genericView.enumerateItems(with: { item -> Bool in
                if item is ShortPeerRowItem {
                    hasItems = true
                }
                return !hasItems
            })
            if let searchButton = self.searchButton {
                self.stackedBar.set(hidden: !(hasItems || self.inSearch), for: searchButton)
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
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self else {
                return .rejected
            }
            self.inSearch = !self.inSearch
            return .invoked
        }, with: self, for: .F, modifierFlags: [.command])
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
    
    open override var defaultBarTitle: String {
        return strings().peerInfoRemovedUsers
    }
    
    private weak var searchButton: ImageButton?

    open override func loadView() {
        super.loadView()
        let btn = stackedBar.insertButton(at: 0, image: theme.icons.chatSearch, handler: { [weak self] in
            guard let self = self else { return }
            self.inSearch = !self.inSearch
        })
        self.searchButton = btn
    }
    
    deinit {
        disposable.dispose()
        removePeerDisposable.dispose()
        updatePeerDisposable.dispose()
    }
    
    open override func update(with state: ViewControllerState) {
        super.update(with: state)
        self.statePromise.set(stateValue.modify({$0.withUpdatedEditing(state == .Edit)}))
    }
    
}


