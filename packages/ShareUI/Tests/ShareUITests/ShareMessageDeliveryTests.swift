import XCTest
import Postbox
import SwiftSignalKit
import TelegramCore
@testable import ShareUI

final class ShareMessageDeliveryTests: XCTestCase {
    private func id(_ value: Int32, peer: Int64 = 10) -> MessageId {
        MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(peer)), namespace: Namespaces.Message.Local, id: value)
    }

    func testFailedFlagsWinOverUnsentAndKeepReason() {
        guard case .failed(.slowmodeActive) = ShareMessageDeliveryState(flags: [.Failed, .Unsent], failureReason: .slowmodeActive) else { return XCTFail() }
        guard case .failed(nil) = ShareMessageDeliveryState(flags: [.Failed], failureReason: nil) else { return XCTFail() }
    }

    func testSentOrDisappearedMessagesFinishAndUnsentWaits() {
        guard case .pending = ShareMessageDeliveryState(flags: [.Unsent], failureReason: .flood) else { return XCTFail() }
        guard case .delivered = ShareMessageDeliveryState(flags: [], failureReason: nil) else { return XCTFail() }
        guard case .delivered = ShareMessageDeliveryState(flags: nil, failureReason: nil) else { return XCTFail() }
    }

    func testMixedRecipientBatchWaitsForEveryTerminalStatusAndOnlyFailsNewFailedIDs() {
        let a = ValuePipe<ShareMessageDeliveryState>(), b = ValuePipe<ShareMessageDeliveryState>()
        let one = id(1), two = id(2, peer: 20)
        var outputs: [[ShareMessageDeliveryOutcome]] = []
        let disposable = shareAwaitMessageDelivery(ids: [one, two], status: { $0 == one ? a.signal() : b.signal() }).start(next: { outputs.append($0) })
        a.putNext(.pending); b.putNext(.pending)
        XCTAssertTrue(outputs.isEmpty)
        a.putNext(.failed(.flood))
        XCTAssertTrue(outputs.isEmpty)
        b.putNext(.delivered)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(outputs[0].map { $0.id }, [one, two])
        XCTAssertEqual(outputs[0].filter { $0.failed }.map { $0.id }, [one])
        guard case .flood? = outputs[0][0].failureReason else { return XCTFail() }
        a.putNext(.delivered); b.putNext(.failed(.slowmodeActive))
        XCTAssertEqual(outputs.count, 1)
        disposable.dispose()
    }

    func testDuplicateIDsSubscribeOnlyOnce() {
        var requests: [MessageId] = []
        var outcomes: [ShareMessageDeliveryOutcome] = []
        let one = id(1)
        let disposable = shareAwaitMessageDelivery(ids: [one, one], status: { requests.append($0); return .single(.delivered) }).start(next: { outcomes = $0 })
        XCTAssertEqual(requests, [one]); XCTAssertEqual(outcomes.count, 1)
        disposable.dispose()
    }

    func testEmptyBatchDoesNotObserveOrHang() {
        var completed = false
        let disposable = shareAwaitMessageDelivery(ids: [], status: { _ in XCTFail(); return .never() }).start(next: { XCTAssertTrue($0.isEmpty) }, completed: { completed = true })
        XCTAssertTrue(completed); disposable.dispose()
    }

    func testDisposalStopsPendingObservation() {
        let pipe = ValuePipe<ShareMessageDeliveryState>()
        var count = 0
        let disposable = shareAwaitMessageDelivery(ids: [id(1)], status: { _ in pipe.signal() }).start(next: { _ in count += 1 })
        pipe.putNext(.pending); disposable.dispose(); pipe.putNext(.delivered)
        XCTAssertEqual(count, 0)
    }

    func testCommentAndContentKeepActualIDsWithoutChangingQueueAcceptanceMeaning() {
        let one = id(1), two = id(2)
        let comment = ShareDeliveryPart(expectedCount: 1, result: [one])
        let content = ShareDeliveryPart(expectedCount: 2, result: [two, nil])
        let delivery = ShareRecipientDelivery(peerId: one.peerId, comment: comment, content: content)
        XCTAssertEqual(comment.messageIds, [one]); XCTAssertEqual(content.messageIds, [two])
        XCTAssertEqual(delivery.status, .partial)
        XCTAssertEqual(SharePickerResult(deliveries: [delivery]), .partiallyAccepted)
        XCTAssertEqual(ShareDeliveryPart(expectedCount: 1, result: nil).status, .unknown)
    }
}
