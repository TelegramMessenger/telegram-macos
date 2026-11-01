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

    public func withUpdatedList(_ list: EngineChatList, type: ViewUpdateType? = nil) -> ChatListViewUpdate {
        ChatListViewUpdate(list: list, type: type ?? self.type, scroll: scroll, removeNextAnimation: removeNextAnimation, communityCategories: communityCategories)
    }
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

public func chatListViewForLocation(chatListLocation: ChatListControllerLocation, location: ChatListIndexRequest, filter: ChatListFilter?, account: Account, predicateTransform: ((ChatListFilterPredicate?) -> ChatListFilterPredicate?)? = nil) -> Signal<ChatListViewUpdate, NoError> {
    switch chatListLocation {
    case let .chatList(groupId):
        return communityFilterCategories(account: account)
        |> mapToSignal { communityCategories -> Signal<ChatListViewUpdate, NoError> in
            let basePredicate = chatListFilterPredicate(for: filter, communityCategories: communityCategories)
            let filterPredicate: ChatListFilterPredicate?
            if let predicateTransform = predicateTransform {
                filterPredicate = predicateTransform(basePredicate)
            } else {
                filterPredicate = basePredicate
            }
            switch location {
            case let .Initial(count, st):
                let signal = account.viewTracker.tailChatListView(groupId: groupId, filterPredicate: filterPredicate, count: count)
                return signal
                |> mapToSignal { view, updateType -> Signal<ChatListViewUpdate, NoError> in
                    return applyCommunityChatListSummaries(EngineChatList(view, accountPeerId: account.peerId), account: account)
                    |> map { list -> ChatListViewUpdate in
                        return ChatListViewUpdate(list: list, type: updateType, scroll: st, removeNextAnimation: false, communityCategories: communityCategories)
                    }
                }
            case let .Index(index, st):
                guard case let .chatList(index) = index else {
                    return .never()
                }
                var first = true
                return account.viewTracker.aroundChatListView(groupId: groupId, filterPredicate: filterPredicate, index: index, count: 100)
                |> mapToSignal { view, updateType -> Signal<ChatListViewUpdate, NoError> in
                    let genericType: ViewUpdateType
                    if first {
                        first = false
                        genericType = ViewUpdateType.UpdateVisible
                    } else {
                        genericType = updateType
                    }
                    return applyCommunityChatListSummaries(EngineChatList(view, accountPeerId: account.peerId), account: account)
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
