import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import LocalAnimations
import InputDataUI
import InAppSettings
import AlertsUI

struct SearchPeerMenuState {
    let canOpenProfile: Bool
    let canManageChat: Bool
    let canPin: Bool
    let isMuted: Bool
    let isPinned: Bool
}

struct SearchPeerMenuActions {
    let openProfile: () -> Void
    let toggleMute: () -> Void
    let mute: (Int32) -> Void
    let muteUntil: () -> Void
    let togglePin: () -> Void
}

struct SearchPeerFolderState {
    let groupId: PeerGroupId?
    let isMuted: Bool
    let isUnread: Bool
    let isContact: Bool
    let hasUnreadMention: Bool
    let communityCategories: [PeerId: ChatListFilterPeerCategories]

    var pinGroupId: PeerGroupId {
        return self.groupId ?? .root
    }
}

enum SearchPeerFolderUpdate: Equatable {
    case updated(ChatListFilterData)
    case includeLimitReached
    case excludeLimitReached
    case unchanged
}

func searchPeerFolderContains(_ filter: ChatListFilter, peer: Peer, state: SearchPeerFolderState) -> Bool {
    guard let predicate = chatListFilterPredicate(for: filter, communityCategories: state.communityCategories) else {
        return false
    }
    if predicate.pinnedPeerIds.contains(peer.id) {
        return true
    }
    guard state.groupId != nil || predicate.includePeerIds.contains(peer.id) else {
        return false
    }
    return predicate.includes(peer: peer, groupId: state.pinGroupId, isRemovedFromTotalUnreadCount: state.isMuted, isUnread: state.isUnread, isContact: state.isContact, messageTagSummaryResult: state.hasUnreadMention)
}

func searchPeerFolderUpdate(_ filter: ChatListFilter, peer: Peer, state: SearchPeerFolderState, limit: Int) -> SearchPeerFolderUpdate {
    guard var data = filter.data else {
        return .unchanged
    }
    if searchPeerFolderContains(filter, peer: peer, state: state) {
        _ = data.includePeers.removePeer(peer.id)
        if !data.isShared, searchPeerFolderContains(filter.withUpdatedData(data), peer: peer, state: state) {
            guard data.excludePeers.contains(peer.id) || data.excludePeers.count < limit else {
                return .excludeLimitReached
            }
            _ = data.addExcludePeer(peerId: peer.id)
        }
    } else {
        data.excludePeers.removeAll(where: { $0 == peer.id })
        if !searchPeerFolderContains(filter.withUpdatedData(data), peer: peer, state: state) {
            guard data.includePeers.peers.contains(peer.id) || data.includePeers.peers.count < limit else {
                return .includeLimitReached
            }
            _ = data.addIncludePeer(peerId: peer.id)
        }
    }
    return .updated(data)
}

private struct SearchPeerContextMenuSnapshot {
    let peer: Peer
    let state: SearchPeerMenuState
    let notificationPeerId: PeerId
    let folders: SearchPeerFolderState
}

