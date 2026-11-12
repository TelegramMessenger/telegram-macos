import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

func chatListFilterBadgeCounts(engine: TelegramEngine, filters: [ChatListFilter]) -> Signal<(Int, [(ChatListFilter, Int, Bool)]), NoError> {
    return Signal<[ChatListFilter], NoError>.single(filters)
    |> distinctUntilChanged
    |> mapToSignal { filters -> Signal<([ChatListFilter], ChatListFilterBadgeSecretChats), NoError> in
        var folderUserIds = Set<EnginePeer.Id>()
        var folderSecretChatIds = Set<EnginePeer.Id>()
        for case let .filter(_, _, _, data) in filters {
            for peerId in data.includePeers.peers + data.includePeers.pinnedPeers + data.excludePeers {
                if peerId.namespace == Namespaces.Peer.CloudUser {
                    folderUserIds.insert(peerId)
                } else if peerId.namespace == Namespaces.Peer.SecretChat {
                    folderSecretChatIds.insert(peerId)
                }
            }
        }
        let userIdsOfFolderSecretChats: Signal<[EnginePeer.Id: EnginePeer.Id], NoError> = engine.account.postbox.transaction { transaction -> [EnginePeer.Id: EnginePeer.Id] in
            var result: [EnginePeer.Id: EnginePeer.Id] = [:]
            for peerId in folderSecretChatIds {
                if let associatedPeerId = transaction.getPeer(peerId)?.associatedPeerId {
                    result[peerId] = associatedPeerId
                }
            }
            return result
        }
        let associatedPeerIdsKey: EngineRawPostboxViewKey = .associatedPeerIds(peerIds: folderUserIds)
        let associatedPeerIds: Signal<[EnginePeer.Id: Set<EnginePeer.Id>], NoError> = engine.account.postbox.combinedView(keys: [associatedPeerIdsKey])
        |> map { view -> [EnginePeer.Id: Set<EnginePeer.Id>] in
            return (view.views[associatedPeerIdsKey] as? EngineRawAssociatedPeerIdsView)?.associatedPeerIds ?? [:]
        }
        |> distinctUntilChanged
        return combineLatest(userIdsOfFolderSecretChats, associatedPeerIds)
        |> map { userIdsOfFolderSecretChats, associatedPeerIds -> ([ChatListFilter], ChatListFilterBadgeSecretChats) in
            return (filters, ChatListFilterBadgeSecretChats(userIds: folderUserIds, associatedPeerIds: associatedPeerIds, userIdsOfFolderSecretChats: userIdsOfFolderSecretChats))
        }
    }
    |> mapToSignal { filters, secretChats -> Signal<(Int, [(ChatListFilter, Int, Bool)]), NoError> in
        let secretChatsByUserId = secretChats.secretChatsByUserId
        let userIdBySecretChatId = secretChats.userIdBySecretChatId

        func expand(_ peerIds: [EnginePeer.Id]) -> [EnginePeer.Id] {
            return chatListFilterBadgePeerIds(peerIds, secretChatsByUserId: secretChatsByUserId)
        }

        var unreadCountItems: [EngineRawUnreadMessageCountsItem] = []
        unreadCountItems.append(.totalInGroup(.root))
        var additionalPeerIds = Set<EnginePeer.Id>()
        var additionalGroupIds = Set<EnginePeerGroupId>()
        for case let .filter(_, _, _, data) in filters {
            additionalPeerIds.formUnion(expand(data.includePeers.peers))
            additionalPeerIds.formUnion(expand(data.includePeers.pinnedPeers))
            additionalPeerIds.formUnion(expand(data.excludePeers))
            if !data.excludeArchived {
                additionalGroupIds.insert(Namespaces.PeerGroup.archive)
            }
        }
        additionalPeerIds.formUnion(userIdBySecretChatId.values)
        if !additionalPeerIds.isEmpty {
            for peerId in additionalPeerIds {
                unreadCountItems.append(.peer(id: peerId, handleThreads: true))
            }
        }
        for groupId in additionalGroupIds {
            unreadCountItems.append(.totalInGroup(groupId))
        }

        let globalNotificationsKey: EngineRawPostboxViewKey = .preferences(keys: Set([PreferencesKeys.globalNotifications]))
        let unreadKey: EngineRawPostboxViewKey = .unreadCounts(items: unreadCountItems)
        let associatedPeerIdsKey: EngineRawPostboxViewKey = .associatedPeerIds(peerIds: secretChats.userIds)
        var keys: [EngineRawPostboxViewKey] = []
        keys.append(globalNotificationsKey)
        keys.append(unreadKey)
        keys.append(associatedPeerIdsKey)
        for peerId in additionalPeerIds {
            keys.append(.basicPeer(peerId))
        }

        return engine.account.postbox.combinedView(keys: keys)
        |> filter { view -> Bool in
            let associatedPeerIds = (view.views[associatedPeerIdsKey] as? EngineRawAssociatedPeerIdsView)?.associatedPeerIds ?? [:]
            return associatedPeerIds == secretChats.associatedPeerIds
        }
        |> map { view -> (Int, [(ChatListFilter, Int, Bool)]) in
            guard let unreadCounts = view.views[unreadKey] as? EngineRawUnreadMessageCountsView else {
                return (0, [])
            }

            let globalNotificationSettings: GlobalNotificationSettings
            if let settingsView = view.views[globalNotificationsKey] as? EngineRawPreferencesView, let settings = settingsView.values[PreferencesKeys.globalNotifications]?.get(GlobalNotificationSettings.self) {
                globalNotificationSettings = settings
            } else {
                globalNotificationSettings = GlobalNotificationSettings.defaultSettings
            }
            let globalNotificationSettingsAccessor = globalNotificationSettings.postboxAccessor

            var result: [(ChatListFilter, Int, Bool)] = []

            var unreadChats: [EnginePeer.Id: ChatListFilterBadgeChat] = [:]

            var totalStates: [EnginePeerGroupId: EngineChatListTotalUnreadState] = [:]
            for entry in unreadCounts.entries {
                switch entry {
                case let .total(_, state):
                    totalStates[.root] = state
                case let .totalInGroup(groupId, state):
                    totalStates[groupId] = state
                case let .peer(peerId, state):
                    if let state = state, state.isUnread {
                        if let peerView = view.views[.basicPeer(peerId)] as? EngineRawBasicPeerView, let peer = peerView.peer {
                            let settingsView: EngineRawBasicPeerView
                            if let userId = userIdBySecretChatId[peerId], let userView = view.views[.basicPeer(userId)] as? EngineRawBasicPeerView {
                                settingsView = userView
                            } else {
                                settingsView = peerView
                            }

                            let tag = engine.account.postbox.seedConfiguration.peerSummaryCounterTags(peer, settingsView.isContact)

                            let isMutedByDefault = !globalNotificationSettingsAccessor.defaultIncludePeer(peer)
                            let isMuted: Bool
                            if let notificationSettings = settingsView.notificationSettings as? TelegramPeerNotificationSettings {
                                isMuted = notificationSettings.isRemovedFromTotalUnreadCount(default: isMutedByDefault)
                            } else {
                                isMuted = isMutedByDefault
                            }
                            if let groupId = peerView.groupId {
                                unreadChats[peerId] = ChatListFilterBadgeChat(tag: tag, groupId: groupId, isMuted: isMuted)
                            }
                        }
                    }
                }
            }

            let totalBadge = 0

            for filter in filters {
                var count = 0
                var unmutedUnreadCount = 0
                if case let .filter(_, _, _, data) = filter {
                    let tags = chatListFilterBadgeCategoryTags(data.categories)

                    if let totalState = totalStates[.root] {
                        for tag in tags {
                            if data.excludeMuted {
                                if let value = totalState.filteredCounters[tag] {
                                    if value.chatCount != 0 {
                                        count += Int(value.chatCount)
                                        unmutedUnreadCount += Int(value.chatCount)
                                    }
                                }
                            } else {
                                if let value = totalState.absoluteCounters[tag] {
                                    count += Int(value.chatCount)
                                }
                                if let value = totalState.filteredCounters[tag] {
                                    if value.chatCount != 0 {
                                        unmutedUnreadCount += Int(value.chatCount)
                                    }
                                }
                            }
                        }
                    }
                    if !data.excludeArchived {
                        if let totalState = totalStates[Namespaces.PeerGroup.archive] {
                            for tag in tags {
                                if data.excludeMuted {
                                    if let value = totalState.filteredCounters[tag] {
                                        if value.chatCount != 0 {
                                            count += Int(value.chatCount)
                                            unmutedUnreadCount += Int(value.chatCount)
                                        }
                                    }
                                } else {
                                    if let value = totalState.absoluteCounters[tag] {
                                        count += Int(value.chatCount)
                                    }
                                    if let value = totalState.filteredCounters[tag] {
                                        if value.chatCount != 0 {
                                            unmutedUnreadCount += Int(value.chatCount)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    let correction = chatListFilterBadgeCorrection(data: data, unreadChats: unreadChats, secretChatsByUserId: secretChatsByUserId, userIdBySecretChatId: userIdBySecretChatId)
                    count += correction.count
                    unmutedUnreadCount += correction.unmuted
                }
                result.append((filter, max(0, count), unmutedUnreadCount > 0))
            }

            return (totalBadge, result)
        }
    }
}


func chatListFilterBadgePeerIds(_ peerIds: [EnginePeer.Id], secretChatsByUserId: [EnginePeer.Id: [EnginePeer.Id]]) -> [EnginePeer.Id] {
    var result: [EnginePeer.Id] = []
    var seen = Set<EnginePeer.Id>()
    for peerId in peerIds {
        if seen.insert(peerId).inserted {
            result.append(peerId)
        }
        for secretChatId in secretChatsByUserId[peerId] ?? [] {
            if seen.insert(secretChatId).inserted {
                result.append(secretChatId)
            }
        }
    }
    return result
}

struct ChatListFilterBadgeSecretChats: Equatable {
    let userIds: Set<EnginePeer.Id>
    let associatedPeerIds: [EnginePeer.Id: Set<EnginePeer.Id>]
    let secretChatsByUserId: [EnginePeer.Id: [EnginePeer.Id]]
    let userIdBySecretChatId: [EnginePeer.Id: EnginePeer.Id]

    init(userIds: Set<EnginePeer.Id>, associatedPeerIds: [EnginePeer.Id: Set<EnginePeer.Id>], userIdsOfFolderSecretChats: [EnginePeer.Id: EnginePeer.Id]) {
        self.userIds = userIds
        self.associatedPeerIds = associatedPeerIds
        var secretChatsByUserId: [EnginePeer.Id: [EnginePeer.Id]] = [:]
        var userIdBySecretChatId = userIdsOfFolderSecretChats
        for (userId, peerIds) in associatedPeerIds {
            let secretChatIds = peerIds.filter { $0.namespace == Namespaces.Peer.SecretChat }.sorted()
            if !secretChatIds.isEmpty {
                secretChatsByUserId[userId] = secretChatIds
                for secretChatId in secretChatIds {
                    userIdBySecretChatId[secretChatId] = userId
                }
            }
        }
        self.secretChatsByUserId = secretChatsByUserId
        self.userIdBySecretChatId = userIdBySecretChatId
    }
}

struct ChatListFilterBadgeChat: Equatable {
    var tag: EnginePeerSummaryCounterTags
    var groupId: EnginePeerGroupId
    var isMuted: Bool
}

func chatListFilterBadgeCategoryTags(_ categories: ChatListFilterPeerCategories) -> [EnginePeerSummaryCounterTags] {
    var tags: [EnginePeerSummaryCounterTags] = []
    if categories.contains(.contacts) {
        tags.append(.contact)
    }
    if categories.contains(.nonContacts) {
        tags.append(.nonContact)
    }
    if categories.contains(.groups) {
        tags.append(.group)
    }
    if categories.contains(.bots) {
        tags.append(.bot)
    }
    if categories.contains(.channels) {
        tags.append(.channel)
    }
    return tags
}

func chatListFilterBadgeCorrection(data: ChatListFilterData, unreadChats: [EnginePeer.Id: ChatListFilterBadgeChat], secretChatsByUserId: [EnginePeer.Id: [EnginePeer.Id]], userIdBySecretChatId: [EnginePeer.Id: EnginePeer.Id]) -> (count: Int, unmuted: Int) {
    let tags = chatListFilterBadgeCategoryTags(data.categories)
    let pinnedPeerIds = Set(data.includePeers.pinnedPeers)
    let includePeerIds = Set(data.includePeers.peers).subtracting(pinnedPeerIds)
    let excludePeerIds = Set(data.excludePeers).subtracting(pinnedPeerIds)

    var count = 0
    var unmuted = 0
    for peerId in chatListFilterBadgePeerIds(data.includePeers.peers + data.includePeers.pinnedPeers + data.excludePeers, secretChatsByUserId: secretChatsByUserId) {
        guard let chat = unreadChats[peerId] else {
            continue
        }
        let isGroupListed: Bool
        switch chat.groupId {
        case .root:
            isGroupListed = true
        case .group:
            isGroupListed = chat.groupId == Namespaces.PeerGroup.archive && !data.excludeArchived
        }
        let isInCategories = isGroupListed && tags.contains(chat.tag)
        let isCountedByTotals = isInCategories && !(chat.isMuted && data.excludeMuted)
        let isCountedByUnmutedTotals = isInCategories && !chat.isMuted

        let identity = userIdBySecretChatId[peerId] ?? peerId
        let isShown: Bool
        if pinnedPeerIds.contains(peerId) {
            isShown = true
        } else if !isGroupListed || excludePeerIds.contains(identity) {
            isShown = false
        } else if includePeerIds.contains(identity) {
            isShown = true
        } else {
            isShown = isCountedByTotals
        }

        count += (isShown ? 1 : 0) - (isCountedByTotals ? 1 : 0)
        unmuted += (isShown && !chat.isMuted ? 1 : 0) - (isCountedByUnmutedTotals ? 1 : 0)
    }
    return (count, unmuted)
}
