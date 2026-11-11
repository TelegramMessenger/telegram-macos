import Postbox
import TelegramCore

func peerInfoUserReportTarget(_ user: TelegramUser, accountPeerId: PeerId) -> PeerId? {
    let peer = EnginePeer(user)
    guard user.id.namespace == Namespaces.Peer.CloudUser, user.id != accountPeerId, !peer.isDeleted, user.botInfo == nil, !user.flags.contains(.isSupport), !peer.isService else {
        return nil
    }
    return user.id
}
