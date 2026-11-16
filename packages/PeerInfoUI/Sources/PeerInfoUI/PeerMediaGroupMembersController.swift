import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore

import TGUIKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import LocalAnimations
import GeneralRows
import ShortPeerRow
import InputDataUI
import ChatHistoryModel
import ChatUI
import StoriesUI
import ChannelAdminUI
import AppAnalytics

private final class GroupPeersArguments<Context: AccountContextProtocol> {
    let context: Context
    let removePeer: (PeerId)->Void
    let openInfo:(RenderedChannelParticipant)->Void
    let promote:(RenderedChannelParticipant)->Void
    let restrict:(RenderedChannelParticipant)->Void
    let showMore:()->Void
    let openStory:(StoryInitialIndex?)->Void
    let analyticsContext: AnalyticsContext
    init(context: Context, analyticsContext: AnalyticsContext, removePeer:@escaping(PeerId)->Void, showMore: @escaping()->Void, openInfo:@escaping(RenderedChannelParticipant)->Void, promote:@escaping(RenderedChannelParticipant)->Void, restrict:@escaping(RenderedChannelParticipant)->Void, openStory:@escaping(StoryInitialIndex?)->Void) {
        self.context = context
        self.analyticsContext = analyticsContext
        self.removePeer = removePeer
        self.openInfo = openInfo
        self.promote = promote
        self.restrict = restrict
        self.showMore = showMore
        self.openStory = openStory
    }
    
    func peerInfo(_ peerId:PeerId) {
        PeerInfoController<Context>.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId, analyticsContext: analyticsContext)
    }
}

private struct GroupPeersState : Equatable {
    var temporaryParticipants: [TemporaryParticipant]
    var successfullyAddedParticipantIds: Set<PeerId>
    var removingParticipantIds: Set<PeerId>
    var hasShowMoreButton: Bool?
}

private func _id_peer_id(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_id_\(id)")
}

extension GroupInfoEntry : Equatable {
    static func ==(lhs: GroupInfoEntry, rhs: GroupInfoEntry) -> Bool {
        return lhs.isEqual(to: rhs)
    }
}

