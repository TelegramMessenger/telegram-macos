import XCTest
import Postbox
import TelegramCore
import TelegramUtils

final class ChatSlowModeExpiryTests: XCTestCase {
    func testZeroAndExpiredTimeoutsUnlockImmediately() {
        for timeout: Int32 in [0, -1, Int32.min] {
            let state = SlowMode(validUntil: 1000, timeout: timeout)
            XCTAssertNil(state.timeout)
            XCTAssertFalse(state.hasLocked)
        }
    }

    func testCountdownReachingZeroClearsWithoutAnotherTick() {
        let active = SlowMode(validUntil: 1000, timeout: 1)
        XCTAssertTrue(active.hasLocked)
        let expired = active.withUpdatedTimeout(0)
        XCTAssertNil(expired.timeout)
        XCTAssertFalse(expired.hasLocked)
        XCTAssertEqual(expired.validUntil, 1000)
    }

    func testPendingMessagesRemainLockedAfterDeadline() {
        let id = MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(42)), namespace: Namespaces.Message.Local, id: 7)
        let state = SlowMode(validUntil: 1000, timeout: 1, sendingIds: [id]).withUpdatedTimeout(0)
        XCTAssertNil(state.timeout)
        XCTAssertTrue(state.hasLocked)
        XCTAssertEqual(state.sendingIds, [id])
    }

    func testPositiveCountdownAndClearedStateArePreserved() {
        let state = SlowMode(validUntil: 1000, timeout: 25)
        XCTAssertEqual(state.timeout, 25)
        XCTAssertTrue(state.hasLocked)
        XCTAssertFalse(state.withUpdatedTimeout(nil).hasLocked)
    }
}
