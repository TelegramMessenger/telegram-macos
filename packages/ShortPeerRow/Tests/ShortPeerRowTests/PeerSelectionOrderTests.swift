import XCTest
import TelegramCore
import Postbox
@testable import ShortPeerRow

final class PeerSelectionOrderTests: XCTestCase {
    private func peer(_ value: Int64) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(value)), accessHash: nil, firstName: "Peer \(value)", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func selected(_ values: [Int64], limit: Int32 = 0) -> SelectPeerPresentation {
        return values.reduce(SelectPeerPresentation(limit: limit)) { state, value in
            let user = peer(value)
            return state.withToggledSelected(user.id, peer: user)
        }
    }

    func testPicksKeepTheirOrderAndSetMembership() {
        let state = selected([3, 1, 2])
        XCTAssertEqual(state.orderedSelected, [peer(3).id, peer(1).id, peer(2).id])
        XCTAssertEqual(state.selected, Set([peer(1).id, peer(2).id, peer(3).id]))
        XCTAssertEqual(Set(state.peers.keys), state.selected)
    }

    func testExplicitToggleIsIdempotent() {
        let state = selected([3, 1, 2])
        let alreadySelected = state.withToggledSelected(peer(1).id, peer: peer(1), toggle: true)
        XCTAssertEqual(alreadySelected.orderedSelected, state.orderedSelected)
        XCTAssertEqual(alreadySelected, state)
        let absent = state.withToggledSelected(peer(9).id, peer: peer(9), toggle: false)
        XCTAssertEqual(absent, state)
    }

    func testRemovalAndReselectionAppendAtTheEnd() {
        let state = selected([3, 1, 2]).deselect(peerId: peer(1).id)
        XCTAssertEqual(state.orderedSelected, [peer(3).id, peer(2).id])
        XCTAssertNil(state.peers[peer(1).id])
        let reselected = state.withToggledSelected(peer(1).id, peer: peer(1))
        XCTAssertEqual(reselected.orderedSelected, [peer(3).id, peer(2).id, peer(1).id])
        let toggledOff = reselected.withToggledSelected(peer(2).id, peer: peer(2))
        XCTAssertEqual(toggledOff.orderedSelected, [peer(3).id, peer(1).id])
        XCTAssertEqual(toggledOff.selected, Set(toggledOff.orderedSelected))
    }

    func testLimitRejectsWithoutChangingOrderAndCanIncrease() {
        let full = selected([3, 1], limit: 2)
        let rejected = full.withToggledSelected(peer(2).id, peer: peer(2))
        XCTAssertEqual(rejected.orderedSelected, full.orderedSelected)
        XCTAssertEqual(rejected.selected, full.selected)
        XCTAssertNil(rejected.peers[peer(2).id])
        XCTAssertTrue(rejected.isLimitReached)
        let increased = rejected.withUpdateLimit(3).withToggledSelected(peer(2).id, peer: peer(2))
        XCTAssertEqual(increased.orderedSelected, [peer(3).id, peer(1).id, peer(2).id])
    }

    func testSetPreselectionIsDeterministicAndExplicitOrderIsNormalized() {
        let ids = Set([peer(3).id, peer(1).id, peer(2).id])
        XCTAssertEqual(SelectPeerPresentation(ids).orderedSelected, ids.sorted())
        let normalized = SelectPeerPresentation(ids, orderedSelected: [peer(3).id, peer(3).id, peer(9).id, peer(1).id])
        XCTAssertEqual(normalized.orderedSelected, [peer(3).id, peer(1).id, peer(2).id])
        XCTAssertEqual(normalized.deselect(peerId: peer(1).id).orderedSelected, [peer(3).id, peer(2).id])
        XCTAssertTrue(SelectPeerPresentation().orderedSelected.isEmpty)
    }

    func testStateCopiesPreservePickOrder() {
        let initial = selected([3, 1, 2])
        let copied = initial.withUpdateLimit(5)
            .withUpdatedMultipleSelection(false)
            .updatedInputQueryResult { $0 }
            .withUpdatedComment(.init(string: "hello", range: NSRange(location: 0, length: 5)))
            .withUpdatedPremiumRequired(Set([peer(9).id]))
        XCTAssertEqual(copied.orderedSelected, initial.orderedSelected)
        XCTAssertEqual(copied.selected, initial.selected)
        XCTAssertEqual(Set(copied.peers.keys), Set(initial.peers.keys))
        XCTAssertEqual(initial.orderedSelected, [peer(3).id, peer(1).id, peer(2).id])
    }

    func testOrderIsPartOfPresentationEquality() {
        let first = selected([3, 1, 2])
        let second = selected([1, 2, 3])
        XCTAssertEqual(first.selected, second.selected)
        XCTAssertNotEqual(first, second)
    }
}
