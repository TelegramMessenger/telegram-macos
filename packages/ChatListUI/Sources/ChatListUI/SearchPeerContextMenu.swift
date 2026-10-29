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
    let canMarkRead: Bool
    let canMarkUnread: Bool
    let canPin: Bool
    var isUnread: Bool
    let isMuted: Bool
    let isPinned: Bool
}

struct SearchPeerMenuActions {
    let openProfile: () -> Void
    let markRead: (Bool) -> Void
    let toggleMute: () -> Void
    let mute: (Int32) -> Void
    let muteUntil: () -> Void
    let togglePin: () -> Void
}

func searchPeerMenuItems(state: SearchPeerMenuState, profileTitle: String, actions: SearchPeerMenuActions, folders: [ContextMenuItem], remove: ContextMenuItem?) -> [ContextMenuItem] {
    var items: [ContextMenuItem] = []
    if state.canOpenProfile {
        items.append(ContextMenuItem(profileTitle, handler: actions.openProfile, itemImage: MenuAnimation.menu_open_profile.value))
    }
    if state.canManageChat {
        if state.isUnread ? state.canMarkRead : state.canMarkUnread {
            items.append(ContextMenuItem(state.isUnread ? strings().chatListContextMaskAsRead : strings().chatListContextMaskAsUnread, handler: {
                actions.markRead(state.isUnread)
            }, itemImage: state.isUnread ? MenuAnimation.menu_read.value : MenuAnimation.menu_unread.value))
        }
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

func searchPeerContextMenuItems(peer: Peer, context: any AccountContextProtocol, target: SearchControllerTarget? = nil, canPin: Bool = false, remove: ContextMenuItem? = nil) -> Signal<[ContextMenuItem], NoError> {
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
    let timestamp = context.timestamp
    let snapshot = context.account.postbox.transaction { transaction -> (Peer, SearchPeerMenuState, PeerId) in
        let currentPeer = transaction.getPeer(peer.id) ?? peer
        let chatIndex = transaction.getPeerChatListIndex(peerId)
        let notificationPeerId = searchPeerNotificationPeerId(currentPeer)
        let settings = transaction.getPeerNotificationSettings(id: notificationPeerId)
        let isMuted: Bool
        if let settings = settings as? TelegramPeerNotificationSettings, case let .muted(until) = settings.muteState {
            isMuted = until > timestamp
        } else {
            isMuted = resolvedIsRemovedFromTotalUnreadCount(globalSettings: transaction.getGlobalNotificationSettings(), peer: currentPeer, peerSettings: settings)
        }
        let readState = transaction.getCombinedPeerReadState(peerId)
        let displayAsRegularChat = (currentPeer as? TelegramChannel)?.flags.contains(.displayForumAsTabs) == true || (transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData)?.viewForumAsMessages.knownValue == true
        let canMarkUnread = peerId.namespace != Namespaces.Peer.SecretChat && (!currentPeer.isForumOrMonoForum || displayAsRegularChat)
        let isSelf = peerId == context.peerId
        let state = SearchPeerMenuState(
            canOpenProfile: !isSelf,
            canManageChat: !isSelf && chatIndex != nil,
            canMarkRead: peerId.namespace != Namespaces.Peer.SecretChat,
            canMarkUnread: canMarkUnread,
            canPin: canPin,
            isUnread: readState?.isUnread ?? false,
            isMuted: isMuted,
            isPinned: transaction.getPinnedItemIds(groupId: .root).contains(.peer(peerId))
        )
        return (currentPeer, state, notificationPeerId)
    }
    let readCounters = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId))
    return combineLatest(snapshot, chatListFilterPreferences(engine: context.engine) |> take(1), readCounters)
    |> deliverOnMainQueue
    |> map { snapshot, filters, readCounters in
        let (peer, snapshotState, notificationPeerId) = snapshot
        var state = snapshotState
        state.isUnread = state.isUnread || readCounters.isUnread
        let storePeer = context.account.postbox.transaction { transaction -> Void in
            if transaction.getPeer(peer.id) == nil {
                updatePeersCustom(transaction: transaction, peers: [peer], update: { _, updated in updated })
            }
        } |> deliverOnMainQueue
        let actions = SearchPeerMenuActions(openProfile: {
            _ = storePeer.start(completed: {
                ChatListUIHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peer.id)
            })
        }, markRead: { read in
            if read {
                ChatListRowItem.markAsRead(context: context, peerId: peerId)
            } else {
                ChatListRowItem.markAsUnread(context: context, peerId: peerId)
            }
        }, toggleMute: {
            ChatListRowItem.toggleMuted(context: context, peerId: notificationPeerId, isMuted: state.isMuted, threadId: nil)
        }, mute: { interval in
            _ = context.engine.peers.updatePeerMuteSetting(peerId: notificationPeerId, threadId: nil, muteInterval: interval).start()
        }, muteUntil: {
            FeatureNavigationHooks.shared.selectDate(context, context.window, nil, nil, .date(title: strings().chatListMuteUntilTitle, doneTitle: strings().chatListMuteUntilOK), { date, _ in
                let interval = Int32(clamping: Int64(max(0, date.timeIntervalSince1970 - Date().timeIntervalSince1970)))
                _ = context.engine.peers.updatePeerMuteSetting(peerId: notificationPeerId, threadId: nil, muteInterval: interval).start()
            })
        }, togglePin: {
            _ = (storePeer |> mapToSignal { _ in
                context.engine.peers.toggleItemPinned(location: .group(.root), itemId: .peer(peerId))
            } |> deliverOnMainQueue).start(next: { result in
                if case .limitExceeded = result {
                    verifyAlert_button(for: context.window, information: strings().chatListContextPinErrorNew2, ok: strings().alertOK, cancel: "", option: strings().chatListContextPinErrorNewSetupFolders, successHandler: { result in
                        if case .thrid = result {
                            context.bindings.rootNavigation().push(ChatListUIHooks.shared.makeChatListFiltersListController(context))
                        }
                    })
                }
            })
        })
        var folders: [ContextMenuItem] = []
        if peerId.namespace != Namespaces.Peer.SecretChat {
            for filter in filters.list {
                guard let data = filter.data else { continue }
                let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
                folders.append(ContextMenuItem(filter.title, handler: {
                    _ = (storePeer |> mapToSignal { _ in context.engine.peers.updateChatListFiltersInteractively { list in
                        var list = list
                        for (index, folder) in list.enumerated() {
                            if ChatListUIHooks.shared.chatListFilterId(folder) == filterId, var data = folder.data {
                                if data.includePeers.peers.contains(peerId) {
                                    var peers = data.includePeers.peers
                                    peers.removeAll(where: { $0 == peerId })
                                    data.includePeers.setPeers(peers)
                                } else {
                                    data.excludePeers.removeAll(where: { $0 == peerId })
                                    data.includePeers.setPeers(data.includePeers.peers + [peerId])
                                }
                                list[index] = folder.withUpdatedData(data)
                            }
                        }
                        return list
                    } }).start()
                }, state: data.includePeers.peers.contains(peerId) ? .on : nil))
            }
        }
        return searchPeerMenuItems(state: state, profileTitle: peer is TelegramUser ? strings().exportedInvitationContextOpenProfile : strings().chatContextPeerOpenInfo, actions: actions, folders: folders, remove: remove)
    }
}
