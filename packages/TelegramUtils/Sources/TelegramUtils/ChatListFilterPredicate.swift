import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import Localization


public enum ChatListIndexRequest :Equatable {
    case Initial(Int, TableScrollState?)
    case Index(EngineChatList.Item.Index, TableScrollState?)
}


extension ChatListFilter {
    public var data: ChatListFilterData? {
        switch self {
        case .allChats:
            return nil
        case let .filter(_, _, _, data):
            return data
        }
    }
    
    public var isAllChats: Bool {
        switch self {
        case .allChats:
            return true
        case .filter:
            return false
        }
    }
    
    public var title: String {
        switch self {
        case .allChats:
            return strings().chatListFilterAllChats
        case let .filter(_, title, _, _):
            return title.text
        }
    }
    
    public var entities: [MessageTextEntity] {
        switch self {
        case .allChats:
            return []
        case let .filter(_, title, _, _):
            return title.entities
        }
    }
    
    public var enableAnimations: Bool {
        switch self {
        case .allChats:
            return false
        case let .filter(_, title, _, _):
            return title.enableAnimations
        }
    }
    
    public var emoticon: String? {
        switch self {
        case .allChats:
            return nil
        case let .filter(_, _, emoticon, _):
            return emoticon
        }
    }
    
    public func withUpdatedTitle(string: String, entities: [MessageTextEntity], enableAnimations: Bool) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, _, emoticon, data):
            return .filter(id: id, title: .init(text: string, entities: entities, enableAnimations: enableAnimations), emoticon: emoticon, data: data)
        }
    }
    
    public func withUpdatedTitle(_ title: ChatFolderTitle) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, _, emoticon, data):
            return .filter(id: id, title: title, emoticon: emoticon, data: data)
        }
    }
    
    public func withUpdatedEmoticon(_ string: String) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, title, _, data):
            return .filter(id: id, title: title, emoticon: string, data: data)
        }
    }
    public func withUpdatedData(_ data: ChatListFilterData) -> ChatListFilter {
        switch self {
        case .allChats:
            return self
        case let .filter(id, title, emoticon, _):
            return .filter(id: id, title: title, emoticon: emoticon, data: data)
        }
    }
}



private func communityFilterCategories(view: PeerView?) -> ChatListFilterPeerCategories {
    let fallback: ChatListFilterPeerCategories = [.groups, .channels]
    guard let view, let cachedData = view.cachedData as? CachedCommunityData, cachedData.about != nil else {
        return fallback
    }
    var result: ChatListFilterPeerCategories = []
    for linkedPeer in cachedData.linkedPeers {
        guard let peer = view.peers[linkedPeer.peerId] else {
            return fallback
        }
        if peer is TelegramGroup {
            result.insert(.groups)
        } else if let channel = peer as? TelegramChannel {
            switch channel.info {
            case .group:
                result.insert(.groups)
            case .broadcast:
                result.insert(.channels)
            }
        } else {
            return fallback
        }
    }
    return result
}

public func communityFilterCategories(account: Account) -> Signal<[PeerId: ChatListFilterPeerCategories], NoError> {
    return TelegramEngine(account: account).peers.updatedCommunitiesState()
    |> mapToSignal { state -> Signal<[PeerId: ChatListFilterPeerCategories], NoError> in
        guard let communityIds = state.communityIds, !communityIds.isEmpty else {
            return .single([:])
        }
        let keys: [PostboxViewKey] = communityIds.map { communityId in
            return .peer(peerId: communityId, components: [.cachedData])
        }
        return account.postbox.combinedView(keys: keys)
        |> take(1)
        |> mapToSignal { views -> Signal<CombinedView, NoError> in
            for communityId in communityIds {
                let key = PostboxViewKey.peer(peerId: communityId, components: [.cachedData])
                let cachedData = (views.views[key] as? PeerView)?.cachedData as? CachedCommunityData
                if cachedData?.about == nil {
                    account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)
                }
            }
            return account.postbox.combinedView(keys: keys)
        }
        |> map { views -> [PeerId: ChatListFilterPeerCategories] in
            var result: [PeerId: ChatListFilterPeerCategories] = [:]
            for communityId in communityIds {
                let key = PostboxViewKey.peer(peerId: communityId, components: [.cachedData])
                result[communityId] = communityFilterCategories(view: views.views[key] as? PeerView)
            }
            return result
        }
        |> distinctUntilChanged
    }
}

