import Postbox
import TelegramCore
import FocusFilterCore

enum ChatListFocusScope: Equatable {
    case root(archivePeerIds: Set<PeerId>?)
    case archive(peerIds: Set<PeerId>)

    func allowsPeer(_ peerId: PeerId) -> Bool {
        switch self {
        case .root:
            return true
        case let .archive(peerIds):
            return peerIds.contains(peerId)
        }
    }
}

func focusAllowsChatListPeer(_ peerId: PeerId, selection: FocusFilterSelection, scope: ChatListFocusScope) -> Bool {
    selection.includes(peerId: peerId.toInt64()) && scope.allowsPeer(peerId)
}

private func focusFolderIdentity(_ peer: Peer) -> PeerId {
    if let associatedId = peer.associatedPeerId, peer.associatedPeerOverridesIdentity {
        return associatedId
    }
    return peer.id
}

func focusChatListPredicate(_ base: ChatListFilterPredicate?, selection: FocusFilterSelection, pinnedPeerIds: [PeerId], scope: ChatListFocusScope) -> ChatListFilterPredicate {
    var predicate = base ?? ChatListFilterPredicate(includePeerIds: [], excludePeerIds: [], pinnedPeerIds: pinnedPeerIds, messageTagSummary: nil, includeAdditionalPeerGroupIds: [], include: { _, _, _, _, _ in true })
    let baseInclude = predicate.include
    let baseIncludePeerIds = predicate.includePeerIds
    let baseExcludePeerIds = predicate.excludePeerIds
    let baseIncludesArchive = predicate.includeAdditionalPeerGroupIds.contains(Namespaces.PeerGroup.archive)
    predicate.includePeerIds = []
    predicate.excludePeerIds = []
    predicate.pinnedPeerIds = predicate.pinnedPeerIds.filter {
        focusAllowsChatListPeer($0, selection: selection, scope: scope)
    }
    switch scope {
    case .archive:
        predicate.includeAdditionalPeerGroupIds = [Namespaces.PeerGroup.archive]
    case let .root(archivePeerIds):
        if archivePeerIds != nil && !baseIncludePeerIds.isEmpty && !baseIncludesArchive {
            predicate.includeAdditionalPeerGroupIds.append(Namespaces.PeerGroup.archive)
        }
    }
    predicate.include = { peer, isMuted, isUnread, isContact, tagSummary in
        guard focusAllowsChatListPeer(peer.id, selection: selection, scope: scope) else {
            return false
        }
        let folderIdentity = focusFolderIdentity(peer)
        if baseExcludePeerIds.contains(folderIdentity) {
            return false
        }
        if baseIncludePeerIds.contains(folderIdentity) {
            return true
        }
        if case let .root(archivePeerIds) = scope, !baseIncludesArchive, archivePeerIds?.contains(peer.id) == true {
            return false
        }
        return baseInclude(peer, isMuted, isUnread, isContact, tagSummary)
    }
    return predicate
}
