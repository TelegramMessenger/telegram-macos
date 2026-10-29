import Foundation

public struct PeerId: Hashable {
    let rawValue: Int64
    init(_ rawValue: Int64) { self.rawValue = rawValue }
    func toInt64() -> Int64 { rawValue }
}

__POSTBOX_PEER_GROUP_ID__

enum Namespaces {
    enum PeerGroup {
        static let archive = PeerGroupId.group(1)
    }
}

public protocol Peer {
    var id: PeerId { get }
    var associatedPeerId: PeerId? { get }
    var associatedPeerOverridesIdentity: Bool { get }
}

private struct TestPeer: Peer {
    let id: PeerId
    let associatedPeerId: PeerId?
    var associatedPeerOverridesIdentity: Bool { associatedPeerId != nil }

    init(_ id: Int64, associatedId: Int64? = nil) {
        self.id = PeerId(id)
        self.associatedPeerId = associatedId.map(PeerId.init)
    }
}

public struct ChatListMessageTagSummaryResultCalculation {}

__POSTBOX_PREDICATE__

__FOCUS_COMPOSITION__

private func includes(_ predicate: ChatListFilterPredicate, _ peerId: Int64, group: PeerGroupId = .root, associatedId: Int64? = nil) -> Bool {
    predicate.includes(peer: TestPeer(peerId, associatedId: associatedId), groupId: group, isRemovedFromTotalUnreadCount: false, isUnread: true, isContact: false, messageTagSummaryResult: nil)
}