public func chatListFilterPredicate(for filter: ChatListFilter?, communityCategories: [PeerId: ChatListFilterPeerCategories]) -> ChatListFilterPredicate? {
    
    guard let filter = filter?.data else {
        return nil
    }
    let includePeers = Set(filter.includePeers.peers)
    let excludePeers = Set(filter.excludePeers)
    var includeAdditionalPeerGroupIds: [PeerGroupId] = []
    if !filter.excludeArchived {
        includeAdditionalPeerGroupIds.append(Namespaces.PeerGroup.archive)
    }
    var messageTagSummary: ChatListMessageTagSummaryResultCalculation?
    if filter.excludeRead || filter.excludeMuted {
        messageTagSummary = ChatListMessageTagSummaryResultCalculation(addCount: ChatListMessageTagSummaryResultComponent(tag: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud), subtractCount: ChatListMessageTagActionsSummaryResultComponent(type: PendingMessageActionType.consumeUnseenPersonalMessage, namespace: Namespaces.Message.Cloud))
    }

    return ChatListFilterPredicate(includePeerIds: includePeers, excludePeerIds: excludePeers, pinnedPeerIds: filter.includePeers.pinnedPeers, messageTagSummary: messageTagSummary, includeAdditionalPeerGroupIds: includeAdditionalPeerGroupIds, include: { peer, isMuted, isUnread, isContact, messageTagSummaryResult in
        if filter.excludeRead {
            var effectiveUnread = isUnread
            if let messageTagSummaryResult = messageTagSummaryResult, messageTagSummaryResult {
                effectiveUnread = true
            }
            if !effectiveUnread {
                return false
            }
        }
        if filter.excludeMuted {
            if isMuted {
                if let messageTagSummaryResult = messageTagSummaryResult, messageTagSummaryResult {
                } else {
                    return false
                }
            }

        }
        if !filter.categories.contains(.contacts) && isContact {
            if let user = peer as? TelegramUser {
                if user.botInfo == nil {
                    return false
                }
            } else if let _ = peer as? TelegramSecretChat {
                return false
            }
        }
        if !filter.categories.contains(.nonContacts) && !isContact {
            if let user = peer as? TelegramUser {
                if user.botInfo == nil {
                    return false
                }
            } else if let _ = peer as? TelegramSecretChat {
                return false
            }
        }
        if !filter.categories.contains(.bots) {
            if let user = peer as? TelegramUser {
                if user.botInfo != nil {
                    return false
                }
            }
        }
        if peer is TelegramCommunity {
            let categories = communityCategories[peer.id] ?? [.groups, .channels]
            if categories.intersection(filter.categories).isEmpty {
                return false
            }
        }
        if !filter.categories.contains(.groups) {
            if let _ = peer as? TelegramGroup {
                return false
            } else if let channel = peer as? TelegramChannel {
                if case .group = channel.info {
                    return false
                }
            }
        }
        if !filter.categories.contains(.channels) {
            if let channel = peer as? TelegramChannel {
                if case .broadcast = channel.info {
                    return false
                }
            }
        }
        return true
    })


}

public enum ChatListControllerLocation {
    case chatList(groupId: PeerGroupId)
    case forum(peerId: PeerId)
    case savedMessagesChats(peerId: EnginePeer.Id)
}

