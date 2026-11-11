import Postbox
import TelegramCore

public struct ConferenceInvitationFailureBatch {
    private var peers: [EnginePeer] = []

    public init() {
    }

    public mutating func append(_ peer: EnginePeer) {
        if !self.peers.contains(where: { $0.id == peer.id }) {
            self.peers.append(peer)
        }
    }

    public mutating func take() -> [EnginePeer] {
        let peers = self.peers
        self.peers.removeAll()
        return peers
    }
}

public func conferenceInvitationPeerIds(_ peerIds: [PeerId]) -> [PeerId] {
    var seen = Set<PeerId>()
    return peerIds.filter { seen.insert($0).inserted }
}

public func conferenceInvitationCapacity(limit: Int, participantCount: Int, participantPeerIds: [PeerId], invitedPeerIds: [PeerId]) -> Int {
    let pending = Set(invitedPeerIds).subtracting(Set(participantPeerIds)).count
    return max(0, limit - max(1, participantCount) - pending)
}
