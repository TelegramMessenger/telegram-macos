import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsStickerJourneyTests: XCTestCase {
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

    private func task(_ analytics: Analytics, entry: AnalyticsStickerJourney.Spec.EntryPoint) -> AnalyticsStickerJourney {
        return AnalyticsStickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: entry)
    }

    private func readyImage(_ journey: AnalyticsStickerJourney) {
        journey.imageSelected()
        journey.editorShown()
        journey.editorApplied(mode: .cutout)
    }

    private func steps() -> [String] {
        guard case let .array(values)? = sent.last?["steps"] else { return [] }
        return values.compactMap { value in
            guard case let .array(pair) = value, case let .string(name)? = pair.first else { return nil }
            return name
        }
    }

    func testCreatePreservesOriginThroughCancelledNameAndChangedDestination() {
        let analytics = hub()
        let journey = task(analytics, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.newPack)
        journey.blocked(.emptyName)
        XCTAssertNil(journey.beginSubmission())
        journey.cancelNaming()
        XCTAssertTrue(sent.isEmpty)
        journey.chooseDestination(.favorites)
        now = 3.75
        let submission = journey.beginSubmission()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["entry_point"], .string("composer_create"))
        XCTAssertEqual(sent[0]["destination"], .string("favorites"))
        XCTAssertEqual(sent[0]["image_mode"], .string("cutout"))
        XCTAssertEqual(sent[0]["last_blocker"], .string("empty_name"))
        XCTAssertEqual(sent[0]["duration_ms"], .number(3000))
        XCTAssertEqual(sent[0]["outcome"], .string("success"))
        XCTAssertEqual(steps(), ["attempt", "open_image_picker", "image_selected", "open_editor", "apply_editor", "choose_destination", "open_name", "blocked", "cancel_name", "choose_destination", "submit", "accepted"])
        XCTAssertEqual(journey.retainedStateCount, 0)
    }

    func testNewPackRequiresObservedNameAcceptance() {
        let analytics = hub()
        let journey = task(analytics, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.newPack)
        XCTAssertNil(journey.beginSubmission())
        journey.nameAccepted()
        let submission = journey.beginSubmission()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.last?["destination"], .string("new_pack"))
        XCTAssertTrue(steps().contains("accept_name"))
    }

    func testExistingStickerHasNoImagePreparationAndCannotChangeOperation() {
        let analytics = hub()
        let journey = task(analytics, entry: .packAddExisting)
        readyImage(journey)
        XCTAssertNil(journey.beginSubmission())
        journey.existingStickerSelected()
        journey.chooseDestination(.send)
        journey.editorShown()
        let submission = journey.beginSubmission()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.last?["destination"], .string("existing_pack"))
        XCTAssertNil(sent.last?["image_mode"])
        XCTAssertEqual(steps(), ["attempt", "open_sticker_picker", "sticker_selected", "submit", "accepted"])
    }

    func testWholeImageFallbackIsDistinctFromEditorApply() {
        let analytics = hub()
        let journey = task(analytics, entry: .packAddImage)
        journey.imageSelected()
        journey.preparedWithoutEditor()
        let submission = journey.beginSubmission()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.last?["image_mode"], .string("whole_image"))
        XCTAssertEqual(steps(), ["attempt", "open_image_picker", "image_selected", "prepared", "submit", "accepted"])
    }

    func testRenameCancellationIsTerminalWithoutSubmission() {
        let analytics = hub()
        let journey = task(analytics, entry: .packRename)
        journey.blocked(.emptyName)
        journey.cancelNaming()
        journey.nameAccepted()
        XCTAssertNil(journey.beginSubmission())
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["outcome"], .string("cancelled"))
        XCTAssertEqual(sent.last?["destination"], .string("rename"))
        XCTAssertEqual(steps(), ["attempt", "open_name", "blocked", "cancel"])
    }

    func testRetryUsesNewAttemptAndIgnoresOldCompletionAndCleanup() {
        let analytics = hub()
        let journey = task(analytics, entry: .packReplace)
        readyImage(journey)
        let first = journey.beginSubmission()
        first?.complete { .retryableFailure(.requestFailed) }
        XCTAssertTrue(sent.isEmpty)
        let second = journey.beginSubmission()
        XCTAssertNotNil(second)
        first?.end()
        var staleBuilderCalled = false
        first?.complete {
            staleBuilderCalled = true
            return .accepted
        }
        XCTAssertFalse(staleBuilderCalled)
        journey.cancel()
        second?.complete { .accepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["destination"], .string("replacement"))
        XCTAssertEqual(sent.last?["retry_count"], .string("1"))
        XCTAssertEqual(steps().suffix(5), ["submit", "rejected", "retry", "submit", "accepted"])
    }

    func testTerminalFailureAndDuplicateResultAreDistinctFromRetry() {
        let analytics = hub()
        let journey = task(analytics, entry: .packRename)
        journey.nameAccepted()
        let submission = journey.beginSubmission()
        submission?.complete { .terminalFailure(.requestFailed) }
        submission?.complete { XCTFail("Duplicate result must stay lazy"); return .accepted }
        XCTAssertNil(journey.beginSubmission())
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["outcome"], .string("fail"))
        XCTAssertEqual(sent.last?["last_blocker"], .string("request_failed"))
        XCTAssertEqual(sent.last?["retry_count"], .string("0"))
    }

    func testUnknownResultAndLostHandleDiscardWithoutCancellation() {
        let analytics = hub()
        for unknownResult in [false, true] {
            let journey = task(analytics, entry: .packRename)
            journey.nameAccepted()
            var submission = journey.beginSubmission()
            XCTAssertNotNil(submission)
            if unknownResult { submission?.complete { nil } }
            submission = nil
            XCTAssertEqual(journey.retainedStateCount, 0)
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testDeniedOriginsAndDisabledCaptureNeverReadClockOrRetainState() {
        let analytics = hub()
        analytics.isEnabled = false
        let disabled = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.isEnabled = true
        for context in [disabled, analytics.unresolvedContext(), analytics.excludedContext()] {
            let journey = AnalyticsStickerJourney(context: context, entry: .composerCreate)
            readyImage(journey)
            journey.chooseDestination(.send)
            journey.cancel()
            XCTAssertNil(journey.beginSubmission())
            XCTAssertEqual(journey.retainedStateCount, 0)
        }
        XCTAssertEqual(clockReads, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testPrivateEntryAndAccountChangeRevokePendingResults() {
        let analytics = hub()
        for privateEntry in [true, false] {
            let journey = task(analytics, entry: .packRename)
            journey.nameAccepted()
            let submission = journey.beginSubmission()
            if privateEntry {
                let privatePresentation = analytics.excludedContext().beginPresentation()
                privatePresentation.end()
            } else {
                analytics.setSink({ _, _ in XCTFail("Old result must not reach another account") }, owner: NSObject())
            }
            submission?.complete { XCTFail("Revoked result must not be built"); return .accepted }
            XCTAssertEqual(journey.retainedStateCount, 0)
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testReentrantDisableInsideResultCannotRestoreStateOrEmit() {
        let analytics = hub()
        let journey = task(analytics, entry: .packRename)
        journey.nameAccepted()
        let submission = journey.beginSubmission()
        submission?.complete {
            analytics.isEnabled = false
            analytics.isEnabled = true
            return .accepted
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(journey.retainedStateCount, 0)
    }

    func testRepeatedRetriesAreBoundedAndEventuallyDiscard() {
        let analytics = hub()
        let journey = task(analytics, entry: .packAddExisting)
        journey.existingStickerSelected()
        var submissions = 0
        for _ in 0..<1000 {
            if let submission = journey.beginSubmission() {
                submissions += 1
                submission.complete { .retryableFailure(.packLimit) }
            }
            XCTAssertLessThanOrEqual(journey.retainedStateCount, 56)
        }
        XCTAssertEqual(submissions, 256)
        XCTAssertEqual(journey.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testEditorTeardownPreservesNamingChildAndCommittedSubmission() {
        let analytics = hub()
        let journey = task(analytics, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.newPack)
        journey.endEditor()
        XCTAssertGreaterThan(journey.retainedStateCount, 0)
        journey.nameAccepted()
        let submission = journey.beginSubmission()
        XCTAssertNotNil(submission)
        journey.endEditor()
        journey.endInteraction()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["outcome"], .string("success"))
        XCTAssertEqual(sent.last?["destination"], .string("new_pack"))
    }

    func testRepeatedPreparedOutputUpdatesFinalModeAfterReturningFromName() {
        let analytics = hub()
        let journey = task(analytics, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.newPack)
        journey.cancelNaming()
        journey.editorApplied(mode: .wholeImage)
        journey.chooseDestination(.existingPack)
        let submission = journey.beginSubmission()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.last?["image_mode"], .string("whole_image"))
        XCTAssertEqual(steps().filter { $0 == "open_editor" }.count, 1)
        XCTAssertEqual(steps().filter { $0 == "apply_editor" }.count, 2)
    }

    func testUnknownChildOrEditorDisappearanceDoesNotInventCancellation() {
        let analytics = hub()
        for naming in [true, false] {
            let journey = task(analytics, entry: .composerCreate)
            readyImage(journey)
            if naming {
                journey.chooseDestination(.newPack)
                journey.endInteraction()
            } else {
                journey.endEditor()
            }
            journey.cancel()
            XCTAssertEqual(journey.retainedStateCount, 0)
            XCTAssertTrue(sent.isEmpty)
        }
    }
    func testSendRequestSurvivesEditorCloseAndCommitsAfterDialogs() {
        let analytics = hub()
        let journey = task(analytics, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.send)
        XCTAssertNil(journey.beginSubmission())
        let request = journey.prepareSend()
        XCTAssertNotNil(request)
        XCTAssertNil(journey.prepareSend())
        journey.endEditor()
        journey.endInteraction()
        request?.step(.openConfirmation)
        request?.step(.openSchedule)
        let submission = request?.commit(scheduled: true, silent: false)
        XCTAssertNotNil(submission)
        XCTAssertNil(request?.commit(scheduled: false, silent: true))
        request?.end()
        request?.cancel()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["scheduled"], .bool(true))
        XCTAssertEqual(sent.last?["silent"], .bool(false))
        XCTAssertEqual(sent.last?["destination"], .string("send"))
        XCTAssertEqual(sent.last?["outcome"], .string("success"))
        XCTAssertEqual(Array(steps().suffix(5)), ["prepare_send", "open_confirmation", "open_schedule", "submit", "accepted"])
    }

    func testSendDialogCancellationIsExplicitAndCannotCommitLater() {
        let analytics = hub()
        for step in [AnalyticsStickerJourney.Spec.Step.cancelSchedule, .cancelConfirmation] {
            let journey = task(analytics, entry: .composerCreate)
            readyImage(journey)
            journey.chooseDestination(.send)
            let request = journey.prepareSend()
            request?.step(step)
            request?.cancel()
            XCTAssertNil(request?.commit(scheduled: true, silent: false))
            XCTAssertEqual(sent.last?["outcome"], .string("cancelled"))
            XCTAssertEqual(Array(steps().suffix(2)), [step.rawValue, "cancel"])
            XCTAssertFalse(steps().contains("submit"))
        }
        XCTAssertEqual(sent.count, 2)
    }

    func testUnknownSendDialogDismissalOrLostRequestIsNotCancellation() {
        let analytics = hub()
        for explicitEnd in [false, true] {
            let journey = task(analytics, entry: .composerCreate)
            readyImage(journey)
            journey.chooseDestination(.send)
            var request = journey.prepareSend()
            XCTAssertNotNil(request)
            request?.step(.openSchedule)
            journey.endEditor()
            if explicitEnd { request?.end() }
            request = nil
            XCTAssertEqual(journey.retainedStateCount, 0)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testPaymentRedirectionAndPermissionDenialEndUnsubmittedSend() {
        let analytics = hub()
        for reason in [AnalyticsStickerJourney.Spec.LastBlocker.paymentRequired, .chatPermission] {
            let journey = task(analytics, entry: .composerCreate)
            readyImage(journey)
            journey.chooseDestination(.send)
            let request = journey.prepareSend()
            request?.fail(reason)
            XCTAssertNil(request?.commit(scheduled: false, silent: false))
            XCTAssertEqual(sent.last?["last_blocker"], .string(reason.rawValue))
            XCTAssertEqual(sent.last?["outcome"], .string("fail"))
            XCTAssertFalse(steps().contains("submit"))
        }
        XCTAssertEqual(sent.count, 2)
    }

    func testOldSendRequestCannotCancelOrCommitLaterRetry() {
        let analytics = hub()
        let journey = task(analytics, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.send)
        let old = journey.prepareSend()
        let first = old?.commit(scheduled: false, silent: false)
        first?.complete { .retryableFailure(.enqueueRejected) }
        let next = journey.prepareSend()
        XCTAssertNotNil(next)
        old?.end()
        old?.cancel()
        old?.fail(.paymentRequired)
        old?.step(.openSchedule)
        XCTAssertNil(old?.commit(scheduled: true, silent: true))
        let submission = next?.commit(scheduled: false, silent: false)
        XCTAssertNotNil(submission)
        first?.end()
        submission?.complete { .accepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["retry_count"], .string("1"))
        XCTAssertFalse(steps().contains("open_schedule"))
    }

    func testSendRequestRevocationClearsDialogsAndSuppressesLateResultBuilder() {
        let analytics = hub()
        for submitted in [false, true] {
            let journey = task(analytics, entry: .composerCreate)
            readyImage(journey)
            journey.chooseDestination(.send)
            let request = journey.prepareSend()
            request?.step(.openConfirmation)
            let submission = submitted ? request?.commit(scheduled: false, silent: false) : nil
            let exclusion = analytics.excludedContext().beginPresentation()
            XCTAssertEqual(journey.retainedStateCount, 0)
            exclusion.end()
            XCTAssertNil(request?.commit(scheduled: true, silent: false))
            submission?.complete {
                XCTFail("Revoked send must not classify its result")
                return .accepted
            }
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testOnlySendDestinationCanPrepareSendAndUnknownEnqueueIsDiscarded() {
        let analytics = hub()
        let journey = task(analytics, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.favorites)
        XCTAssertNil(journey.prepareSend())
        journey.chooseDestination(.send)
        let request = journey.prepareSend()
        let submission = request?.commit(scheduled: false, silent: false)
        submission?.complete { nil }
        submission?.complete { .accepted }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(journey.retainedStateCount, 0)
    }

    func testSendRestrictionPreservesExactOriginalScope() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let journey = AnalyticsStickerJourney(context: origin, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.send)
        let request = journey.prepareSend()
        request?.restrict(to: origin)
        let submission = request?.commit(scheduled: false, silent: false)
        request?.restrict(to: origin)
        submission?.complete { .accepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["outcome"], .string("success"))
    }

    func testPrivateUnresolvedAndDifferentScopesDiscardPreparedAndCommittedSend() {
        for committed in [false, true] {
            for kind in 0..<4 {
                sent.removeAll()
                let analytics = hub()
                let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
                let journey = AnalyticsStickerJourney(context: origin, entry: .composerCreate)
                readyImage(journey)
                journey.chooseDestination(.send)
                let request = journey.prepareSend()
                let submission = committed ? request?.commit(scheduled: false, silent: false) : nil
                let otherAnalytics = hub()
                let incompatible: AnalyticsContext
                switch kind {
                case 0: incompatible = analytics.captureContext(owner: owner, privacy: .excluded)
                case 1: incompatible = analytics.unresolvedContext()
                case 2: incompatible = analytics.captureContext(owner: owner, privacy: .ordinary)
                default: incompatible = otherAnalytics.captureContext(owner: owner, privacy: .ordinary)
                }
                request?.restrict(to: incompatible)
                XCTAssertEqual(journey.retainedStateCount, 0)
                request?.restrict(to: origin)
                request?.step(.openConfirmation)
                request?.cancel()
                request?.fail(.paymentRequired)
                XCTAssertNil(request?.commit(scheduled: false, silent: false))
                var built = false
                submission?.complete { built = true; return .accepted }
                XCTAssertFalse(built)
                XCTAssertTrue(sent.isEmpty)
            }
        }
    }

    func testOldRequestRestrictionCannotDiscardNewRetry() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let journey = AnalyticsStickerJourney(context: origin, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.send)
        let old = journey.prepareSend()
        let first = old?.commit(scheduled: false, silent: false)
        first?.complete { .retryableFailure(.enqueueRejected) }
        let next = journey.prepareSend()
        old?.restrict(to: analytics.unresolvedContext())
        next?.restrict(to: origin)
        let second = next?.commit(scheduled: false, silent: false)
        XCTAssertNotNil(second)
        old?.restrict(to: analytics.unresolvedContext())
        second?.complete { .accepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["retry_count"], .string("1"))
    }

    func testRestrictionCannotReviveRequestAfterPolicyRevocation() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let journey = AnalyticsStickerJourney(context: origin, entry: .composerCreate)
        readyImage(journey)
        journey.chooseDestination(.send)
        let request = journey.prepareSend()
        let submission = request?.commit(scheduled: false, silent: false)
        analytics.isEnabled = false
        analytics.isEnabled = true
        request?.restrict(to: analytics.captureContext(owner: owner, privacy: .ordinary))
        var built = false
        submission?.complete { built = true; return .accepted }
        XCTAssertFalse(built)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(journey.retainedStateCount, 0)
    }

}