public struct ChatListViewUpdate {
    public let list: EngineChatList
    public let type: ViewUpdateType
    public let scroll: TableScrollState?
    public var removeNextAnimation: Bool
    public var communityCategories: [PeerId: ChatListFilterPeerCategories] = [:]
}



private func applyCommunityChatListSummaries(_ list: EngineChatList, account: Account) -> Signal<EngineChatList, NoError> {
    let communityIds = list.items.compactMap { item -> PeerId? in
        if let peer = item.renderedPeer.peer, case .community = peer {
            return item.renderedPeer.peerId
        }
        return nil
    }
    if communityIds.isEmpty {
        return .single(list)
    }
    return communityChatListItemSummaries(postbox: account.postbox, communityIds: communityIds)
    |> map { summaries -> EngineChatList in
        let newItems = list.items.map { item -> EngineChatList.Item in
            if let peer = item.renderedPeer.peer, case .community = peer, let summary = summaries[item.renderedPeer.peerId], summary.hasLinkedPeers {
                return item.withUpdatedCommunitySummary(messages: summary.topMessage.map { [$0] } ?? item.messages, readCounters: summary.readCounters ?? item.readCounters)
            }
            return item
        }
        return EngineChatList(items: newItems, groupItems: list.groupItems, additionalItems: list.additionalItems, hasEarlier: list.hasEarlier, hasLater: list.hasLater, isLoading: list.isLoading)
    }
}

private struct CollapsedCommunityPeers: Equatable {
    var communityIdByPeerId: [PeerId: PeerId] = [:]
    var peerIds: [PeerId] = []
}

private func collapsedCommunityPeers(account: Account) -> Signal<CollapsedCommunityPeers, NoError> {
    return TelegramEngine(account: account).peers.updatedCommunitiesState()
    |> map { state -> [PeerId] in
        return state.communityIds ?? []
    }
    |> distinctUntilChanged
    |> mapToSignal { communityIds -> Signal<CollapsedCommunityPeers, NoError> in
        if communityIds.isEmpty {
            return .single(CollapsedCommunityPeers())
        }
        let keys: [PostboxViewKey] = communityIds.map { communityId in
            return .peer(peerId: communityId, components: [.cachedData])
        }
        return account.postbox.combinedView(keys: keys)
        |> map { views -> CollapsedCommunityPeers in
            var result = CollapsedCommunityPeers()
            for communityId in communityIds {
                guard let view = views.views[.peer(peerId: communityId, components: [.cachedData])] as? PeerView else {
                    continue
                }
                guard let community = view.peers[communityId] as? TelegramCommunity, community.collapsedInDialogs == true else {
                    continue
                }
                guard let cachedData = view.cachedData as? CachedCommunityData else {
                    continue
                }
                for linkedPeer in cachedData.linkedPeers {
                    if linkedPeer.peerId == communityId || result.communityIdByPeerId[linkedPeer.peerId] != nil {
                        continue
                    }
                    result.communityIdByPeerId[linkedPeer.peerId] = communityId
                    result.peerIds.append(linkedPeer.peerId)
                }
            }
            return result
        }
        |> distinctUntilChanged
    }
}

private struct CollapsedCommunityFilterItems {
    var items: [EngineChatList.Item] = []
    var communityIdByPeerId: [PeerId: PeerId] = [:]
}

