import Foundation
import FocusFilterCore
import Localization
import Postbox
import TelegramCore
import TelegramUtils

func focusCatalogTitle(_ peer: Peer) -> String {
    if let user = peer as? TelegramUser {
        let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? strings().peerDeletedUser : name
    }
    return peer.displayTitle
}

func focusTelegramChatId(_ peerId: PeerId) -> Int64? {
    let id = peerId.id._internalGetInt64Value()
    switch peerId.namespace {
    case Namespaces.Peer.CloudUser:
        return (1...0xffffffffff).contains(id) ? id : nil
    case Namespaces.Peer.CloudGroup:
        return (1...999_999_999_999).contains(id) ? -id : nil
    case Namespaces.Peer.CloudChannel:
        guard (1...997_852_516_352).contains(id) || (1_002_147_483_649...3_000_000_000_000).contains(id) else { return nil }
        return -(1_000_000_000_000 + id)
    case Namespaces.Peer.SecretChat:
        return (Int64(Int32.min)...Int64(Int32.max)).contains(id) ? id - 2_000_000_000_000 : nil
    default:
        return nil
    }
}

func focusAccountCatalog(transaction: Transaction, accountId: Int64, filters: [ChatListFilter], communityCategories: [PeerId: ChatListFilterPeerCategories]) -> FocusFilterCatalog {
    let groups: [PeerGroupId] = [.root, Namespaces.PeerGroup.archive]
    var peers: [PeerId: (peer: Peer, groupId: PeerGroupId)] = [:]
    for groupId in groups {
        for peer in transaction.getChatListPeers(groupId: groupId, filterPredicate: nil, additionalFilter: nil) {
            peers[peer.id] = (peer, groupId)
        }
    }
    let chats = peers.values.map { entry in
        FocusCatalogChat(id: FocusChatIdentifier(accountId: accountId, peerId: entry.peer.id.toInt64()), title: focusCatalogTitle(entry.peer), isArchived: entry.groupId == Namespaces.PeerGroup.archive, telegramChatId: focusTelegramChatId(entry.peer.id))
    }.sorted { $0.id.peerId < $1.id.peerId }
    let globalSettings = transaction.getGlobalNotificationSettings()
    let folderStates = filters.isEmpty ? [] : peers.values.map { entry in
        FocusFolderChatState(transaction: transaction, peer: entry.peer, groupId: entry.groupId, globalSettings: globalSettings)
    }
    let folders = filters.map { filter -> FocusCatalogFolder in
        let predicate = chatListFilterPredicate(for: filter, communityCategories: communityCategories)
        var peerIds = Set<Int64>()
        for state in folderStates where state.belongs(to: predicate, transaction: transaction) {
            peerIds.insert(state.peer.id.toInt64())
        }
        return FocusCatalogFolder(id: FocusFolderIdentifier(accountId: accountId, folderId: filter.id), title: filter.title, peerIds: peerIds)
    }.sorted { $0.id.folderId < $1.id.folderId }
    return FocusFilterCatalog(chats: chats, folders: folders)
}
