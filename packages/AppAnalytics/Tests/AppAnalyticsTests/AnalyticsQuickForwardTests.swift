import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsQuickForwardTests: XCTestCase {
    private typealias Spec = AnalyticsFlows.ChatQuickForward
    private let owner = NSObject()
    private var now: TimeInterval = 0
    private var reads = 0
    private var sent: [[String: JSON]] = []

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { [unowned self] in reads += 1; return now })
        analytics.setSink({ [unowned self] name, value in
            XCTAssertEqual(name, "flow.end")
            if case let .dictionary(data) = value { sent.append(data) }
        }, owner: owner)
        analytics.isEnabled = true
        return analytics
    }

    func testQuickTargetAndTopicKeepDraftAndAcceptanceDistinct() {
        let analytics = hub()
        for entry: Spec.EntryPoint in [.directTarget, .topicTarget] {
            for result: Spec.Result in [.draftPrepared, .destinationReady, .accepted] {
                now = 0
                let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: analytics.captureContext(owner: owner, privacy: .ordinary).scope)
                flow.set(entryPoint: entry); flow.step(.request); now = 2.79
                flow.set(result: result); flow.step(result == .accepted ? .accepted : result == .destinationReady ? .destinationReady : .draftPrepared); flow.finish(.success)
                XCTAssertEqual(sent.last?["flow"], .string("chat.quick_forward")); XCTAssertEqual(sent.last?["entry_point"], .string(entry.rawValue))
                XCTAssertEqual(sent.last?["result"], .string(result.rawValue)); XCTAssertEqual(sent.last?["duration_ms"], .number(2000))
                for key in ["peer_id", "message_id", "thread_id", "title", "source", "error"] { XCTAssertNil(sent.last?[key]) }
            }
        }
        XCTAssertEqual(sent.count, 6)
    }

    func testUncertainPartialAndKnownFailureResultsRemainSeparate() {
        let analytics = hub()
        let results: [Spec.Result] = [.partiallyAccepted, .rejected, .acceptanceUnknown, .sourceUnavailable, .targetUnavailable, .restricted, .completionUnknown, .operationFailed]
        for result in results {
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            flow.set(entryPoint: .directTarget); flow.step(.request); flow.set(result: result); flow.finish(.fail)
            XCTAssertEqual(sent.last?["result"], .string(result.rawValue)); XCTAssertEqual(sent.last?["outcome"], .string("fail"))
        }
        XCTAssertEqual(sent.count, results.count)
    }

    func testExcludedMissingAndRevokedScopesCannotEmitForwardingSummary() {
        let analytics = hub()
        for scope in [analytics.excludedContext().scope, analytics.unresolvedContext().scope] {
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope)
            flow.set(entryPoint: .directTarget); flow.step(.request); flow.set(result: .accepted); flow.finish(.success)
        }
        XCTAssertEqual(reads, 0); XCTAssertTrue(sent.isEmpty)
        let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        flow.set(entryPoint: .topicTarget); flow.step(.request)
        analytics.isEnabled = false; analytics.isEnabled = true
        XCTAssertEqual(flow.storedStepCount, 0)
        flow.set(result: .draftPrepared); flow.finish(.success)
        XCTAssertTrue(sent.isEmpty)
    }
}