private func collapsedCommunityFilterItems(account: Account, filter: ChatListFilterData, predicate: ChatListFilterPredicate) -> Signal<CollapsedCommunityFilterItems, NoError> {
    return collapsedCommunityPeers(account: account)
    |> mapToSignal { collapsed -> Signal<CollapsedCommunityFilterItems, NoError> in
        let peerIds = collapsed.peerIds.filter { peerId in
            return !predicate.excludePeerIds.contains(peerId)
        }
        if peerIds.isEmpty {
            return .single(CollapsedCommunityFilterItems())
        }

        let topMessageKey: PostboxViewKey = .topChatMessage(peerIds: peerIds)
        let globalNotificationsKey: PostboxViewKey = .preferences(keys: Set([PreferencesKeys.globalNotifications]))
        let peerKeys: [PostboxViewKey] = peerIds.map { .basicPeer($0) }

        let views = account.postbox.combinedView(keys: [topMessageKey, globalNotificationsKey] + peerKeys)
        let readStates = account.postbox.unreadMessageCountsView(items: peerIds.map { peerId in
            return .peer(id: peerId, handleThreads: true)
        })
        |> map { view -> [PeerId: CombinedPeerReadState] in
            var result: [PeerId: CombinedPeerReadState] = [:]
            for entry in view.entries {
                if case let .peer(peerId, state) = entry, let state {
                    result[peerId] = state
                }
            }
            return result
        }

        return combineLatest(views, readStates)
        |> map { views, readStates -> CollapsedCommunityFilterItems in
            let topMessages = (views.views[topMessageKey] as? TopChatMessageView)?.messages ?? [:]
            let globalNotificationSettings = ((views.views[globalNotificationsKey] as? PreferencesView)?.values[PreferencesKeys.globalNotifications]?.get(GlobalNotificationSettings.self) ?? GlobalNotificationSettings.defaultSettings).postboxAccessor

            var result = CollapsedCommunityFilterItems(items: [], communityIdByPeerId: collapsed.communityIdByPeerId)
            for peerId in peerIds {
                guard let peerView = views.views[.basicPeer(peerId)] as? BasicPeerView, let peer = peerView.peer else {
                    continue
                }
                guard let topMessage = topMessages[peerId] else {
                    continue
                }
                let readState = readStates[peerId]
                let isMuted = resolvedIsRemovedFromTotalUnreadCount(globalSettings: globalNotificationSettings, peer: peer, peerSettings: peerView.notificationSettings)

                let pinningIndex: UInt16?
                if let index = filter.includePeers.pinnedPeers.firstIndex(of: peerId) {
                    pinningIndex = UInt16(index)
                } else if predicate.includes(peer: peer, groupId: .root, isRemovedFromTotalUnreadCount: isMuted, isUnread: readState?.isUnread ?? false, isContact: peerView.isContact, messageTagSummaryResult: nil) {
                    pinningIndex = nil
                } else {
                    continue
                }

                result.items.append(EngineChatList.Item(
                    id: .chatList(peerId),
                    index: .chatList(ChatListIndex(pinningIndex: pinningIndex, messageIndex: topMessage.index)),
                    messages: [EngineMessage(topMessage)],
                    readCounters: EnginePeerReadCounters(state: readState, isMuted: isMuted),
                    isMuted: isMuted,
                    draft: nil,
                    threadData: nil,
                    renderedPeer: EngineRenderedPeer(peer: EnginePeer(peer)),
                    presence: nil,
                    hasUnseenMentions: false,
                    hasUnseenReactions: false,
                    hasUnseenPollVotes: false,
                    forumTopicData: nil,
                    topForumTopicItems: [],
                    hasFailed: false,
                    isContact: peerView.isContact,
                    autoremoveTimeout: nil,
                    storyStats: nil,
                    displayAsTopicList: false,
                    isPremiumRequiredToMessage: false,
                    mediaDraftContentType: nil
                ))
            }
            return result
        }
    }
}

