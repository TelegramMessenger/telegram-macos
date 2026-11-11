import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsOwnContactShareTests: XCTestCase {
    private typealias Spec = AnalyticsFlows.PeerInfoShareOwnContact
    private let owner = NSObject()
    private var now: TimeInterval = 0
    private var sent: [[String: JSON]] = []
    private var reads = 0

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { [unowned self] in reads += 1; return now })
        analytics.setSink({ [unowned self] name, value in
            XCTAssertEqual(name, "flow.end")
            if case let .dictionary(data) = value { sent.append(data) }
        }, owner: owner)
        analytics.isEnabled = true
        return analytics
    }

    func testOwnContactResultsUseDistinctRegisteredFlowAndCoarseTiming() {
        let analytics = hub()
        for (result, outcome): (Spec.Result, AnalyticsFlowOutcome) in [(.accepted, .success), (.rejected, .fail), (.acceptanceUnknown, .fail), (.targetUnavailable, .fail), (.sourceUnavailable, .fail)] {
            now = 0
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: analytics.captureContext(owner: owner, privacy: .ordinary).scope, source: .peerInfo)
            flow.step(.request); flow.set(result: result); now = 2.79; flow.finish(outcome)
            XCTAssertEqual(sent.last?["flow"], .string("peer_info.share_own_contact")); XCTAssertEqual(sent.last?["result"], .string(result.rawValue))
            XCTAssertEqual(sent.last?["source"], .string("peer_info")); XCTAssertEqual(sent.last?["duration_ms"], .number(2000))
            for key in ["phone", "first_name", "last_name", "contact", "peer_id", "target", "entry_point"] { XCTAssertNil(sent.last?[key]) }
        }
        XCTAssertEqual(sent.count, 5)
    }

    func testOwnContactCancellationHasNoDeliveryResultAndDiscardHasNoEvent() {
        let analytics = hub(); let scope = analytics.captureContext(owner: owner, privacy: .ordinary).scope
        let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: .peerInfo)
        flow.step(.request); flow.step(.targetReady); flow.step(.openConfirmation); flow.step(.cancel); flow.finish(.cancelled)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(sent.last?["outcome"], .string("cancelled")); XCTAssertNil(sent.last?["result"])
        let other = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: .peerInfo)
        other.step(.request); other.step(.openConfirmation); other.discard(); other.finish(.cancelled)
        XCTAssertEqual(sent.count, 1)
    }

    func testOwnContactInvalidAndRevokedScopesNeverRecord() {
        let analytics = hub()
        let inert = AnalyticsFlow<Spec>(analytics: analytics, scope: analytics.excludedContext().scope, source: .peerInfo)
        inert.step(.request); inert.set(result: .accepted); inert.finish(.success)
        XCTAssertEqual(reads, 0); XCTAssertTrue(sent.isEmpty)
        let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: analytics.captureContext(owner: owner, privacy: .ordinary).scope, source: .peerInfo)
        flow.step(.request); flow.step(.openConfirmation)
        let privatePresentation = analytics.excludedContext().beginPresentation(); privatePresentation.end()
        XCTAssertEqual(flow.storedStepCount, 0)
        flow.step(.confirm); flow.set(result: .accepted); flow.finish(.success)
        XCTAssertTrue(sent.isEmpty)
    }
}
