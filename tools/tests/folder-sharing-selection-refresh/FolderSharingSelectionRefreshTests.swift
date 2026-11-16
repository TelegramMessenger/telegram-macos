import Foundation
import XCTest

public protocol Peer: AnyObject {
    var id: PeerId { get }
    func isEqual(_ other: Peer) -> Bool
}

final class TestPeer: Peer {
    let id: PeerId
    let title: String
    let avatar: Int
    let eligible: Bool

    init(_ value: Int64, title: String = "Group", avatar: Int = 0, eligible: Bool = true) {
        self.id = PeerId(namespace: ._internalFromInt32Value(1), id: ._internalFromInt64Value(value))
        self.title = title
        self.avatar = avatar
        self.eligible = eligible
    }

    func isEqual(_ other: Peer) -> Bool {
        guard let other = other as? TestPeer else {
            return false
        }
        return id == other.id && title == other.title && avatar == other.avatar && eligible == other.eligible
    }
}

public enum EnginePeer {
    public typealias Id = PeerId
}

struct ChatListFilter: Equatable {}

func peerCanBeSharedInFolder(_ peer: Peer, filter: ChatListFilter? = nil) -> Bool {
    return (peer as? TestPeer)?.eligible == true
}

final class StateBox {
    var value: FolderSharingLinkState

    init(_ value: FolderSharingLinkState) {
        self.value = value
    }

    func with<T>(_ body: (FolderSharingLinkState) -> T) -> T {
        return body(value)
    }
}

final class Replay {
    let selected: Selection
    let stateValue: StateBox
    let emit: ([FolderSharingPeer], [PeerId: Int?]) -> Void
    let needsDiscard: () -> Bool

    var state: FolderSharingLinkState {
        return stateValue.value
    }

    init(link: ExportedChatFolderLink?) {
        let selected = Selection()
        self.selected = selected
        let filter = ChatListFilter()
        let stateValue = StateBox(FolderSharingLinkState(filter: filter, link: link))
        self.stateValue = stateValue
        let updateState: ((FolderSharingLinkState) -> FolderSharingLinkState) -> Void = { transform in
            stateValue.value = transform(stateValue.value)
        }
        __SELECTION_LOCAL__
        emit = __PEER_CALLBACK__
        selected.action = __ROW_CALLBACK__
        needsDiscard = {
            let state = stateValue.with { $0 }
            return __DISCARD_EXPRESSION__
        }
    }

    func refresh(_ peers: [TestPeer], counts: [PeerId: Int?] = [:]) {
        emit(peers.map { FolderSharingPeer($0) }, counts)
    }

    func toggle(_ peer: TestPeer) {
        selected.action(peer.id, nil)
    }

    func toggleAll() {
        let peers = state.peers.map { $0.peer }.filter { peerCanBeSharedInFolder($0, filter: state.filter) }
        folderSharingToggleAll(peers, selected: state.selected, selection: selected)
        stateValue.value.selected = selected.selectedPeerIds
    }

    func saveEvents() -> [String] {
        var events: [String] = []
        folderSharingSaveLink(state: state, original: state.link, edit: { _, _, _, _ in
            events.append("edit")
        }, updated: { _, _ in events.append("updated") }, success: { events.append("success") }, failure: { events.append("failure") }, delete: { events.append("delete") }, close: { events.append("close") })
        return events
    }
}

final class FolderSharingSelectionRefreshTests: XCTestCase {
    private func peer(_ value: Int64, title: String = "Group", avatar: Int = 0, eligible: Bool = true) -> TestPeer {
        return TestPeer(value, title: title, avatar: avatar, eligible: eligible)
    }

    private func link(_ ids: [Int64]) -> ExportedChatFolderLink {
        return ExportedChatFolderLink(title: "Original", link: "https://t.me/addlist/local-test", peerIds: ids.map { peer($0).id }, isRevoked: false)
    }

    private func expect(_ replay: Replay, _ ids: [Int64], dirty: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let expected = Set(ids.map { peer($0).id })
        XCTAssertEqual(replay.selected.selectedPeerIds, expected, file: file, line: line)
        XCTAssertEqual(replay.state.selected, expected, file: file, line: line)
        XCTAssertEqual(replay.needsDiscard(), dirty, file: file, line: line)
    }