private func groupPeersEntries<Context: AccountContextProtocol>(state: GroupPeersState, isEditing: Bool, viewAndStories: (PeerView, [PeerId: PeerStoryStats]), inputActivities: [PeerId: PeerInputActivity], memberListState: ChannelMemberListState, arguments: GroupPeersArguments<Context>) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index:Int32 = 0
    
    let view = viewAndStories.0
    let storyStats = viewAndStories.1
    
    
    
    
    var usersBlock:[GroupInfoEntry<Context>] = []
    
    
    func applyBlock(_ block:[GroupInfoEntry<Context>]) {
        var block = block
        for (i, item) in block.enumerated() {
            var viewType = bestGeneralViewType(block, for: i)
            if i == 0 {
                if block.count > 1 {
                    viewType = .innerItem
                } else {
                    viewType = .lastItem
                }
            }
            
            
            viewType = viewType.withUpdatedInsets(NSEdgeInsetsMake(16, 18, 16, 18))
            block[i] = item.withUpdatedViewType(viewType)
            
        }
       
        
        for item in block {
            switch item {
            case let .member(_, _, _, peer, presence, inputActivity, stories, memberStatus, editing, menuItems, enabled, viewType, badgeAction):
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer_id(peer!.id), equatable: InputDataEquatable(item), comparable: nil, item: { initialSize, stableId in
                    let label: String
                    var isAdmin: Bool = false
                    var badgeType: AdminBadgeType = .none
                    switch memberStatus {
                    case let .creator(rank):
                        label = rank
                        isAdmin = true
                        badgeType = .owner
                    case let .admin(rank):
                        label = rank
                        isAdmin = true
                        badgeType = .admin
                    case let .memberTag(rank):
                        label = rank
                    case .member:
                        label = ""
                    }
                    let peer = peer!

                    var string:String = strings().peerStatusRecently
                    var color:NSColor = theme.colors.grayText

                    if let peer = peer as? TelegramUser, let botInfo = peer.botInfo {
                        string = botInfo.flags.contains(.hasAccessToChatHistory) || isAdmin ? strings().peerInfoBotStatusHasAccess : strings().peerInfoBotStatusHasNoAccess
                    } else if let presence = presence as? TelegramUserPresence {
                        let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                        (string, _, color) = stringAndActivityForUserPresence(presence, timeDifference: arguments.context.timeDifference, relativeTo: Int32(timestamp))
                    }

                    let interactionType:ShortPeerItemInteractionType
                    if let editing = editing {

                        interactionType = .deletable(onRemove: { memberId in
                            arguments.removePeer(memberId)
                        }, deletable: editing.editable)
                    } else {
                        interactionType = .plain
                    }

                    let generalType: GeneralInteractedType
                    if badgeType != .none, !label.isEmpty {
                        let badgeColor: NSColor = badgeType == .owner ? premiumGradient[1] : theme.colors.greenUI
                        generalType = .contextColored(label, badgeColor)
                    } else {
                        generalType = .context(label)
                    }

                    return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: enabled, height: 36 + 16, photoSize: NSMakeSize(36, 36), titleStyle: ControlStyle(font: .medium(12.5), foregroundColor: theme.colors.text), statusStyle: ControlStyle(font: NSFont.normal(12.5), foregroundColor:color), status: string, inset: NSEdgeInsets(left: 0, right: 0), drawSeparatorIgnoringInset: true, interactionType: interactionType, generalType: generalType, viewType: viewType, action:{
                        arguments.peerInfo(peer.id)
                    }, contextMenuItems: {
                        return .single(menuItems)
                    }, inputActivity: inputActivity, highlightVerified: true, customTheme: .initialize(theme), story: stories?.subscriptionItem(peer), openStory: arguments.openStory, fullSize: true, badgeAction: badgeAction)
                }))
            case let .showMore(_, _, viewType):
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("_id_show_more"), equatable: nil, comparable: nil, item: { initialSize, stableId in
                    return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().peerInfoShowMore, nameStyle: blueActionButton, type: .none, viewType: viewType, action: {
                        arguments.showMore()
                    }, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchUp, textInset: 52, thumbInset: 4), inset: NSEdgeInsetsZero)
                }))
            default:
                break
            }
            
        }
    }
    
    
    if let group = peerViewMainPeer(view) {
        let access = group.groupAccess
        
        if let cachedGroupData = view.cachedData as? CachedGroupData, let participants = cachedGroupData.participants, let group = group as? TelegramGroup {
            
            var updatedParticipants = participants.participants
            let existingParticipantIds = Set(updatedParticipants.map { $0.peerId })
            
            var peerPresences: [PeerId: PeerPresence] = view.peerPresences
            var peers: [PeerId: Peer] = view.peers
            var disabledPeerIds = state.removingParticipantIds
            
            if !state.temporaryParticipants.isEmpty {
                for participant in state.temporaryParticipants {
                    if !existingParticipantIds.contains(participant.peer.id) {
                        updatedParticipants.append(.member(id: participant.peer.id, invitedBy: arguments.context.account.peerId, invitedAt: participant.timestamp, rank: nil))
                        if let presence = participant.presence, peerPresences[participant.peer.id] == nil {
                            peerPresences[participant.peer.id] = presence
                        }
                        if peers[participant.peer.id] == nil {
                            peers[participant.peer.id] = participant.peer
                        }
                        disabledPeerIds.insert(participant.peer.id)
                    }
                }
            }
            
            let sortedParticipants = participants.participants.filter({peers[$0.peerId]?.displayTitle != nil}).map { participant in
                return (participant: participant, hasActivity: inputActivities[participant.peerId] != nil, presence: view.peerPresences[participant.peerId] as? TelegramUserPresence)
            }.sorted(by: { lhs, rhs in
                if lhs.hasActivity && !rhs.hasActivity {
                    return true
                } else if rhs.hasActivity && !lhs.hasActivity {
                    return false
                }
                
                if let lhsPresence = lhs.presence, let rhsPresence = rhs.presence {
                    return lhsPresence.status > rhsPresence.status
                } else if lhs.presence != nil {
                    return true
                } else if rhs.presence != nil {
                    return false
                }
                
                return lhs.participant < rhs.participant
            }).map { $0.participant }
            
            for i in 0 ..< sortedParticipants.count {
                if let peer = view.peers[sortedParticipants[i].peerId] {
                    let memberStatus: GroupInfoMemberStatus
                    if access.highlightAdmins {
                        switch sortedParticipants[i] {
                        case .admin:
                            memberStatus = .admin(rank: strings().chatAdminBadge)
                        case  .creator:
                            memberStatus = .creator(rank: strings().chatOwnerBadge)
                        case .member:
                            memberStatus = .member
                        }
                    } else {
                        memberStatus = .member
                    }
                    
                    var canRestrict: Bool
                    if sortedParticipants[i].peerId == arguments.context.peerId {
                        canRestrict = false
                    } else {
                        switch group.role {
                        case .creator:
                            canRestrict = true
                        case .member:
                            switch sortedParticipants[i] {
                            case .creator, .admin:
                                canRestrict = false
                            case let .member(_, invitedBy, _, _):
                                if invitedBy == arguments.context.peerId {
                                    canRestrict = true
                                } else {
                                    canRestrict = false
                                }
                            }
                        case .admin:
                            switch sortedParticipants[i] {
                            case .creator, .admin:
                                canRestrict = false
                            case .member:
                                canRestrict = true
                            }
                        }
                    }
                    
                    let editing:ShortPeerDeleting?
                    
                    if isEditing {
                        let deletable:Bool = group.canRemoveParticipant(sortedParticipants[i]) || (sortedParticipants[i].invitedBy == arguments.context.peerId && sortedParticipants[i].peerId != arguments.context.peerId)
                        editing = ShortPeerDeleting(editable: deletable)
                    } else {
                        editing = nil
                    }
                    
                    var menuItems: [ContextMenuItem] = []

                   
                    if canRestrict {
                        menuItems.append(ContextMenuItem(strings().peerInfoGroupMenuDelete, handler: {
                            arguments.removePeer(sortedParticipants[i].peerId)
                        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                    }
                    
                    usersBlock.append(.member(section: Int(sectionId), index: i, peerId: peer.id, peer: peer, presence: view.peerPresences[peer.id], activity: inputActivities[peer.id], stories: storyStats[peer.id], memberStatus: memberStatus, editing: editing, menuItems: menuItems, enabled: !disabledPeerIds.contains(peer.id), viewType: .singleItem))
                }
            }
        }
        
        if let cachedGroupData = view.cachedData as? CachedChannelData, let channel = group as? TelegramChannel {
            let participants = memberListState.list
            var updatedParticipants = participants
            let existingParticipantIds = Set(updatedParticipants.map { $0.peer.id })
            var peerPresences: [PeerId: PeerPresence] = view.peerPresences
            var peers: [PeerId: Peer] = view.peers
            var disabledPeerIds = state.removingParticipantIds
            
            
            if !state.temporaryParticipants.isEmpty {
                for participant in state.temporaryParticipants {
                    if !existingParticipantIds.contains(participant.peer.id) {
                        updatedParticipants.append(RenderedChannelParticipant(participant: .member(id: participant.peer.id, invitedAt: participant.timestamp, adminInfo: nil, banInfo: nil, rank: nil, subscriptionUntilDate: nil), peer: EnginePeer(participant.peer)))
                        if let presence = participant.presence, peerPresences[participant.peer.id] == nil {
                            peerPresences[participant.peer.id] = presence
                        }
                        if participant.peer.id == arguments.context.account.peerId {
                            peerPresences[participant.peer.id] = TelegramUserPresence(status: .present(until: Int32.max), lastActivity: Int32.max)
                        }
                        if peers[participant.peer.id] == nil {
                            peers[participant.peer.id] = participant.peer
                        }
                        disabledPeerIds.insert(participant.peer.id)
                    }
                }
            }
        
            
            var sortedParticipants = participants.filter({!$0.peer._asPeer().rawDisplayTitle.isEmpty}).map { participant in
                return (participant: participant, hasActivity: inputActivities[participant.peer.id] != nil, presence: participant.presences[participant.peer.id] as? TelegramUserPresence)
            }.sorted(by: { lhs, rhs in
                if lhs.hasActivity && !rhs.hasActivity {
                    return true
                } else if rhs.hasActivity && !lhs.hasActivity {
                    return false
                }
                
                if let lhsPresence = lhs.presence, let rhsPresence = rhs.presence {
                    return lhsPresence.status > rhsPresence.status
                } else if lhs.presence != nil {
                    return true
                } else if rhs.presence != nil {
                    return false
                }
                
                return lhs.participant < rhs.participant
            }).map { $0.participant }
            
            if let hasShowMoreButton = state.hasShowMoreButton, hasShowMoreButton, let memberCount = cachedGroupData.participantsSummary.memberCount, memberCount > 100 {
                sortedParticipants = Array(sortedParticipants.prefix(min(50, sortedParticipants.count)))
            }
            
            for i in 0 ..< sortedParticipants.count {
                let memberStatus: GroupInfoMemberStatus
                if access.highlightAdmins {
                    switch sortedParticipants[i].participant {
                    case let .creator(_, _, rank):
                        memberStatus = .creator(rank: rank ?? strings().chatOwnerBadge)
                    case let .member(_, _, adminRights, _, rank, _):
                        if adminRights != nil {
                            memberStatus = .admin(rank: rank ?? strings().chatAdminBadge)
                        } else if let rank = rank, !rank.isEmpty {
                            memberStatus = .memberTag(rank: rank)
                        } else {
                            memberStatus = .member
                        }
                    }
                } else {
                    memberStatus = .member
                }
                
                var canRestrict: Bool
                if sortedParticipants[i].peer.id == arguments.context.peerId {
                    canRestrict = false
                } else {
                    switch sortedParticipants[i].participant {
                    case .creator:
                        canRestrict = false
                    case let .member(_, _, adminRights, _, _, _):
                        if channel.hasPermission(.banMembers) {
                            canRestrict = true
                        } else {
                            canRestrict = false
                        }
                        if canRestrict {
                            if let adminRights = adminRights {
                                if adminRights.promotedBy != arguments.context.peerId && !channel.flags.contains(.isCreator) {
                                    canRestrict = false
                                }
                            }
                        }
                    }
                }

                var menuItems:[ContextMenuItem] = []

                let isParticipantCreator: Bool
                if case .creator = sortedParticipants[i].participant {
                    isParticipantCreator = true
                } else {
                    isParticipantCreator = false
                }

                let isParticipantAdmin: Bool
                if case let .member(_, _, adminRights, _, _, _) = sortedParticipants[i].participant, adminRights != nil {
                    isParticipantAdmin = true
                } else {
                    isParticipantAdmin = isParticipantCreator
                }

                let canEditTag = (sortedParticipants[i].peer.id == arguments.context.peerId &&  channel.hasPermission(.editRank)) || channel.hasPermission(.manageRanks)
                if canEditTag {
                    menuItems.append(ContextMenuItem(strings().channelMemberEditTag, handler: {
                        arguments.openInfo(sortedParticipants[i])
                    }, itemImage: MenuAnimation.menu_tag_rename.value))
                }
                
                if sortedParticipants[i].peer.id != arguments.context.peerId, !isParticipantCreator {

                    if canRestrict {
                        menuItems.append(ContextMenuItem(strings().channelMemberRestrict, handler: {
                            arguments.restrict(sortedParticipants[i])
                        }, itemImage: MenuAnimation.menu_restrict.value))
                    }

                    if channel.hasPermission(.addAdmins), !isParticipantAdmin {
                        menuItems.append(ContextMenuItem(strings().channelMemberPromote, handler: {
                            arguments.promote(sortedParticipants[i])
                        }, itemImage: MenuAnimation.menu_promote.value))
                    }
                }
                if canRestrict {
                    menuItems.append(ContextSeparatorItem())
                    menuItems.append(ContextMenuItem(strings().peerInfoGroupMenuDelete, handler: {
                        arguments.removePeer(sortedParticipants[i].peer.id)
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                
                let editing:ShortPeerDeleting?
                
                if isEditing, let group = group as? TelegramChannel {
                    let deletable:Bool = group.canRemoveParticipant(sortedParticipants[i].participant, accountId: arguments.context.account.peerId)
                    editing = ShortPeerDeleting(editable: deletable)
                } else {
                    editing = nil
                }
                
                
                let badgeAction: ((NSView)->Void)?
                if canEditTag {
                    badgeAction = { view in
                        let menu = ContextMenu()
                        menu.addItem(ContextMenuItem(strings().channelMemberEditTag, handler: {
                            arguments.openInfo(sortedParticipants[i])
                        }, itemImage: MenuAnimation.menu_tag_rename.value))
                        if let event = NSApp.currentEvent {
                            AppMenu(menu: menu).show(event: event, view: view)
                        }
                    }
                } else {
                    let tag: String
                    let badgeType: AdminBadgeType
                    switch memberStatus {
                    case let .creator(rank):
                        tag = rank
                        badgeType = .owner
                    case let .admin(rank):
                        tag = rank
                        badgeType = .admin
                    case let .memberTag(rank):
                        tag = rank
                        badgeType = .none
                    case .member:
                        tag = ""
                        badgeType = .none
                    }
                    if !tag.isEmpty {
                        badgeAction = { [weak channel] _ in
                            let origin = arguments.analyticsContext.restricting(peerId: sortedParticipants[i].peer.id).restricting(peerId: sortedParticipants[i].participant.peerId)
                            PeerInfoNavigationHooks.shared.showUserTagInfoObserved(arguments.context, tag, sortedParticipants[i].peer._asPeer().compactDisplayTitle, channel?.compactDisplayTitle ?? "", badgeType, false, analyticsContext: origin)
                        }
                    } else {
                        badgeAction = nil
                    }
                }

                usersBlock.append(GroupInfoEntry<Context>.member(section: Int(sectionId), index: i, peerId: sortedParticipants[i].peer.id, peer: sortedParticipants[i].peer._asPeer(), presence: sortedParticipants[i].presences[sortedParticipants[i].peer.id], activity: inputActivities[sortedParticipants[i].peer.id], stories: memberListState.peerStoryStats[sortedParticipants[i].peer.id], memberStatus: memberStatus, editing: editing, menuItems: menuItems, enabled: !disabledPeerIds.contains(sortedParticipants[i].peer.id), viewType: .singleItem, badgeAction: badgeAction))
            }
            
            let membersHidden: ()->Bool = {
                let membersHidden = cachedGroupData.membersHidden.knownValue?.value ?? false
                if channel.isAdmin {
                    return false
                } else {
                    return membersHidden
                }
            }
            
           
            
            if let hasShowMoreButton = state.hasShowMoreButton, hasShowMoreButton, let memberCount = cachedGroupData.participantsSummary.memberCount, memberCount > 100, !membersHidden()  {
                usersBlock.append(.showMore(section: GroupInfoSection.members.rawValue, index: sortedParticipants.count + 1, viewType: .singleItem))
            }
        }
        
    }
    
    
    applyBlock(usersBlock)
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    return entries
}

func PeerMediaGroupMembersController<Context: AccountContextProtocol>(context: Context, peerId: PeerId, editing: Signal<Bool, NoError>, analyticsContext: AnalyticsContext? = nil) -> InputDataController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    
    let initialState = GroupPeersState(temporaryParticipants: [], successfullyAddedParticipantIds: Set(), removingParticipantIds: Set(), hasShowMoreButton: true)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((GroupPeersState) -> GroupPeersState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let actionsDisposable = DisposableSet()
    
    
    var loadMoreControl: PeerChannelMemberCategoryControl?
    
    let channelMembersPromise = Promise<ChannelMemberListState>()
    
    let inputActivity = context.account.peerInputActivities(peerId: .init(peerId: peerId, category: .global))
        |> map { activities -> [PeerId : PeerInputActivity] in
            return activities.reduce([:], { (current, activity) -> [PeerId : PeerInputActivity] in
                var current = current
                current[activity.0] = activity.1
                return current
            })
    }

    if peerId.namespace == Namespaces.Peer.CloudChannel {
        let membersPresentation = origin.beginPresentation()
        let (disposable, control) = context.peerChannelMemberCategoriesContextsManager.recent(peerId: peerId, updated: { state in
            let presentation = origin.beginPresentation()
            defer { presentation.end() }
            channelMembersPromise.set(.single(state))
        })
        loadMoreControl = control
        actionsDisposable.add(ActionDisposable {
            let cleanup = origin.beginPresentation()
            defer { cleanup.end() }
            disposable.dispose()
            membersPresentation.end()
        })
    } else {
        channelMembersPromise.set(.single(.init(list: [], peerStoryStats: [:], loadingState: .ready(hasMore: false))))
    }
    
    let arguments = GroupPeersArguments(context: context, analyticsContext: origin, removePeer: { memberId in
        let targetOrigin = origin.restricting(peerId: memberId)
        let presentation = targetOrigin.beginPresentation()
        defer { presentation.end() }
        let signal = context.account.postbox.loadedPeerWithId(memberId)
            |> deliverOnMainQueue
            |> mapToSignal { peer -> Signal<Bool, NoError> in
                if targetOrigin.restricting(peerId: peer.id).isExcluded { targetOrigin.scope?.exclude() }
                let result = ValuePromise<Bool>()
                result.set(true)
                return result.get()
            }
            |> mapToSignal { value -> Signal<Void, NoError> in
                if value {
                    updateState { state in
                        var state = state
                        for i in 0 ..< state.temporaryParticipants.count {
                            if state.temporaryParticipants[i].peer.id == memberId {
                                state.temporaryParticipants.remove(at: i)
                                break
                            }
                        }
                        state.successfullyAddedParticipantIds.remove(memberId)
                        state.removingParticipantIds.insert(memberId)
                        return state
                    }
                    
                    if peerId.namespace == Namespaces.Peer.CloudChannel {
                        return context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: memberId, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: Int32.max))
                            |> afterDisposed {
                                updateState { state in
                                    var state = state
                                    state.removingParticipantIds.remove(memberId)
                                    return state
                                }
                        }
                    }
                    
                    return context.engine.peers.removePeerMember(peerId: peerId, memberId: memberId)
                        |> deliverOnMainQueue
                        |> afterDisposed {
                            updateState { state in
                                var state = state
                                state.removingParticipantIds.remove(memberId)
                                return state
                            }
                    }
                } else {
                    return .complete()
                }
        }
        actionsDisposable.add(targetOrigin.preservingPresentation(signal).start())
        
    }, showMore: {
        updateState { state in
            var state = state
            state.hasShowMoreButton = nil
            return state
        }
    }, openInfo: { participant in
        PeerInfoNavigationHooks.shared.showChannelParticipantObserved(context, peerId, participant, analyticsContext: origin)
    }, promote: { participant in
        let targetOrigin = origin.restricting(peerId: participant.peer.id).restricting(peerId: participant.participant.peerId)
        let presentation = targetOrigin.beginPresentation()
        defer { presentation.end() }
        showModal(with: ChannelAdminModalController(context, peerId: peerId, adminId: participant.participant.peerId, initialParticipant: participant.participant, updated: { _ in }, upgradedToSupergroup: { _, _ in }, analyticsContext: targetOrigin), for: context.window)
    }, restrict: { participant in
        let targetOrigin = origin.restricting(peerId: participant.peer.id)
        PeerInfoNavigationHooks.shared.showRestrictMemberObserved(context, peerId, participant.participant.peerId, participant.participant, { updatedRights in
            let presentation = targetOrigin.beginPresentation()
            defer { presentation.end() }
            _ = targetOrigin.preservingPresentation(context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: participant.participant.peerId, bannedRights: updatedRights)).start()
        }, analyticsContext: targetOrigin)
    }, openStory: { index in
        StoryModalController<Context>.ShowStories(context: context, isHidden: false, initialId: index, singlePeer: true, analyticsContext: origin)
    })
    
    

    let peerViewAndStories:Signal<(PeerView, [PeerId: PeerStoryStats]), NoError> = origin.preservingPresentation(context.account.postbox.peerView(id: peerId)) |> mapToSignal { peerView in
        if let peer = peerViewMainPeer(peerView), origin.restricting(peerId: peer.id).isExcluded {
            origin.scope?.exclude()
        }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let cachedData = peerView.cachedData as? CachedGroupData, let participants = cachedData.participants {
            let key: PostboxViewKey = .peerStoryStats(peerIds: Set(participants.participants.map(\.peerId)))
            return context.account.postbox.combinedView(keys: [key])
            |> map { views in
                if let view = views.views[key] as? PeerStoryStatsView {
                    return (peerView, view.storyStats)
                }
                return (peerView, [:])
            }
        } else {
            return .single((peerView, [:]))
        }
    }
    
    
    let dataSignal = origin.preservingPresentation(combineLatest(queue: prepareQueue, statePromise.get(), peerViewAndStories, channelMembersPromise.get(), inputActivity, editing)) |> map {
        return InputDataSignalValue(entries: groupPeersEntries(state: $0, isEditing: $4, viewAndStories: $1, inputActivities: $3, memberListState: $2, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: dataSignal, title: "")
    controller.analyticsContext = origin
    controller.analyticsScreen = .peerInfoMediaMembers
    controller.bar = .init(height: 0)
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.getBackgroundColor = {
        .clear
    }
    
    controller.didLoad = { controller, _ in
        
        controller.tableView.verticalScrollElasticity = .none

        
        controller.tableView.setScrollHandler { position in
            if let loadMoreControl = loadMoreControl {
                switch position.direction {
                case .bottom:
                    let presentation = origin.beginPresentation()
                    defer { presentation.end() }
                    context.peerChannelMemberCategoriesContextsManager.loadMore(peerId: peerId, control: loadMoreControl)
                default:
                    break
                }
            }
        }
        controller.tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: true, { [weak controller] scroll in
            let presentation = origin.beginPresentation()
            defer { presentation.end() }
            var refreshStoryPeerIds:[PeerId] = []
            controller?.tableView.enumerateVisibleItems(with: { item in
                if let item = item as? ShortPeerRowItem, let peer = item.peer as? TelegramUser {
                    refreshStoryPeerIds.append(peer.id)
                }
                return true
            })
            context.account.viewTracker.refreshStoryStatsForPeerIds(peerIds: refreshStoryPeerIds)
        }))
        
    }
    
    return controller
}
