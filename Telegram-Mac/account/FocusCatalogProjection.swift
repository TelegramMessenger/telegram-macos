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

func focusAccountCatalog(transaction: Transaction, accountId: Int64, filters: [ChatListFilter], communityCategories: [PeerId: ChatListFilterPeerCategories]) -> FocusFilterCatalog {
    let groups: [PeerGroupId] = [.root, Namespaces.PeerGroup.archive]
    var peers: [PeerId: (peer: Peer, isArchived: Bool)] = [:]
    for groupId in groups {
        for peer in transaction.getChatListPeers(groupId: groupId, filterPredicate: nil, additionalFilter: nil) {
            peers[peer.id] = (peer, groupId == Namespaces.PeerGroup.archive)
        }
    }
    let chats = peers.values.map { entry in
        FocusCatalogChat(id: FocusChatIdentifier(accountId: accountId, peerId: entry.peer.id.toInt64()), title: focusCatalogTitle(entry.peer), isArchived: entry.isArchived)
    }.sorted { $0.id.peerId < $1.id.peerId }
    let folders = filters.map { filter -> FocusCatalogFolder in
        let predicate = chatListFilterPredicate(for: filter, communityCategories: communityCategories)
        var peerIds = Set<Int64>()
        for groupId in groups {
            for peer in transaction.getChatListPeers(groupId: groupId, filterPredicate: predicate, additionalFilter: nil) {
                peerIds.insert(peer.id.toInt64())
            }
        }
        return FocusCatalogFolder(id: FocusFolderIdentifier(accountId: accountId, folderId: filter.id), title: filter.title, peerIds: peerIds)
    }.sorted { $0.id.folderId < $1.id.folderId }
    return FocusFilterCatalog(chats: chats, folders: folders)
}
