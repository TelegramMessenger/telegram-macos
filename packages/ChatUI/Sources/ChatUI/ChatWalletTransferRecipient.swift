import Foundation
import Postbox
import TelegramCore

public enum ChatWalletSendRecipient {
    case peer(TelegramUser)
    case address(String)
}

func chatWalletTransferRecipient(chatPeer: Peer?, accountPeerId: PeerId, peerAddress: String, normalizeAddress: (String) -> String?) -> ChatWalletSendRecipient? {
    guard let user = chatPeer as? TelegramUser, user.id.namespace == Namespaces.Peer.CloudUser else {
        return nil
    }
    if user.id.isTelegramNotifications {
        return normalizeAddress(peerAddress).map(ChatWalletSendRecipient.address)
    }
    let peer = EnginePeer(user)
    guard user.id != accountPeerId, !peer.isService, !peer.isDeleted, user.botInfo == nil, !user.flags.contains(.isSupport) else {
        return nil
    }
    return .peer(user)
}
