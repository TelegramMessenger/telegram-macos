import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsPreparedShareJourneyTests: XCTestCase {
    private let owner = NSObject()
    private var now: TimeInterval = 0
    private var clockReads = 0
    private var sent: [[String: JSON]] = []

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { [unowned self] in
            clockReads += 1
            return now
        })
        analytics.setSink({ [unowned self] name, value in
            XCTAssertEqual(name, "flow.end")
            if case let .dictionary(data) = value { sent.append(data) }
        }, owner: owner)
        analytics.isEnabled = true
        return analytics
    }

    private func task(_ analytics: Analytics, privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsPreparedShareJourney {
        AnalyticsPreparedShareJourney(context: analytics.captureContext(owner: owner, privacy: privacy))
    }

    private func steps() -> [String] {
        guard case let .array(values)? = sent.last?["steps"] else { return [] }
        return values.compactMap {
            guard case let .array(pair) = $0, case let .string(value)? = pair.first else { return nil }
            return value
        }
    }

    func testAcceptedJourneyRetainsRequestRouteAndCoarseTimingOnce() {
        let analytics = hub(); let journey = task(analytics)
        journey.metadataReady(); journey.previewOpened(); journey.pickerOpened()
        now = 2.95; journey.pickerFinished(accepted: true); journey.pickerFinished(accepted: false); journey.cancelPreview()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["flow"], .string("bot.prepared_share"))
        XCTAssertEqual(sent.last?["entry_point"], .string("mini_app_request"))
        XCTAssertEqual(sent.last?["source"], .string("bot.mini_app"))
        XCTAssertEqual(sent.last?["result"], .string("accepted"))
        XCTAssertEqual(sent.last?["outcome"], .string("success"))
        XCTAssertEqual(sent.last?["duration_ms"], .number(2000))
        XCTAssertEqual(steps(), ["request", "metadata_ready", "open_preview", "open_picker", "accepted"])
        XCTAssertEqual(journey.retainedStateCount, 0)
    }

    func testPickerFalseDoesNotClaimExplicitCancellationOrRejection() {
        let analytics = hub(); let journey = task(analytics)
        journey.metadataReady(); journey.previewOpened(); journey.pickerOpened(); journey.pickerFinished(accepted: false)
        XCTAssertEqual(sent.last?["result"], .string("not_accepted")); XCTAssertEqual(sent.last?["outcome"], .string("fail"))
        XCTAssertFalse(steps().contains("cancel_preview")); XCTAssertEqual(sent.count, 1)
    }

    func testExplicitPreviewCancellationHasNoSubmissionResult() {
        let analytics = hub()
        for openedPicker in [false, true] {
            let journey = task(analytics); journey.metadataReady(); journey.previewOpened()
            if openedPicker { journey.pickerOpened() }
            journey.cancelPreview(); journey.pickerFinished(accepted: true)
            XCTAssertEqual(sent.last?["outcome"], .string("cancelled")); XCTAssertNil(sent.last?["result"])
            XCTAssertEqual(steps().last, "cancel_preview")
        }
        XCTAssertEqual(sent.count, 2)
    }

    func testMissingMetadataFailsOnlyBeforePreview() {
        let analytics = hub(); let journey = task(analytics)
        journey.metadataUnavailable(); journey.metadataUnavailable(); journey.previewOpened()
        XCTAssertEqual(sent.last?["result"], .string("metadata_unavailable")); XCTAssertEqual(steps(), ["request", "metadata_unavailable"])
        let prepared = task(analytics); prepared.metadataReady(); prepared.metadataUnavailable()
        XCTAssertEqual(sent.count, 1); prepared.discard(); XCTAssertEqual(prepared.retainedStateCount, 0)
    }

    func testOutOfOrderAndRepeatedCallbacksCannotInventOrGrowJourney() {
        let analytics = hub(); let journey = task(analytics)
        journey.pickerFinished(accepted: true); journey.cancelPreview(); journey.previewOpened(); journey.pickerOpened()
        XCTAssertTrue(sent.isEmpty)
        for _ in 0..<1000 { journey.metadataReady(); journey.previewOpened(); journey.pickerOpened() }
        XCTAssertLessThanOrEqual(journey.retainedStateCount, 5)
        journey.pickerFinished(accepted: true)
        XCTAssertEqual(steps(), ["request", "metadata_ready", "open_preview", "open_picker", "accepted"])
    }

    func testDisabledPrivateUnknownAndRevokedContextsAreInert() {
        let analytics = hub()
        let revoked = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.isEnabled = false; analytics.isEnabled = true
        let contexts = [analytics.excludedContext(), analytics.unresolvedContext(), revoked]
        for context in contexts {
            let journey = AnalyticsPreparedShareJourney(context: context)
            journey.metadataReady(); journey.previewOpened(); journey.pickerOpened(); journey.pickerFinished(accepted: true)
            XCTAssertEqual(journey.retainedStateCount, 0)
        }
        analytics.isEnabled = false
        let journey = task(analytics); journey.metadataUnavailable()
        XCTAssertEqual(journey.retainedStateCount, 0); XCTAssertEqual(clockReads, 0); XCTAssertTrue(sent.isEmpty)
    }

    func testPrivateTransitionClearsWholeAttemptBeforePickerResult() {
        let analytics = hub(); let journey = task(analytics)
        journey.metadataReady(); journey.previewOpened(); journey.pickerOpened()
        let presentation = analytics.excludedContext().beginPresentation()
        XCTAssertEqual(journey.retainedStateCount, 0); presentation.end()
        journey.pickerFinished(accepted: true); journey.cancelPreview(); XCTAssertTrue(sent.isEmpty)
    }

    func testDisableAndAccountChangeCannotReplayAttempt() {
        let analytics = hub(); let first = task(analytics)
        first.metadataReady(); first.previewOpened(); analytics.isEnabled = false; analytics.isEnabled = true
        first.cancelPreview(); XCTAssertEqual(first.retainedStateCount, 0)
        let second = task(analytics); second.metadataReady(); second.previewOpened(); second.pickerOpened()
        let replacementOwner = NSObject()
        analytics.setSink({ _, _ in XCTFail("Old journey cannot reach replacement account") }, owner: replacementOwner)
        second.pickerFinished(accepted: true); XCTAssertEqual(second.retainedStateCount, 0); XCTAssertTrue(sent.isEmpty)
    }

    func testDiscardAndTeardownDoNotInferAbandonment() {
        let analytics = hub(); var journey: AnalyticsPreparedShareJourney? = task(analytics)
        journey?.metadataReady(); journey?.previewOpened(); journey = nil
        let other = task(analytics); other.discard(); other.metadataUnavailable()
        XCTAssertEqual(other.retainedStateCount, 0); XCTAssertTrue(sent.isEmpty)
    }
}

