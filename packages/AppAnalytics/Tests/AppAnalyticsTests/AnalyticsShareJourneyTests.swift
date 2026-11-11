import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsShareJourneyTests: XCTestCase {
    private let owner = NSObject()
    private var now: TimeInterval = 0
    private var reads = 0
    private var onClock: (() -> Void)?
    private var sent: [[String: JSON]] = []

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { [unowned self] in reads += 1; onClock?(); return now })
        analytics.setSink({ [unowned self] name, value in
            XCTAssertEqual(name, "flow.end")
            if case let .dictionary(data) = value { sent.append(data) }
        }, owner: owner)
        analytics.isEnabled = true
        return analytics
    }
    private func task(_ analytics: Analytics, _ entry: AnalyticsShareJourney.Spec.EntryPoint = .messageAction) -> AnalyticsShareJourney {
        AnalyticsShareJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: entry)
    }
    private func steps() -> [String] {
        guard case let .array(values)? = sent.last?["steps"] else { return [] }
        return values.compactMap { guard case let .array(pair) = $0, case let .string(value)? = pair.first else { return nil }; return value }
    }
    func testMessageAndAlbumRoutesStayDistinctThroughAcceptance() {
        let analytics = hub()
        for entry: AnalyticsShareJourney.Spec.EntryPoint in [.messageAction, .albumAction, .gallerySelection, .galleryGroup] {
            now = 0; let journey = task(analytics, entry)
            journey.pickerOpened(); journey.submitted(); now = 3.78; journey.complete(.accepted); journey.complete(.unknown); journey.cancel()
            XCTAssertEqual(sent.last?["flow"], .string("chat.share")); XCTAssertEqual(sent.last?["entry_point"], .string(entry.rawValue))
            XCTAssertEqual(sent.last?["result"], .string("accepted")); XCTAssertEqual(sent.last?["outcome"], .string("success")); XCTAssertEqual(sent.last?["duration_ms"], .number(3000))
            XCTAssertEqual(steps(), ["request", "open_picker", "submit", "accepted"]); XCTAssertEqual(journey.retainedStateCount, 0)
        }
        XCTAssertEqual(sent.count, 4)
    }
    func testProfileRequiresSourceBeforePickerAndDoesNotExposeContactData() {
        let analytics = hub(); let journey = task(analytics, .profileContact)
        journey.pickerOpened(); journey.submitted(); journey.complete(.accepted); XCTAssertTrue(sent.isEmpty)
        journey.sourceReady(); journey.pickerOpened(); journey.submitted(); journey.complete(.accepted)
        XCTAssertEqual(sent.last?["entry_point"], .string("profile_contact")); XCTAssertEqual(steps(), ["request", "source_ready", "open_picker", "submit", "accepted"])
        XCTAssertNil(sent.last?["peer_id"]); XCTAssertNil(sent.last?["recipient_count"])
    }
    func testUnavailableProfileSourceIsDistinctFromUncertainSubmission() {
        let analytics = hub(); let journey = task(analytics, .profileContact)
        journey.sourceUnavailable(); journey.sourceUnavailable(); journey.complete(.accepted)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(sent.last?["result"], .string("source_unavailable")); XCTAssertEqual(steps(), ["request", "source_unavailable"])
        let message = task(analytics); message.sourceUnavailable(); XCTAssertEqual(sent.count, 1)
    }
    func testPartialRejectedAndUnknownResultsAreNotCompleteAcceptance() {
        let analytics = hub()
        for (result, value): (AnalyticsShareJourney.Result, String) in [(.partiallyAccepted, "partially_accepted"), (.rejected, "rejected"), (.unknown, "acceptance_unknown")] {
            let journey = task(analytics); journey.pickerOpened(); journey.submitted(); journey.complete(result)
            XCTAssertEqual(sent.last?["result"], .string(value)); XCTAssertEqual(sent.last?["outcome"], .string("fail")); XCTAssertEqual(steps().last, value)
        }
        XCTAssertEqual(sent.count, 3)
    }
    func testExplicitCloseBeforeOrDuringSubmissionIsCancellationRequestOnly() {
        let analytics = hub()
        for submitting in [false, true] {
            let journey = task(analytics); journey.pickerOpened(); if submitting { journey.submitted() }
            journey.cancel(); journey.submissionEnded(); journey.complete(.accepted)
            XCTAssertNil(sent.last?["result"]); XCTAssertEqual(sent.last?["outcome"], .string("cancelled")); XCTAssertEqual(steps().last, "cancel")
        }
        XCTAssertEqual(sent.count, 2)
    }
    func testSupersededSubmissionAndTeardownDiscardWithoutInventingOutcome() {
        let analytics = hub(); let journey = task(analytics)
        journey.pickerOpened(); journey.submitted(); journey.submissionEnded(); journey.submitted(); journey.complete(.accepted); journey.cancel()
        XCTAssertTrue(sent.isEmpty); XCTAssertEqual(journey.retainedStateCount, 0)
        var other: AnalyticsShareJourney? = task(analytics, .profileContact); other?.sourceReady(); other = nil
        XCTAssertTrue(sent.isEmpty)
    }
    func testRepeatedAndOutOfOrderActionsRemainBounded() {
        let analytics = hub(); let journey = task(analytics)
        journey.submitted(); journey.complete(.accepted); journey.cancel(); XCTAssertTrue(sent.isEmpty)
        for _ in 0..<1000 { journey.sourceReady(); journey.pickerOpened(); journey.submitted() }
        XCTAssertLessThanOrEqual(journey.retainedStateCount, 4)
        journey.complete(.accepted); XCTAssertEqual(steps(), ["request", "open_picker", "submit", "accepted"])
    }
    func testPrivateUnknownDisabledAndRevokedContextsHaveNoRecorderState() {
        let analytics = hub(); let revoked = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.isEnabled = false; analytics.isEnabled = true
        for context in [analytics.excludedContext(), analytics.unresolvedContext(), revoked] {
            let journey = AnalyticsShareJourney(context: context, entry: .profileContact)
            journey.sourceReady(); journey.pickerOpened(); journey.submitted(); journey.complete(.accepted)
            XCTAssertEqual(journey.retainedStateCount, 0)
        }
        analytics.isEnabled = false; let disabled = task(analytics); disabled.cancel()
        XCTAssertEqual(disabled.retainedStateCount, 0); XCTAssertEqual(reads, 0); XCTAssertTrue(sent.isEmpty)
    }
    func testPrivateEntryDisableAndAccountChangeEraseExistingTask() {
        let analytics = hub()
        for kind in 0..<3 {
            let journey = task(analytics); journey.pickerOpened(); journey.submitted()
            if kind == 0 { let privatePresentation = analytics.excludedContext().beginPresentation(); privatePresentation.end() }
            if kind == 1 { analytics.isEnabled = false; analytics.isEnabled = true }
            if kind == 2 { analytics.setSink({ _, _ in XCTFail("Old share task cannot reach another account") }, owner: NSObject()) }
            XCTAssertEqual(journey.retainedStateCount, 0); journey.complete(.accepted); journey.cancel()
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testBlockerRecoveryConsumesOneRetryAndPreservesLastReason() {
        let analytics = hub(); let journey = task(analytics)
        journey.pickerOpened(); journey.blocked(.slowModeWait); journey.blocked(.pendingMessages)
        journey.retryIfBlocked(); journey.retryIfBlocked(); journey.submitted(); journey.complete(.accepted)
        XCTAssertEqual(sent.last?["retry_count"], .string("1")); XCTAssertEqual(sent.last?["last_blocker"], .string("pending_messages"))
        XCTAssertEqual(steps(), ["request", "open_picker", "blocked", "retry", "submit", "accepted"])
    }
    func testRepeatedBlockedAttemptsUseCappedBucketAndBoundedSteps() {
        let analytics = hub(); let journey = task(analytics); journey.pickerOpened()
        for _ in 0..<1000 { journey.blocked(.premiumRequired); journey.retryIfBlocked() }
        XCTAssertLessThanOrEqual(journey.retainedStateCount, 53)
        journey.cancel()
        XCTAssertEqual(sent.last?["retry_count"], .string("4_plus")); XCTAssertEqual(sent.last?["last_blocker"], .string("premium_required"))
        XCTAssertEqual(journey.retainedStateCount, 0)
    }
    func testConfirmationCancelIsRecoverableAndNotDeliveryFailure() {
        let analytics = hub(); let journey = task(analytics); journey.pickerOpened()
        journey.paymentConfirmationOpened(); journey.submitted(); journey.complete(.accepted)
        XCTAssertTrue(sent.isEmpty)
        journey.paymentConfirmationResolved(confirmed: false); journey.paymentConfirmationEnded()
        journey.retryIfBlocked(); journey.paymentConfirmationOpened(); journey.paymentConfirmationResolved(confirmed: true)
        journey.paymentConfirmationEnded(); journey.submitted(); journey.complete(.accepted)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(sent.last?["retry_count"], .string("1")); XCTAssertNil(sent.last?["last_blocker"])
        XCTAssertEqual(steps(), ["request", "open_picker", "open_payment_confirmation", "cancel_payment_confirmation", "retry", "open_payment_confirmation", "confirm_payment", "submit", "accepted"])
    }
    func testUnknownConfirmationEndDiscardsWholeObservation() {
        let analytics = hub(); let journey = task(analytics); journey.pickerOpened()
        journey.paymentConfirmationOpened(); journey.paymentConfirmationEnded()
        journey.paymentConfirmationResolved(confirmed: true); journey.submitted(); journey.complete(.accepted); journey.cancel()
        XCTAssertTrue(sent.isEmpty); XCTAssertEqual(journey.retainedStateCount, 0)
    }
    func testTopUpRequiresExplicitSubsequentSubmission() {
        let analytics = hub(); let journey = task(analytics); journey.pickerOpened()
        journey.paymentConfirmationOpened(); journey.paymentConfirmationResolved(confirmed: true)
        journey.blocked(.insufficientBalance); journey.topUpOpened(); journey.complete(.accepted)
        XCTAssertTrue(sent.isEmpty)
        journey.retryIfBlocked(); journey.submitted(); journey.complete(.accepted)
        XCTAssertEqual(sent.last?["retry_count"], .string("1")); XCTAssertEqual(sent.last?["last_blocker"], .string("insufficient_balance"))
        XCTAssertEqual(steps(), ["request", "open_picker", "open_payment_confirmation", "confirm_payment", "blocked", "open_top_up", "retry", "submit", "accepted"])
    }
    func testReentrantRevocationCannotRestoreBlockerOrRetryState() {
        let analytics = hub()
        for operation in 0..<3 {
            analytics.isEnabled = true
            let journey = task(analytics); journey.pickerOpened()
            if operation == 1 { journey.blocked(.slowModeComment) }
            if operation == 2 { journey.paymentConfirmationOpened() }
            onClock = { analytics.isEnabled = false }
            if operation == 0 { journey.blocked(.premiumRequired) }
            if operation == 1 { journey.submitted() }
            if operation == 2 { journey.paymentConfirmationResolved(confirmed: false) }
            onClock = nil
            XCTAssertEqual(journey.retainedStateCount, 0)
            analytics.isEnabled = true; journey.submitted(); journey.complete(.accepted); journey.cancel()
        }
        XCTAssertTrue(sent.isEmpty)
    }
    func testPrivateContextRejectsAllRecoveryOperationsWithoutClockReads() {
        let analytics = hub(); let journey = AnalyticsShareJourney(context: analytics.excludedContext(), entry: .messageAction)
        journey.pickerOpened(); journey.blocked(.premiumRequired); journey.retryIfBlocked()
        journey.paymentConfirmationOpened(); journey.paymentConfirmationResolved(confirmed: false); journey.paymentConfirmationEnded()
        journey.topUpOpened(); journey.submitted(); journey.complete(.accepted); journey.cancel()
        XCTAssertEqual(reads, 0); XCTAssertTrue(sent.isEmpty); XCTAssertEqual(journey.retainedStateCount, 0)
    }
}
