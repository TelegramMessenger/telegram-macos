import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsMediaEditJourneyTests: XCTestCase {
    private let owner = NSObject()
    private var payloads: [[String: JSON]] = []
    private var clockReads = 0
    private var logs: [String] = []

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { [unowned self] in
            clockReads += 1
            return Double(clockReads) / 4
        })
        analytics.setSink({ [unowned self] type, data in
            XCTAssertEqual(type, AnalyticsEventName.flowEnd.rawValue)
            if case let .dictionary(value) = data { payloads.append(value) }
        }, owner: owner)
        analytics.log = { [unowned self] in logs.append($0) }
        analytics.isEnabled = true
        return analytics
    }

    private func task(_ analytics: Analytics) -> AnalyticsMediaEditJourney {
        return AnalyticsMediaEditJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .clipboard, mode: .media)
    }

    private func prepare(_ task: AnalyticsMediaEditJourney, entry: AnalyticsMediaEditJourney.Spec.EntryPoint = .clipboard, mode: AnalyticsMediaEditJourney.Spec.MediaMode = .media) {
        if let token = task.beginReplacement(entry: entry, mode: mode) { task.appliedReplacement(token) }
    }

    private func steps(_ payload: [String: JSON]) -> [String] {
        guard case let .array(values)? = payload["steps"] else { return [] }
        return values.compactMap {
            guard case let .array(pair) = $0, case let .string(value)? = pair.first else { return nil }
            return value
        }
    }

    func testFirstRouteSurvivesLaterReplacementAndCancelledPicker() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        prepare(journey, entry: .dropTarget)
        let selection = try XCTUnwrap(journey.beginReplacement(entry: .replacementPicker, mode: .file))
        journey.cancelledSelection(selection)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        XCTAssertTrue(payloads.isEmpty)
        request.complete { .applied }
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0]["flow"], .string("chat.media_edit"))
        XCTAssertEqual(payloads[0]["entry_point"], .string("clipboard"))
        XCTAssertEqual(payloads[0]["media_mode"], .string("media"))
        XCTAssertEqual(payloads[0]["replacement_count"], .string("2_3"))
        XCTAssertEqual(payloads[0]["outcome"], .string("success"))
        XCTAssertEqual(steps(payloads[0]), ["paste", "apply_replacement", "drop", "apply_replacement", "open_picker", "cancel_selection", "submit", "applied"])
    }

    func testSupersededConversionCannotApplyOrCancelTheNewSelection() throws {
        let analytics = hub()
        let journey = task(analytics)
        let first = try XCTUnwrap(journey.beginReplacement(entry: .clipboard, mode: .media))
        let second = try XCTUnwrap(journey.beginReplacement(entry: .replacementPicker, mode: .file))
        journey.appliedReplacement(first)
        journey.cancelledSelection(first)
        journey.appliedReplacement(second)
        journey.appliedReplacement(second)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        request.complete { .applied }
        XCTAssertEqual(payloads[0]["replacement_count"], .string("1"))
        XCTAssertEqual(payloads[0]["media_mode"], .string("file"))
        XCTAssertEqual(payloads[0]["scheduled"], .bool(true))
        XCTAssertEqual(steps(payloads[0]), ["paste", "supersede_replacement", "open_picker", "apply_replacement", "submit", "applied"])
    }

    func testUnappliedAndPendingReplacementDoNotBecomeSuccessfulEdits() {
        let analytics = hub()
        let empty = task(analytics)
        XCTAssertNil(empty.beginSubmission(scheduled: false))
        let pending = task(analytics)
        prepare(pending)
        _ = pending.beginReplacement(entry: .photoEditor, mode: .media)
        XCTAssertNil(pending.beginSubmission(scheduled: false))
        pending.cancel()
        XCTAssertTrue(payloads.isEmpty)
    }

    func testCommittedRequestSurvivesParentEndAndCompletesOnce() throws {
        let analytics = hub()
        var journey: AnalyticsMediaEditJourney? = task(analytics)
        prepare(journey!)
        let request = try XCTUnwrap(journey?.beginSubmission(scheduled: false))
        journey?.endEditing()
        journey?.cancel()
        journey = nil
        var evaluations = 0
        request.complete { evaluations += 1; return .applied }
        request.complete { evaluations += 1; return .failed(.requestFailed) }
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(payloads.count, 1)
    }

    func testObservedFailureIsDistinctFromUnknownCompletion() throws {
        let analytics = hub()
        let failed = task(analytics)
        prepare(failed)
        failed.blocked(.captionLimit)
        let failure = try XCTUnwrap(failed.beginSubmission(scheduled: false))
        failure.complete { .failed(.permission) }
        XCTAssertEqual(payloads[0]["outcome"], .string("fail"))
        XCTAssertEqual(payloads[0]["last_blocker"], .string("permission"))
        let unknown = task(analytics)
        prepare(unknown)
        let request = try XCTUnwrap(unknown.beginSubmission(scheduled: false))
        request.complete { nil }
        request.complete { .applied }
        XCTAssertEqual(payloads.count, 1)
    }

    func testPrivateUnresolvedAndDisabledOriginsDoNotDeriveAnything() {
        let analytics = hub()
        let contexts = [analytics.excludedContext(), analytics.unresolvedContext()]
        for context in contexts {
            let journey = AnalyticsMediaEditJourney(context: context, entry: .clipboard, mode: .media)
            prepare(journey)
            XCTAssertNil(journey.beginSubmission(scheduled: false))
            journey.cancel()
        }
        analytics.isEnabled = false
        let disabled = task(analytics)
        prepare(disabled)
        XCTAssertNil(disabled.beginSubmission(scheduled: false))
        disabled.cancel()
        XCTAssertEqual(clockReads, 0)
        XCTAssertTrue(payloads.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testRevocationPreventsLazyResultEvaluationAndRechecksBuilder() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        analytics.isEnabled = false
        request.complete { XCTFail("Revoked result must remain unevaluated"); return .applied }
        analytics.isEnabled = true
        let other = task(analytics)
        prepare(other)
        let otherRequest = try XCTUnwrap(other.beginSubmission(scheduled: false))
        otherRequest.complete { analytics.isEnabled = false; return .applied }
        XCTAssertTrue(payloads.isEmpty)
    }

    func testReplacementAndStepBudgetsAreBounded() throws {
        let analytics = hub()
        let journey = task(analytics)
        for _ in 0..<256 { prepare(journey) }
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        request.complete { .applied }
        XCTAssertEqual(payloads[0]["replacement_count"], .string("4_plus"))
        XCTAssertEqual(steps(payloads[0]).count, 50)
        let overflow = task(analytics)
        for _ in 0..<257 { prepare(overflow) }
        XCTAssertNil(overflow.beginSubmission(scheduled: false))
        XCTAssertEqual(payloads.count, 1)
    }

    func testExplicitCancelAndUnknownDisappearanceAreDifferent() {
        let analytics = hub()
        let cancelled = task(analytics)
        prepare(cancelled)
        cancelled.cancel()
        XCTAssertEqual(payloads.first?["outcome"], .string("cancelled"))
        let vanished = task(analytics)
        prepare(vanished)
        vanished.endEditing()
        vanished.cancel()
        let lost = task(analytics)
        prepare(lost)
        var request = lost.beginSubmission(scheduled: false)
        XCTAssertNotNil(request)
        request = nil
        lost.cancel()
        XCTAssertEqual(payloads.count, 1)
    }

    func testScheduledFailureRetainsOriginThroughReplacementAndRetry() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        var first = try XCTUnwrap(journey.beginSubmission(scheduled: true)) as AnalyticsMediaEditSubmission?
        first?.complete { .failed(.requestFailed) }
        first = nil
        XCTAssertTrue(payloads.isEmpty)
        prepare(journey, entry: .replacementPicker, mode: .file)
        let second = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        second.complete { .applied }
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0]["entry_point"], .string("clipboard"))
        XCTAssertEqual(payloads[0]["retry_count"], .string("1"))
        XCTAssertEqual(payloads[0]["replacement_count"], .string("2_3"))
        XCTAssertEqual(payloads[0]["media_mode"], .string("file"))
        XCTAssertEqual(steps(payloads[0]), ["paste", "apply_replacement", "submit", "rejected", "open_picker", "apply_replacement", "retry", "submit", "applied"])
    }

    func testExplicitUploadCancellationDoesNotCancelEditingOrLetOldHandleFinishRetry() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        var first: AnalyticsMediaEditSubmission? = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        journey.cancelSubmission()
        journey.cancelSubmission()
        let second = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        first?.complete { XCTFail("Old result must remain unevaluated"); return .applied }
        first?.discard()
        first = nil
        second.complete { .applied }
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0]["retry_count"], .string("1"))
        XCTAssertEqual(steps(payloads[0]), ["paste", "apply_replacement", "submit", "cancel_submission", "retry", "submit", "applied"])
    }

    func testReplacementDuringUploadSupersedesObservationAndKeepsNewAttempt() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let first = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        prepare(journey, entry: .dropTarget)
        let second = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        first.complete { XCTFail("Superseded upload must not resolve the new draft"); return .failed(.permission) }
        first.discard()
        second.complete { .applied }
        XCTAssertEqual(payloads[0]["retry_count"], .string("1"))
        XCTAssertEqual(steps(payloads[0]), ["paste", "apply_replacement", "submit", "supersede_submission", "drop", "apply_replacement", "retry", "submit", "applied"])
    }

    func testUnknownDisposalDiscardsInsteadOfInventingCancelledUpload() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        var request: AnalyticsMediaEditSubmission? = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        XCTAssertNotNil(request)
        request = nil
        journey.cancelSubmission()
        XCTAssertNil(journey.beginSubmission(scheduled: true))
        journey.cancel()
        XCTAssertTrue(payloads.isEmpty)
    }

    func testScheduledFailureAfterOwnerEndsIsTerminalAndCannotRetry() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        journey.endEditing()
        request.complete { .failed(.requestFailed) }
        XCTAssertEqual(payloads.first?["outcome"], .string("fail"))
        XCTAssertNil(journey.beginSubmission(scheduled: true))
    }

    func testFailedScheduledEditCanBeExplicitlyCancelledWithoutReportingSuccess() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        request.complete { .failed(.permission) }
        journey.cancel()
        request.discard()
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0]["outcome"], .string("cancelled"))
        XCTAssertEqual(payloads[0]["last_blocker"], .string("permission"))
    }

    func testSubmissionRetryBudgetAndRepeatedBlockerAreBounded() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        journey.blocked(.captionLimit)
        journey.blocked(.captionLimit)
        for _ in 0..<255 {
            let request = try XCTUnwrap(journey.beginSubmission(scheduled: true))
            request.complete { .failed(.requestFailed) }
        }
        let last = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        last.complete { .applied }
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads[0]["retry_count"], .string("4_plus"))
        XCTAssertEqual(steps(payloads[0]).count, 50)
        let overflow = task(analytics)
        prepare(overflow)
        for _ in 0..<256 {
            let request = try XCTUnwrap(overflow.beginSubmission(scheduled: true))
            request.complete { .failed(.requestFailed) }
        }
        XCTAssertNil(overflow.beginSubmission(scheduled: true))
        overflow.cancel()
        XCTAssertEqual(payloads.count, 1)
    }

    func testEditorCancelReturnsToAppliedDraftWithoutAddingReplacement() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey, mode: .file)
        let editor = try XCTUnwrap(journey.beginReplacement(entry: .photoEditor, mode: .media))
        journey.cancelledSelection(editor)
        journey.cancelledSelection(editor)
        journey.appliedReplacement(editor)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        request.complete { .applied }
        XCTAssertEqual(payloads[0]["replacement_count"], .string("1"))
        XCTAssertEqual(payloads[0]["media_mode"], .string("file"))
        XCTAssertEqual(steps(payloads[0]), ["paste", "apply_replacement", "open_editor", "cancel_editor", "submit", "applied"])
    }

    func testStaleEditorCancelCannotCancelReplacementPicker() throws {
        let analytics = hub()
        let journey = task(analytics)
        let editor = try XCTUnwrap(journey.beginReplacement(entry: .photoEditor, mode: .media))
        let picker = try XCTUnwrap(journey.beginReplacement(entry: .replacementPicker, mode: .file))
        journey.cancelledSelection(editor)
        journey.appliedReplacement(picker)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        request.complete { .applied }
        XCTAssertFalse(steps(payloads[0]).contains("cancel_editor"))
        XCTAssertEqual(payloads[0]["replacement_count"], .string("1"))
        XCTAssertEqual(payloads[0]["media_mode"], .string("file"))
    }

    func testUnresolvedEditorExitCannotBecomeCancellationOrSuccessfulSave() {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        _ = journey.beginReplacement(entry: .photoEditor, mode: .media)
        journey.discard()
        journey.cancel()
        XCTAssertNil(journey.beginSubmission(scheduled: false))
        XCTAssertTrue(payloads.isEmpty)
    }

    func testRejectedPasteRetainsFirstRouteThroughSuccessfulPickerRecovery() throws {
        let analytics = hub()
        let journey = task(analytics)
        journey.rejectedReplacement(entry: .clipboard, reason: .sizeLimit)
        prepare(journey, entry: .replacementPicker, mode: .file)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        request.complete { .applied }
        XCTAssertEqual(payloads[0]["entry_point"], .string("clipboard"))
        XCTAssertEqual(payloads[0]["replacement_count"], .string("1"))
        XCTAssertEqual(payloads[0]["last_blocker"], .string("size_limit"))
        XCTAssertEqual(payloads[0]["retry_count"], .string("1"))
        XCTAssertEqual(steps(payloads[0]), ["paste", "blocked", "open_picker", "apply_replacement", "retry", "submit", "applied"])
    }

    func testRejectedInputDoesNotSupersedeValidPendingConversion() throws {
        let analytics = hub()
        let journey = task(analytics)
        let pending = try XCTUnwrap(journey.beginReplacement(entry: .replacementPicker, mode: .file))
        journey.rejectedReplacement(entry: .clipboard, reason: .fileUnavailable)
        journey.appliedReplacement(pending)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        request.complete { .applied }
        XCTAssertEqual(payloads[0]["media_mode"], .string("file"))
        XCTAssertEqual(payloads[0]["replacement_count"], .string("1"))
        XCTAssertFalse(steps(payloads[0]).contains("supersede_replacement"))
    }

    func testKnownPreparationFailurePreservesPriorDraftAndIgnoresDuplicateFailure() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey, mode: .file)
        let editor = try XCTUnwrap(journey.beginReplacement(entry: .photoEditor, mode: .media))
        journey.failedReplacement(editor, reason: .preparation)
        journey.failedReplacement(editor, reason: .permission)
        journey.appliedReplacement(editor)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        request.complete { .applied }
        XCTAssertEqual(payloads[0]["media_mode"], .string("file"))
        XCTAssertEqual(payloads[0]["replacement_count"], .string("1"))
        XCTAssertEqual(payloads[0]["last_blocker"], .string("preparation"))
        XCTAssertEqual(payloads[0]["retry_count"], .string("1"))
    }

    func testStaleAcquisitionFailureCannotResolveNewReplacement() throws {
        let analytics = hub()
        let journey = task(analytics)
        let old = try XCTUnwrap(journey.beginReplacement(entry: .photoEditor, mode: .media))
        let current = try XCTUnwrap(journey.beginReplacement(entry: .replacementPicker, mode: .file))
        journey.failedReplacement(old, reason: .preparation)
        journey.appliedReplacement(current)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: false))
        request.complete { .applied }
        XCTAssertNil(payloads[0]["last_blocker"])
        XCTAssertEqual(payloads[0]["retry_count"], .string("0"))
    }

    func testInvalidInputDuringUploadDoesNotRewriteSubmittedJourney() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: true))
        journey.rejectedReplacement(entry: .clipboard, reason: .permission)
        request.complete { .applied }
        XCTAssertNil(payloads[0]["last_blocker"])
        XCTAssertEqual(steps(payloads[0]), ["paste", "apply_replacement", "submit", "applied"])
    }

    func testRepeatedRejectedSelectionsConsumeTheAcquisitionBudget() {
        let analytics = hub()
        let journey = task(analytics)
        for _ in 0..<257 { journey.rejectedReplacement(entry: .clipboard, reason: .fileUnavailable) }
        journey.cancel()
        XCTAssertTrue(payloads.isEmpty)
    }

    func testDetachedScheduledEditFailureIsTerminalWhileKeepingScheduledMetadata() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: true, allowsRetry: false))
        request.complete { .failed(.requestFailed) }
        XCTAssertEqual(payloads.first?["scheduled"], .bool(true))
        XCTAssertEqual(payloads.first?["outcome"], .string("fail"))
        XCTAssertNil(journey.beginSubmission(scheduled: true, allowsRetry: false))
    }

    func testDetachedScheduledEditCannotBecomeRetryableThroughUploadCancel() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let request = try XCTUnwrap(journey.beginSubmission(scheduled: true, allowsRetry: false))
        journey.cancelSubmission()
        XCTAssertNil(journey.beginReplacement(entry: .clipboard, mode: .media))
        journey.endEditing()
        request.complete { .applied }
        XCTAssertEqual(payloads.first?["scheduled"], .bool(true))
        XCTAssertEqual(steps(payloads[0]), ["paste", "apply_replacement", "submit", "applied"])
    }

    func testActiveEditorRetryDoesNotRequireScheduledMetadata() throws {
        let analytics = hub()
        let journey = task(analytics)
        prepare(journey)
        let first = try XCTUnwrap(journey.beginSubmission(scheduled: false, allowsRetry: true))
        first.complete { .failed(.requestFailed) }
        XCTAssertTrue(payloads.isEmpty)
        let second = try XCTUnwrap(journey.beginSubmission(scheduled: false, allowsRetry: true))
        second.complete { .applied }
        XCTAssertEqual(payloads.first?["scheduled"], .bool(false))
        XCTAssertEqual(payloads.first?["retry_count"], .string("1"))
        XCTAssertEqual(payloads.first?["outcome"], .string("success"))
    }
}