    func testInitializationIsIdempotentAndDeduplicatesPeers() {
        let selected = Selection()
        let peers: [Peer] = [peer(2), peer(1), peer(2)]
        folderSharingInitializeSelection(peers, selectedIds: nil, selection: selected)
        XCTAssertEqual(selected.selectedPeerIds, [peer(1).id, peer(2).id])
        folderSharingInitializeSelection(peers, selectedIds: nil, selection: selected)
        XCTAssertEqual(selected.selectedPeerIds, [peer(1).id, peer(2).id])
        XCTAssertEqual(selected.toggled, [peer(2).id, peer(1).id])
    }

    func testExplicitInitialIdsAndEmptyExistingLink() {
        let selected = Selection()
        folderSharingInitializeSelection([peer(2), peer(1)], selectedIds: [peer(1).id], selection: selected)
        XCTAssertEqual(selected.selectedPeerIds, [peer(1).id])
        folderSharingInitializeSelection([peer(2), peer(1)], selectedIds: [peer(1).id], selection: selected)
        XCTAssertEqual(selected.selectedPeerIds, [peer(1).id])
        let replay = Replay(link: link([]))
        replay.refresh([peer(1), peer(2)])
        replay.refresh([peer(1), peer(2)])
        expect(replay, [], dirty: false)
    }

    func testRenameAvatarAndCountsKeepExistingSelectionAndSave() {
        let replay = Replay(link: link([1, 2]))
        replay.refresh([peer(1), peer(2)])
        for revision in 1...3 {
            replay.refresh([peer(2, title: "Renamed \(revision)", avatar: revision), peer(1)], counts: [peer(2).id: revision, peer(1).id: nil])
            expect(replay, [1, 2], dirty: false)
            XCTAssertEqual(replay.state.peers.map { $0.peer.id }, [peer(2).id, peer(1).id])
            XCTAssertEqual((replay.state.peers[0].peer as? TestPeer)?.title, "Renamed \(revision)")
            XCTAssertEqual(replay.state.membersCount, [peer(2).id: revision])
            XCTAssertEqual(replay.saveEvents(), ["close"])
        }
        XCTAssertEqual(replay.selected.toggled, [peer(1).id, peer(2).id])
    }

    func testRowDeselectAndAdditionKeepOriginalDirtyBaseline() {
        let replay = Replay(link: link([1]))
        replay.refresh([peer(1), peer(2)])
        replay.toggle(peer(1))
        replay.toggle(peer(2))
        for revision in 1...3 {
            replay.refresh([peer(1, avatar: revision), peer(2)])
            expect(replay, [2], dirty: true)
            XCTAssertEqual(replay.saveEvents(), ["edit", "close"])
        }
        replay.toggle(peer(1))
        replay.toggle(peer(2))
        expect(replay, [1], dirty: false)
    }

    func testUserAdditionAloneRemainsDirtyAfterRefresh() {
        let replay = Replay(link: link([]))
        replay.refresh([peer(1), peer(2)])
        replay.toggle(peer(2))
        replay.refresh([peer(1), peer(2, title: "Changed")])
        expect(replay, [2], dirty: true)
    }

    func testSelectAllPersistsAcrossMetadataRefresh() {
        let replay = Replay(link: link([1]))
        replay.refresh([peer(1), peer(2), peer(3, eligible: false)])
        replay.toggleAll()
        replay.refresh([peer(1), peer(2, avatar: 1), peer(3, eligible: false)])
        expect(replay, [1, 2], dirty: true)
    }

    func testDeselectAllPersistsAndIntentionalDeleteRemains() {
        let replay = Replay(link: link([1, 2]))
        replay.refresh([peer(1), peer(2)])
        replay.toggleAll()
        replay.refresh([peer(2, title: "Changed"), peer(1)])
        expect(replay, [], dirty: true)
        XCTAssertEqual(replay.saveEvents(), ["delete"])
    }

    func testNewLinkDefaultsAndUnsavedSelectionSurviveRefresh() {
        let replay = Replay(link: nil)
        replay.refresh([peer(1), peer(2), peer(3, eligible: false)])
        expect(replay, [1, 2], dirty: false)
        replay.toggle(peer(1))
        replay.refresh([peer(2, title: "Changed"), peer(1), peer(3, eligible: false)])
        expect(replay, [2], dirty: false)
        replay.toggleAll()
        replay.refresh([peer(1), peer(2)])
        expect(replay, [1, 2], dirty: false)
    }

