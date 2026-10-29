import FocusFilterCore
import Postbox
import TelegramCore
import TelegramUtils

struct FocusNotificationMembershipRequest {
    let chat: FocusChatIdentifier
    let configuration: FocusFilterConfiguration
    let filters: [ChatListFilter]
    let communityCategories: [PeerId: ChatListFilterPeerCategories]
}

private struct FocusNotificationChatState {
    let peer: Peer
    let groupId: PeerGroupId
    let isMuted: Bool
    let isUnread: Bool
    let isContact: Bool

    init?(transaction: Transaction, peerId: PeerId) {
        guard let peer = transaction.getPeer(peerId),
              let (groupId, _) = transaction.getPeerChatListIndex(peerId),
              groupId == .root || groupId == Namespaces.PeerGroup.archive else {
            return nil
        }
        self.peer = peer
        self.groupId = groupId
        isUnread = transaction.getCombinedPeerReadState(peerId)?.isUnread ?? false
        isContact = transaction.isPeerContact(peerId: peerId)
        isMuted = resolvedIsRemovedFromTotalUnreadCount(globalSettings: transaction.getGlobalNotificationSettings(), peer: peer, peerSettings: transaction.getPeerNotificationSettings(id: peerId))
    }

    func belongs(to predicate: ChatListFilterPredicate?, transaction: Transaction) -> Bool {
        guard let predicate = predicate else { return true }
        if predicate.pinnedPeerIds.contains(peer.id) {
            return true
        }
        return predicate.includes(peer: peer, groupId: groupId, isRemovedFromTotalUnreadCount: isMuted, isUnread: isUnread, isContact: isContact, messageTagSummaryResult: messageTagSummary(predicate.messageTagSummary, transaction: transaction))
    }

    private func messageTagSummary(_ calculation: ChatListMessageTagSummaryResultCalculation?, transaction: Transaction) -> Bool? {
        guard let calculation = calculation else { return nil }
        let addCount = transaction.getMessageTagSummary(peerId: peer.id, threadId: nil, tagMask: calculation.addCount.tag, namespace: calculation.addCount.namespace, customTag: nil)?.count ?? 0
        let subtractCount = transaction.getPendingMessageActionsSummary(peerId: peer.id, type: calculation.subtractCount.type, namespace: calculation.subtractCount.namespace) ?? 0
        return addCount - subtractCount > 0
    }
}

func focusNotificationPolicy(transaction: Transaction, request: FocusNotificationMembershipRequest) -> FocusFilterPolicy {
    let configuration = request.configuration
    guard configuration.effect.contains(.notifications), configuration.accountIds.contains(request.chat.accountId),
          let state = FocusNotificationChatState(transaction: transaction, peerId: PeerId(request.chat.peerId)) else {
        return FocusFilterPolicy(configuration: configuration)
    }
    let selectedFolders = configuration.folderIds.filter { $0.accountId == request.chat.accountId }
    let folders = request.filters.compactMap { filter -> FocusCatalogFolder? in
        let id = FocusFolderIdentifier(accountId: request.chat.accountId, folderId: filter.id)
        guard selectedFolders.contains(id) else { return nil }
        let predicate = chatListFilterPredicate(for: filter, communityCategories: request.communityCategories)
        let includes = state.belongs(to: predicate, transaction: transaction)
        return FocusCatalogFolder(id: id, title: filter.title, peerIds: includes ? [request.chat.peerId] : [])
    }
    return FocusFilterPolicy(configuration: configuration, catalog: FocusFilterCatalog(folders: folders))
}