@main
private enum Tests {
    static func main() {
        let base = ChatListFilterPredicate(includePeerIds: [PeerId(1), PeerId(4)], excludePeerIds: [PeerId(9)], pinnedPeerIds: [PeerId(1), PeerId(2), PeerId(3)], messageTagSummary: nil, includeAdditionalPeerGroupIds: [Namespaces.PeerGroup.archive], include: { _, _, isUnread, _, _ in isUnread })
        let allow = focusChatListPredicate(base, selection: .init(mode: .allowSelected, peerIds: [2, 4, 9, 10]), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(allow.includePeerIds.isEmpty && allow.excludePeerIds.isEmpty)
        precondition(allow.pinnedPeerIds == [PeerId(2)])
        precondition(allow.includeAdditionalPeerGroupIds == [Namespaces.PeerGroup.archive])
        precondition(!includes(allow, 1))
        precondition(includes(allow, 4))
        precondition(!includes(allow, 9))
        precondition(includes(allow, 10, group: Namespaces.PeerGroup.archive))
        precondition(!includes(allow, 11))

        let deny = focusChatListPredicate(base, selection: .init(mode: .excludeSelected, peerIds: [2, 4]), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(deny.includePeerIds.isEmpty && deny.excludePeerIds.isEmpty)
        precondition(deny.pinnedPeerIds == [PeerId(1), PeerId(3)])
        precondition(!includes(deny, 2))
        precondition(!includes(deny, 4))
        precondition(!includes(deny, 9))
        precondition(includes(deny, 10))

        let neutral = focusChatListPredicate(nil, selection: .init(mode: .excludeSelected, peerIds: [20]), pinnedPeerIds: [PeerId(30), PeerId(20), PeerId(10)], scope: .root(archivePeerIds: nil))
        precondition(neutral.pinnedPeerIds == [PeerId(30), PeerId(10)])
        precondition(includes(neutral, 100_000))
        precondition(!includes(neutral, 20))

        let emptyAllow = focusChatListPredicate(base, selection: .init(mode: .allowSelected, peerIds: []), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(emptyAllow.includePeerIds.isEmpty && emptyAllow.pinnedPeerIds.isEmpty)
        precondition(!includes(emptyAllow, 1) && !includes(emptyAllow, 100_000))
        let emptyDeny = focusChatListPredicate(nil, selection: .init(mode: .excludeSelected, peerIds: []), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(includes(emptyDeny, 1) && includes(emptyDeny, 100_000))

        let archive = focusChatListPredicate(nil, selection: .init(mode: .allowSelected, peerIds: [1, 3]), pinnedPeerIds: [], scope: .archive(peerIds: [PeerId(1), PeerId(2)]))
        precondition(archive.includeAdditionalPeerGroupIds == [Namespaces.PeerGroup.archive])
        precondition(includes(archive, 1, group: Namespaces.PeerGroup.archive))
        precondition(!includes(archive, 2, group: Namespaces.PeerGroup.archive))
        precondition(!includes(archive, 3, group: Namespaces.PeerGroup.archive))
        let replaySelection = FocusFilterSelection(mode: .allowSelected, peerIds: [7, 42])
        precondition(focusAllowsChatListPeer(PeerId(42), selection: replaySelection, scope: .archive(peerIds: [PeerId(42)])))
        precondition(!focusAllowsChatListPeer(PeerId(7), selection: replaySelection, scope: .archive(peerIds: [PeerId(42)])))
        precondition(focusAllowsChatListPeer(PeerId(7), selection: replaySelection, scope: .root(archivePeerIds: nil)))

        let aliasBase = ChatListFilterPredicate(includePeerIds: [PeerId(42)], excludePeerIds: [], pinnedPeerIds: [], messageTagSummary: nil, includeAdditionalPeerGroupIds: [Namespaces.PeerGroup.archive], include: { _, _, _, _, _ in false })
        let associatedAllow = focusChatListPredicate(aliasBase, selection: .init(mode: .allowSelected, peerIds: [42]), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(!includes(associatedAllow, 7, associatedId: 42))
        precondition(includes(associatedAllow, 42))
        let secretAllow = focusChatListPredicate(aliasBase, selection: .init(mode: .allowSelected, peerIds: [7]), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(includes(secretAllow, 7, associatedId: 42))
        let associatedDeny = focusChatListPredicate(aliasBase, selection: .init(mode: .excludeSelected, peerIds: [42]), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(includes(associatedDeny, 7, associatedId: 42))
        let secretDeny = focusChatListPredicate(aliasBase, selection: .init(mode: .excludeSelected, peerIds: [7]), pinnedPeerIds: [], scope: .root(archivePeerIds: nil))
        precondition(!includes(secretDeny, 7, associatedId: 42))
        let archivedSecret = focusChatListPredicate(aliasBase, selection: .init(mode: .allowSelected, peerIds: [7]), pinnedPeerIds: [], scope: .archive(peerIds: [PeerId(7), PeerId(42)]))
        precondition(includes(archivedSecret, 7, group: Namespaces.PeerGroup.archive, associatedId: 42))
        precondition(!includes(archivedSecret, 42, group: Namespaces.PeerGroup.archive))
        let selectedRootSecret = focusChatListPredicate(aliasBase, selection: .init(mode: .allowSelected, peerIds: [7]), pinnedPeerIds: [], scope: .archive(peerIds: [PeerId(42)]))
        precondition(!includes(selectedRootSecret, 7, group: Namespaces.PeerGroup.archive, associatedId: 42))
        precondition(!focusAllowsChatListPeer(PeerId(7), selection: .init(mode: .allowSelected, peerIds: [7]), scope: .archive(peerIds: [PeerId(42)])))
        let archivePins = focusChatListPredicate(nil, selection: .init(mode: .allowSelected, peerIds: [7, 8, 9]), pinnedPeerIds: [PeerId(9), PeerId(8), PeerId(7)], scope: .archive(peerIds: [PeerId(7), PeerId(9)]))
        precondition(archivePins.pinnedPeerIds == [PeerId(9), PeerId(7)])
        let explicitArchivedBase = ChatListFilterPredicate(includePeerIds: [PeerId(42)], excludePeerIds: [], pinnedPeerIds: [], messageTagSummary: nil, includeAdditionalPeerGroupIds: [], include: { _, _, _, _, _ in true })
        let explicitArchived = focusChatListPredicate(explicitArchivedBase, selection: .init(mode: .allowSelected, peerIds: [7, 8, 9]), pinnedPeerIds: [], scope: .root(archivePeerIds: [PeerId(7), PeerId(8)]))
        precondition(explicitArchived.includeAdditionalPeerGroupIds == [Namespaces.PeerGroup.archive])
        precondition(includes(explicitArchived, 7, group: Namespaces.PeerGroup.archive, associatedId: 42))
        precondition(!includes(explicitArchived, 8, group: Namespaces.PeerGroup.archive))
        precondition(includes(explicitArchived, 9))
        print("PASS: Focus predicate composition, pins, folders, archive and associated identities")
    }
}