extension AnalyticsPreparedShareJourneyTests {
    func testTypedPickerResultsPreservePartialRejectedAndUnknownMeanings() {
        let analytics = hub()
        for (result, value): (AnalyticsPreparedShareJourney.PickerResult, String) in [(.partiallyAccepted, "partially_accepted"), (.rejected, "rejected"), (.unknown, "acceptance_unknown")] {
            let journey = task(analytics); journey.metadataReady(); journey.previewOpened(); journey.pickerOpened()
            journey.pickerFinished(result: result); journey.pickerFinished(result: .accepted)
            XCTAssertEqual(sent.last?["result"], .string(value)); XCTAssertEqual(sent.last?["outcome"], .string("fail"))
            XCTAssertEqual(steps().last, value); XCTAssertEqual(journey.retainedStateCount, 0)
        }
        XCTAssertEqual(sent.count, 3)
    }

    func testTypedPickerCancellationHasNoDeliveryResult() {
        let analytics = hub(); let journey = task(analytics)
        journey.metadataReady(); journey.previewOpened(); journey.pickerOpened(); journey.pickerFinished(result: .cancelled)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(sent.last?["outcome"], .string("cancelled")); XCTAssertNil(sent.last?["result"])
        XCTAssertEqual(steps(), ["request", "metadata_ready", "open_preview", "open_picker", "cancel_picker"])
    }
}