    func testNewLinkSelectsLateAvailablePeersOnce() {
        let replay = Replay(link: nil)
        replay.refresh([])
        replay.refresh([peer(1)])
        replay.toggle(peer(1))
        replay.refresh([peer(1), peer(2)])
        expect(replay, [2], dirty: false)
        replay.refresh([peer(2), peer(1)])
        expect(replay, [2], dirty: false)
    }

    func testExistingLinkSelectsOnlyLateLinkedPeers() {
        let replay = Replay(link: link([1, 2]))
        replay.refresh([])
        replay.refresh([peer(1)])
        replay.toggle(peer(1))
        replay.refresh([peer(1), peer(2), peer(3)])
        expect(replay, [2], dirty: true)
        replay.toggle(peer(1))
        expect(replay, [1, 2], dirty: false)
    }

    func testInitiallyIneligiblePeerInitializesWhenAllowed() {
        let replay = Replay(link: link([1, 2]))
        replay.refresh([peer(1), peer(2, eligible: false), peer(3, eligible: false)])
        replay.toggle(peer(1))
        replay.refresh([peer(1), peer(2), peer(3)])
        expect(replay, [2], dirty: true)
        replay.toggle(peer(1))
        expect(replay, [1, 2], dirty: false)
    }

    func testEligibilityLossPrunesOnlyUnavailableSelectedPeers() {
        let replay = Replay(link: link([1, 2]))
        replay.refresh([peer(1), peer(2), peer(3)])
        replay.toggle(peer(3))
        replay.refresh([peer(1, eligible: false), peer(2), peer(3)])
        expect(replay, [2, 3], dirty: true)
        XCTAssertEqual(replay.state.peers.map { $0.peer.id }, [peer(2).id, peer(3).id, peer(1).id])
        replay.refresh([peer(1, eligible: false), peer(2, avatar: 1), peer(3)])
        expect(replay, [2, 3], dirty: true)
    }

    func testEligibilityReturnRestoresUserChoiceRatherThanOriginalLink() {
        let replay = Replay(link: link([1]))
        replay.refresh([peer(1), peer(2)])
        replay.toggle(peer(1))
        replay.toggle(peer(2))
        replay.refresh([peer(1, eligible: false), peer(2, eligible: false)])
        expect(replay, [], dirty: true)
        replay.refresh([peer(1), peer(2)])
        expect(replay, [2], dirty: true)
        replay.toggle(peer(1))
        replay.toggle(peer(2))
        expect(replay, [1], dirty: false)
    }

    func testMissingPeerReturnRestoresPriorSelection() {
        let replay = Replay(link: link([1, 2]))
        replay.refresh([peer(1), peer(2)])
        replay.refresh([peer(2)])
        expect(replay, [2], dirty: true)
        replay.refresh([peer(2), peer(1)])
        expect(replay, [1, 2], dirty: false)
    }

    func testUnavailableDeselectedPeerIsNotReinitialized() {
        let replay = Replay(link: link([1, 2]))
        replay.refresh([peer(1), peer(2)])
        replay.toggle(peer(1))
        replay.refresh([peer(1, eligible: false), peer(2)])
        replay.refresh([peer(1), peer(2)])
        expect(replay, [2], dirty: true)
    }

    func testRenameLinkRemainsDirtyAcrossPeerRefresh() {
        let replay = Replay(link: link([1]))
        replay.refresh([peer(1)])
        replay.stateValue.value.link?.title = "Unsaved title"
        replay.refresh([peer(1, title: "Renamed peer")])
        expect(replay, [1], dirty: true)
        XCTAssertEqual(replay.state.link?.title, "Unsaved title")
    }

    func testRepeatedSelectAllAndRowTogglesRemainDeliberate() {
        let replay = Replay(link: link([1]))
        replay.refresh([peer(1), peer(2), peer(3, eligible: false)])
        replay.toggleAll()
        expect(replay, [1, 2], dirty: true)
        replay.toggleAll()
        expect(replay, [], dirty: true)
        replay.toggle(peer(1))
        expect(replay, [1], dirty: false)
        replay.toggle(peer(1))
        expect(replay, [], dirty: true)
    }
}

let suite = XCTestSuite(forTestCaseClass: FolderSharingSelectionRefreshTests.self)
suite.run()
let result = suite.testRun!
print("NATIVE_RESULT tests=\(result.executionCount) failures=\(result.totalFailureCount)")
exit(result.totalFailureCount == 0 ? 0 : 1)
