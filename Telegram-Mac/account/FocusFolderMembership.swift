import Postbox
import TelegramCore

struct FocusFolderChatState {
    let peer: Peer
    private let groupId: PeerGroupId
    private let isMuted: Bool
    private let isUnread: Bool
    private let isContact: Bool

    init(transaction: Transaction, peer: Peer, groupId: PeerGroupId, globalSettings: PostboxGlobalNotificationSettings) {
        self.peer = peer
        self.groupId = groupId
        let notificationSettingsPeerId = peer.notificationSettingsPeerId ?? peer.id
        isUnread = transaction.isChatListPeerUnread(peer)
        isContact = transaction.isPeerContact(peerId: notificationSettingsPeerId)
        isMuted = resolvedIsRemovedFromTotalUnreadCount(globalSettings: globalSettings, peer: peer, peerSettings: transaction.getPeerNotificationSettings(id: notificationSettingsPeerId))
    }

    init?(transaction: Transaction, peerId: PeerId) {
        guard let peer = transaction.getPeer(peerId),
              let (groupId, _) = transaction.getPeerChatListIndex(peerId),
              groupId == .root || groupId == Namespaces.PeerGroup.archive else {
            return nil
        }
        self.init(transaction: transaction, peer: peer, groupId: groupId, globalSettings: transaction.getGlobalNotificationSettings())
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