func searchPeerMenuItems(state: SearchPeerMenuState, profileTitle: String, actions: SearchPeerMenuActions, readItem: ContextMenuItem?, folders: [ContextMenuItem], remove: ContextMenuItem?) -> [ContextMenuItem] {
    var items: [ContextMenuItem] = []
    if state.canOpenProfile {
        items.append(ContextMenuItem(profileTitle, handler: actions.openProfile, itemImage: MenuAnimation.menu_open_profile.value))
    }
    if let readItem {
        items.append(readItem)
    }
    if state.canManageChat {
        let muteItem = ContextMenuItem(state.isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: actions.toggleMute, itemImage: state.isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value)
        if !state.isMuted {
            let menu = ContextMenu()
            menu.items = [
                ContextMenuItem(strings().chatListMute1Hour, handler: { actions.mute(60 * 60) }, itemImage: MenuAnimation.menu_mute_for_1_hour.value),
                ContextMenuItem(strings().chatListMute8Hours, handler: { actions.mute(60 * 60 * 8) }, itemImage: MenuAnimation.menu_mute_for_1_hour.value),
                ContextMenuItem(strings().chatListMute3Days, handler: { actions.mute(60 * 60 * 24 * 3) }, itemImage: MenuAnimation.menu_mute_for_2_days.value),
                ContextSeparatorItem(),
                ContextMenuItem(strings().chatListMuteUntil, handler: actions.muteUntil, itemImage: MenuAnimation.menu_schedule_message.value),
                ContextMenuItem(strings().chatListMuteForever, handler: { actions.mute(Int32.max) }, itemImage: MenuAnimation.menu_mute.value)
            ]
            muteItem.submenu = menu
        }
        items.append(muteItem)
    }
    if state.canPin || !folders.isEmpty {
        if !items.isEmpty {
            items.append(ContextSeparatorItem())
        }
        if state.canPin {
            items.append(ContextMenuItem(state.isPinned ? strings().chatListContextUnpin : strings().chatListContextPin, handler: actions.togglePin, itemImage: state.isPinned ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
        }
        if !folders.isEmpty {
            let item = ContextMenuItem(strings().chatListFilterAddToFolder, itemImage: MenuAnimation.menu_add_to_folder.value)
            let submenu = ContextMenu()
            submenu.items = folders
            item.submenu = submenu
            items.append(item)
        }
    }
    if let remove {
        if !items.isEmpty {
            items.append(ContextSeparatorItem())
        }
        items.append(remove)
    }
    return items
}

func searchPeerOpenProfileAction(adPeer: AdPeer?, markAdAction: @escaping (Data, Bool, Bool) -> Void, openProfile: @escaping () -> Void) -> () -> Void {
    return {
        if let adPeer {
            markAdAction(adPeer.opaqueId, false, false)
        }
        openProfile()
    }
}

func searchPeerNotificationPeerId(_ peer: Peer) -> PeerId {
    return peer.notificationSettingsPeerId ?? peer.id
}

func searchSavedPeerMenuItems(profileTitle: String?, isPinned: Bool, openProfile: @escaping () -> Void, togglePin: @escaping () -> Void) -> [ContextMenuItem] {
    var items: [ContextMenuItem] = []
    if let profileTitle {
        items.append(ContextMenuItem(profileTitle, handler: openProfile, itemImage: MenuAnimation.menu_open_profile.value))
        items.append(ContextSeparatorItem())
    }
    items.append(ContextMenuItem(isPinned ? strings().chatListContextUnpin : strings().chatListContextPin, handler: togglePin, itemImage: isPinned ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
    return items
}

func searchPeerContextMenuItems(peer: Peer, context: any AccountContextProtocol, target: SearchControllerTarget? = nil, canPin: Bool = false, remove: ContextMenuItem? = nil, adPeer: AdPeer? = nil) -> Signal<[ContextMenuItem], NoError> {
    if case let .savedMessages(savedPeerId)? = target {
        let threadId = peer.id.toInt64()
        return context.account.postbox.transaction { transaction in
            transaction.getPeerPinnedThreads(peerId: savedPeerId).contains(threadId)
        } |> deliverOnMainQueue |> map { isPinned in
            searchSavedPeerMenuItems(profileTitle: peer.id == context.peerId ? nil : (peer is TelegramUser ? strings().exportedInvitationContextOpenProfile : strings().chatContextPeerOpenInfo), isPinned: isPinned, openProfile: {
                ChatListUIHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peer.id)
            }, togglePin: {
                _ = (context.engine.peers.toggleForumChannelTopicPinned(id: savedPeerId, threadId: threadId) |> deliverOnMainQueue).start(error: { error in
                    switch error {
                    case let .limitReached(count):
                        alert(for: context.window, info: strings().chatListContextPinErrorTopicsOther(count))
                    default:
                        alert(for: context.window, info: strings().unknownError)
                    }
                })
            })
        }
    }
    let peerId = peer.id
    let categories: Signal<[PeerId: ChatListFilterPeerCategories], NoError> = peer is TelegramCommunity ? (communityFilterCategories(account: context.account) |> take(1)) : .single([:])
    let snapshotSignal = combineLatest(context.engine.data.get(TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId)), categories)
    |> mapToSignal { readCounters, communityCategories in
        context.account.postbox.transaction { transaction -> SearchPeerContextMenuSnapshot in
            let currentPeer = transaction.getPeer(peerId) ?? peer
            let chatIndex = transaction.getPeerChatListIndex(peerId)
            let notificationPeerId = searchPeerNotificationPeerId(currentPeer)
            let settings = transaction.getPeerNotificationSettings(id: notificationPeerId)
            let isMuted: Bool
            if let settings = settings as? TelegramPeerNotificationSettings, case let .muted(until) = settings.muteState {
                isMuted = until > context.timestamp
            } else {
                isMuted = resolvedIsRemovedFromTotalUnreadCount(globalSettings: transaction.getGlobalNotificationSettings(), peer: currentPeer, peerSettings: settings)
            }
            let mentionCount = transaction.getMessageTagSummary(peerId: peerId, threadId: nil, tagMask: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud, customTag: nil)?.count ?? 0
            let pendingMentionCount = transaction.getPendingMessageActionsSummary(peerId: peerId, type: .consumeUnseenPersonalMessage, namespace: Namespaces.Message.Cloud) ?? 0
            let folders = SearchPeerFolderState(
                groupId: chatIndex?.0 ?? transaction.getPeerChatListInclusion(peerId).groupId,
                isMuted: isMuted,
                isUnread: readCounters.isUnread,
                isContact: transaction.isPeerContact(peerId: notificationPeerId),
                hasUnreadMention: mentionCount > pendingMentionCount,
                communityCategories: communityCategories
            )
            let isSelf = peerId == context.peerId
            let state = SearchPeerMenuState(
                canOpenProfile: !isSelf,
                canManageChat: !isSelf && chatIndex != nil,
                canPin: canPin,
                isMuted: isMuted,
                isPinned: transaction.getPinnedItemIds(groupId: folders.pinGroupId).contains(.peer(peerId))
            )
            return SearchPeerContextMenuSnapshot(peer: currentPeer, state: state, notificationPeerId: notificationPeerId, folders: folders)
        }
    }
    let readItem = searchPeerReadMenuItem(context: context, peerId: peerId, target: target ?? .common(.root))
    return combineLatest(snapshotSignal, chatListFilterPreferences(engine: context.engine), readItem)
    |> take(1)
    |> deliverOnMainQueue
    |> map { snapshot, filters, readItem in
        let peer = snapshot.peer
        let state = snapshot.state
        let notificationPeerId = snapshot.notificationPeerId
        let storePeer = context.account.postbox.transaction { transaction -> Void in
            if transaction.getPeer(peer.id) == nil {
                updatePeersCustom(transaction: transaction, peers: [peer], update: { _, updated in updated })
            }
        } |> deliverOnMainQueue
        let actions = SearchPeerMenuActions(openProfile: searchPeerOpenProfileAction(adPeer: adPeer, markAdAction: context.engine.messages.markAdAction, openProfile: {
            _ = storePeer.start(completed: {
                ChatListUIHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peer.id)
            })
        }), toggleMute: {
            ChatListRowItem.toggleMuted(context: context, peerId: notificationPeerId, isMuted: state.isMuted, threadId: nil, threadData: nil)
        }, mute: { interval in
            _ = context.engine.peers.updatePeerMuteSetting(peerId: notificationPeerId, threadId: nil, muteInterval: interval).start()
        }, muteUntil: {
            FeatureNavigationHooks.shared.selectDate(context, context.window, nil, nil, .date(title: strings().chatListMuteUntilTitle, doneTitle: strings().chatListMuteUntilOK), { date, _ in
                let interval = Int32(clamping: Int64(max(0, date.timeIntervalSince1970 - Date().timeIntervalSince1970)))
                _ = context.engine.peers.updatePeerMuteSetting(peerId: notificationPeerId, threadId: nil, muteInterval: interval).start()
            })
        }, togglePin: {
            _ = (storePeer |> mapToSignal { _ in snapshotSignal } |> deliverOnMainQueue).start(next: { current in
                ChatListRowItem.togglePinned(context: context, peerId: peerId, isPinned: current.state.isPinned, mode: .chat, filter: .allChats, associatedGroupId: EngineChatList.Group(current.folders.pinGroupId))
            })
        })
        var folders: [ContextMenuItem] = []
        if peerId.namespace != Namespaces.Peer.SecretChat {
            for filter in filters.list {
                guard filter.data != nil else { continue }
                let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
                folders.append(ContextMenuItem(filter.title, handler: {
                    let limit = context.isPremium ? context.premiumLimits.dialog_filters_chats_limit_premium : context.premiumLimits.dialog_filters_chats_limit_default
                    _ = (storePeer |> mapToSignal { _ in snapshotSignal } |> mapToSignal { current -> Signal<SearchPeerFolderUpdate, NoError> in
                        let result = Atomic<SearchPeerFolderUpdate>(value: .unchanged)
                        return context.engine.peers.updateChatListFiltersInteractively { list in
                            var list = list
                            if let index = list.firstIndex(where: { ChatListUIHooks.shared.chatListFilterId($0) == filterId }) {
                                let update = searchPeerFolderUpdate(list[index], peer: current.peer, state: current.folders, limit: limit)
                                _ = result.swap(update)
                                if case let .updated(data) = update {
                                    list[index] = list[index].withUpdatedData(data)
                                }
                            }
                            return list
                        } |> map { _ in result.with { $0 } }
                    } |> deliverOnMainQueue).start(next: { result in
                        switch result {
                        case .includeLimitReached:
                            if context.isPremium {
                                alert(for: context.window, info: strings().chatListFilterIncludeLimitReached)
                            } else {
                                FeatureNavigationHooks.shared.showPremiumLimit(context, .chatInFolders)
                            }
                        case .excludeLimitReached:
                            alert(for: context.window, info: strings().chatListFilterExcludeLimitReachedNew(limit))
                        case .updated, .unchanged:
                            break
                        }
                    })
                }, state: searchPeerFolderContains(filter, peer: peer, state: snapshot.folders) ? .on : nil))
            }
        }
        return searchPeerMenuItems(state: state, profileTitle: peer is TelegramUser ? strings().exportedInvitationContextOpenProfile : strings().chatContextPeerOpenInfo, actions: actions, readItem: readItem, folders: folders, remove: remove)
    }
}