private func mergeCollapsedCommunityFilterItems(_ list: EngineChatList, extra: CollapsedCommunityFilterItems, filter: ChatListFilterData) -> EngineChatList {
    if extra.items.isEmpty {
        return list
    }
    if list.items.isEmpty && (list.hasEarlier || list.hasLater || list.isLoading) {
        return list
    }
    let existingIds = Set(list.items.map(\.id))
    let lowerBound = (list.hasEarlier || list.isLoading) ? list.items.first?.index : nil
    let upperBound = list.hasLater ? list.items.last?.index : nil

    let added = extra.items.filter { item in
        if existingIds.contains(item.id) {
            return false
        }
        if let lowerBound, item.index < lowerBound {
            return false
        }
        if let upperBound, item.index > upperBound {
            return false
        }
        return true
    }
    if added.isEmpty {
        return list
    }

    let explicitlyIncluded = Set(filter.includePeers.peers)
    var replacedCommunityIds = Set<PeerId>()
    for item in added {
        if case let .chatList(peerId) = item.id, let communityId = extra.communityIdByPeerId[peerId], !explicitlyIncluded.contains(communityId) {
            replacedCommunityIds.insert(communityId)
        }
    }

    var items = list.items.filter { item in
        if case let .chatList(peerId) = item.id {
            return !replacedCommunityIds.contains(peerId)
        }
        return true
    }
    items.append(contentsOf: added)
    items.sort(by: { $0.index < $1.index })

    return EngineChatList(items: items, groupItems: list.groupItems, additionalItems: list.additionalItems, hasEarlier: list.hasEarlier, hasLater: list.hasLater, isLoading: list.isLoading)
}

private func chatListWithCollapsedCommunityPeers(_ view: Signal<(ChatListView, ViewUpdateType), NoError>, account: Account, filter: ChatListFilter?, predicate: ChatListFilterPredicate?) -> Signal<(EngineChatList, ViewUpdateType), NoError> {
    let mapped = view
    |> map { view, updateType -> (EngineChatList, ViewUpdateType) in
        return (EngineChatList(view, accountPeerId: account.peerId), updateType)
    }
    guard let data = filter?.data, let predicate else {
        return mapped
    }
    return combineLatest(mapped, collapsedCommunityFilterItems(account: account, filter: data, predicate: predicate))
    |> map { value, extra -> (EngineChatList, ViewUpdateType) in
        return (mergeCollapsedCommunityFilterItems(value.0, extra: extra, filter: data), value.1)
    }
}

public func chatListViewForLocation(chatListLocation: ChatListControllerLocation, location: ChatListIndexRequest, filter: ChatListFilter?, account: Account) -> Signal<ChatListViewUpdate, NoError> {
    switch chatListLocation {
    case let .chatList(groupId):
        return communityFilterCategories(account: account)
        |> mapToSignal { communityCategories -> Signal<ChatListViewUpdate, NoError> in
            let filterPredicate = chatListFilterPredicate(for: filter, communityCategories: communityCategories)
            switch location {
            case let .Initial(count, st):
                let signal = account.viewTracker.tailChatListView(groupId: groupId, filterPredicate: filterPredicate, count: count)
                return chatListWithCollapsedCommunityPeers(signal, account: account, filter: groupId == .root ? filter : nil, predicate: filterPredicate)
                |> mapToSignal { list, updateType -> Signal<ChatListViewUpdate, NoError> in
                    return applyCommunityChatListSummaries(list, account: account)
                    |> map { list -> ChatListViewUpdate in
                        return ChatListViewUpdate(list: list, type: updateType, scroll: st, removeNextAnimation: false, communityCategories: communityCategories)
                    }
                }
            case let .Index(index, st):
                guard case let .chatList(index) = index else {
                    return .never()
                }
                var first = true
                let signal = account.viewTracker.aroundChatListView(groupId: groupId, filterPredicate: filterPredicate, index: index, count: 100)
                return chatListWithCollapsedCommunityPeers(signal, account: account, filter: groupId == .root ? filter : nil, predicate: filterPredicate)
                |> mapToSignal { list, updateType -> Signal<ChatListViewUpdate, NoError> in
                    let genericType: ViewUpdateType
                    if first {
                        first = false
                        genericType = ViewUpdateType.UpdateVisible
                    } else {
                        genericType = updateType
                    }
                    return applyCommunityChatListSummaries(list, account: account)
                    |> map { list -> ChatListViewUpdate in
                        return ChatListViewUpdate(list: list, type: genericType, scroll: st, removeNextAnimation: st != nil, communityCategories: communityCategories)
                    }
                }
            }
        }
    case let .forum(peerId):
        let viewKey: PostboxViewKey = .messageHistoryThreadIndex(
                   id: peerId,
                   summaryComponents: ChatListEntrySummaryComponents(
                       components: [
                           ChatListEntryMessageTagSummaryKey(
                               tag: .unseenPersonalMessage,
                               actionType: PendingMessageActionType.consumeUnseenPersonalMessage
                           ): ChatListEntrySummaryComponents.Component(
                               tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                               actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                           ),
                           ChatListEntryMessageTagSummaryKey(
                               tag: .unseenReaction,
                               actionType: PendingMessageActionType.readReactionOrPollVote
                           ): ChatListEntrySummaryComponents.Component(
                               tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                               actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                           )
                       ]
                   )
               )
        var isFirst = false
        return account.postbox.combinedView(keys: [viewKey])
        |> map { views -> ChatListViewUpdate in
            guard let view = views.views[viewKey] as? MessageHistoryThreadIndexView else {
                preconditionFailure()
            }
            
            var items: [EngineChatList.Item] = []
            for item in view.items {
                guard let peer = view.peer else {
                    continue
                }
                guard let data = item.info.get(MessageHistoryThreadData.self) else {
                    continue
                }
                
                let defaultPeerNotificationSettings: TelegramPeerNotificationSettings = (view.peerNotificationSettings as? TelegramPeerNotificationSettings) ?? .defaultSettings

                var hasUnseenMentions = false
                               
                var isMuted = false
                switch data.notificationSettings.muteState {
                case .muted:
                    isMuted = true
                case .unmuted:
                    isMuted = false
                case .default:
                    if case .default = data.notificationSettings.muteState {
                        if case .muted = defaultPeerNotificationSettings.muteState {
                            isMuted = true
                        }
                    }
                }

                
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenPersonalMessage,
                    actionType: PendingMessageActionType.consumeUnseenPersonalMessage
                )] {
                    hasUnseenMentions = (info.tagSummaryCount ?? 0) > (info.actionsSummaryCount ?? 0)
                }
                
                var hasUnseenReactions = false
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenReaction,
                    actionType: PendingMessageActionType.readReactionOrPollVote
                )] {
                    hasUnseenReactions = (info.tagSummaryCount ?? 0) != 0// > (info.actionsSummaryCount ?? 0)
                }
                
                var hasUnseenVotes = false
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenPollVote,
                    actionType: PendingMessageActionType.readReactionOrPollVote
                )] {
                    hasUnseenVotes = (info.tagSummaryCount ?? 0) != 0// > (info.actionsSummaryCount ?? 0)
                }
                
                let pinnedIndex: EngineChatList.Item.PinnedIndex
                if let index = item.pinnedIndex {
                    pinnedIndex = .index(index)
                } else {
                    pinnedIndex = .none
                }
                
                let readCounters = EnginePeerReadCounters(state: CombinedPeerReadState(states: [(Namespaces.Message.Cloud, .idBased(maxIncomingReadId: 1, maxOutgoingReadId: 1, maxKnownId: 1, count: data.incomingUnreadCount, markedUnread: false))]), isMuted: false)
                               
                var draft: EngineChatList.Draft?
                if let embeddedState = item.embeddedInterfaceState, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            draft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
                               
                items.append(EngineChatList.Item(
                    id: .forum(item.id),
                    index: .forum(pinnedIndex: pinnedIndex, timestamp: item.index.timestamp, threadId: item.id, namespace: item.index.id.namespace, id: item.index.id.id),
                    messages: item.topMessage.flatMap { [EngineMessage($0)] } ?? [],
                    readCounters: readCounters,
                    isMuted: isMuted,
                    draft: draft,
                    threadData: data,
                    renderedPeer: EngineRenderedPeer(peer: EnginePeer(peer)),
                    presence: nil,
                    hasUnseenMentions: hasUnseenMentions,
                    hasUnseenReactions: hasUnseenReactions,
                    hasUnseenPollVotes: hasUnseenVotes,
                    forumTopicData: nil,
                    topForumTopicItems: [],
                    hasFailed: false,
                    isContact: false,
                    autoremoveTimeout: nil,
                    storyStats: nil,
                    displayAsTopicList: false,
                    isPremiumRequiredToMessage: false,
                    mediaDraftContentType: nil
                ))

            }
            
            let list = EngineChatList(
                items: items.reversed(),
                groupItems: [],
                additionalItems: [],
                hasEarlier: false,
                hasLater: false,
                isLoading: view.isLoading
            )
            
            let type: ViewUpdateType
            if isFirst {
                type = .Initial
            } else {
                type = .Generic
            }
            isFirst = false
            return ChatListViewUpdate(list: list, type: type, scroll: nil, removeNextAnimation: false)
        }
    case let .savedMessagesChats(peerId):
        let viewKey: PostboxViewKey = .savedMessagesIndex(peerId: peerId)
        let interfaceStateKey: PostboxViewKey = .chatInterfaceState(peerId: peerId)


        var isFirst = true
        return account.postbox.combinedView(keys: [viewKey, interfaceStateKey])
        |> map { views -> ChatListViewUpdate in
            guard let view = views.views[viewKey] as? MessageHistorySavedMessagesIndexView else {
                preconditionFailure()
            }
            
            var draft: EngineChatList.Draft?
            if let interfaceStateView = views.views[interfaceStateKey] as? ChatInterfaceStateView {
                if let embeddedState = interfaceStateView.value, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            draft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
            }

            
            var items: [EngineChatList.Item] = []
            for item in view.items {
                guard let sourcePeer = item.peer else {
                    continue
                }
                
                let sourceId = PeerId(item.id)
                
                var messages: [EngineMessage] = []
                if let topMessage = item.topMessage {
                    messages.append(EngineMessage(topMessage))
                }
                
                let mappedMessageIndex = MessageIndex(id: MessageId(peerId: sourceId, namespace: item.index.id.namespace, id: item.index.id.id), timestamp: item.index.timestamp)
                
                items.append(EngineChatList.Item(
                    id: .chatList(sourceId),
                    index: .chatList(ChatListIndex(pinningIndex: item.pinnedIndex.flatMap(UInt16.init), messageIndex: mappedMessageIndex)),
                    messages: messages,
                    readCounters: EnginePeerReadCounters(
                        incomingReadId: 0, outgoingReadId: 0, count: Int32(item.unreadCount), markedUnread: false),
                    isMuted: false,
                    draft: sourceId == account.peerId ? draft : nil,
                    threadData: nil,
                    renderedPeer: EngineRenderedPeer(peer: EnginePeer(sourcePeer)),
                    presence: nil,
                    hasUnseenMentions: false,
                    hasUnseenReactions: false,
                    hasUnseenPollVotes: false,
                    forumTopicData: nil,
                    topForumTopicItems: [],
                    hasFailed: false,
                    isContact: false,
                    autoremoveTimeout: nil,
                    storyStats: nil,
                    displayAsTopicList: false,
                    isPremiumRequiredToMessage: false,
                    mediaDraftContentType: nil
                ))
            }
            
            let list = EngineChatList(
                items: items.reversed(),
                groupItems: [],
                additionalItems: [],
                hasEarlier: false,
                hasLater: false,
                isLoading: view.isLoading
            )
            
            let type: ViewUpdateType
            if isFirst {
                type = .Initial
            } else {
                type = .Generic
            }
            isFirst = false
            return ChatListViewUpdate(list: list, type: type, scroll: nil, removeNextAnimation: false)
        }
    }
}
