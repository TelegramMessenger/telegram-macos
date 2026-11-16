import XCTest
import SwiftSignalKit
import TelegramCore
@testable import AppAnalytics

final class AnalyticsRecordingJourneyTests: XCTestCase {
    private let owner = NSObject()
    private var sent: [[String: JSON]] = []
    private var logs: [String] = []
    private var clockReads = 0
    private var now: TimeInterval = 0

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { [unowned self] in
            self.clockReads += 1
            return self.now
        })
        analytics.setSink({ [unowned self] name, value in
            XCTAssertEqual(name, AnalyticsEventName.flowEnd.rawValue)
            if case let .dictionary(data) = value { self.sent.append(data) }
        }, owner: owner)
        analytics.log = { [unowned self] in self.logs.append($0) }
        analytics.isEnabled = true
        return analytics
    }

    func testReceivingContextRestrictionPreservesEligibleRecordingRequest() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let recording = AnalyticsRecordingJourney(context: origin, kind: .voice, surface: .chat, initialMode: .hold)
        recording.started()
        let request = recording.prepareSubmission(via: .release)
        request?.restrict(to: origin)
        request?.step(.openSchedule)
        request?.restrict(to: origin)
        request?.commit(scheduled: true)?.complete { true }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["outcome"], .string("success"))
        XCTAssertEqual(sent[0]["scheduled"], .bool(true))
        XCTAssertTrue(steps().contains("open_schedule"))
    }

    func testReceivingPrivateUnknownOrForeignContextDiscardsRecordingPreparation() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let otherHub = Analytics()
        otherHub.setSink({ _, _ in XCTFail("Recorded under a foreign hub") }, owner: owner)
        otherHub.isEnabled = true
        for context in [analytics.excludedContext(), analytics.unresolvedContext(),
                        analytics.captureContext(owner: owner, privacy: .ordinary),
                        analytics.captureContext(owner: NSObject(), privacy: .ordinary),
                        otherHub.captureContext(owner: owner, privacy: .ordinary)] {
            let recording = AnalyticsRecordingJourney(context: origin, kind: .video, surface: .chat, initialMode: .hold)
            recording.started()
            let request = recording.prepareSubmission(via: .release)
            XCTAssertNotNil(request)
            request?.restrict(to: context)
            XCTAssertEqual(recording.retainedStateCount, 0)
            let reads = clockReads
            request?.restrict(to: origin)
            request?.step(.openSchedule)
            request?.fail(.preparation)
            request?.cancel()
            XCTAssertNil(request?.commit(scheduled: false))
            XCTAssertEqual(clockReads, reads)
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testRecordingRestrictionAlsoDiscardsAlreadyCommittedLateResult() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let recording = AnalyticsRecordingJourney(context: origin, kind: .voice, surface: .chat, initialMode: .hold)
        recording.started()
        let request = recording.prepareSubmission(via: .release)
        let submission = request?.commit(scheduled: false)
        XCTAssertNotNil(submission)
        request?.restrict(to: analytics.excludedContext())
        let reads = clockReads
        submission?.complete { XCTFail("Evaluated a private recording result"); return true }
        request?.restrict(to: origin)
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
    }

    func testNewReceivingContextCannotReviveRevokedRecordingRequest() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let request = recording.prepareSubmission(via: .release)
        analytics.isEnabled = false
        analytics.isEnabled = true
        let reads = clockReads
        request?.restrict(to: analytics.captureContext(owner: owner, privacy: .ordinary))
        request?.step(.openSchedule)
        request?.fail(.preparation)
        XCTAssertNil(request?.commit(scheduled: true))
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    private func task(_ analytics: Analytics, kind: AnalyticsRecordingJourney.Spec.RecordingKind = .voice, mode: AnalyticsRecordingJourney.Spec.InitialMode = .hold) -> AnalyticsRecordingJourney {
        return AnalyticsRecordingJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), kind: kind, surface: .chat, initialMode: mode)
    }

    private func steps(_ index: Int = 0) -> [String] {
        guard sent.indices.contains(index), case let .array(values)? = sent[index]["steps"] else { return [] }
        return values.compactMap { value in
            guard case let .array(pair) = value, case let .string(name)? = pair.first else { return nil }
            return name
        }
    }

    func testHoldReviewTrimResumeAndSendPreserveEntry() {
        let analytics = hub()
        let recording = task(analytics)
        recording.permissionResolved(granted: true)
        recording.started()
        recording.lock()
        recording.lock()
        recording.paused()
        recording.trimApplied()
        recording.previewReady()
        recording.previewReady()
        recording.trimApplied()
        recording.step(.openConfirmation)
        recording.step(.cancelConfirmation)
        recording.resumed()
        recording.setOneTime(true)
        recording.setOneTime(true)
        now = 2.9
        let submission = recording.beginSubmission(via: .sendControl, scheduled: false)
        submission?.complete { true }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["recording_kind"], .string("voice"))
        XCTAssertEqual(sent.first?["initial_mode"], .string("hold"))
        XCTAssertEqual(sent.first?["result"], .string("media_accepted"))
        XCTAssertEqual(sent.first?["one_time"], .bool(true))
        XCTAssertEqual(sent.first?["duration_ms"], .number(2000))
        XCTAssertEqual(steps(), ["attempt", "permission_granted", "start", "lock", "pause", "review", "trim", "open_confirmation", "cancel_confirmation", "resume", "one_time_on", "submit", "accepted"])
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testLockedEntryDoesNotInventShortcutOrSecondLock() {
        let analytics = hub()
        let recording = task(analytics, mode: .locked)
        recording.started()
        recording.lock()
        recording.cancel()
        XCTAssertEqual(steps(), ["attempt", "start", "cancel"])
        XCTAssertNil(sent.first?["via"])
        XCTAssertEqual(sent.first?["initial_mode"], .string("locked"))
        XCTAssertEqual(sent.first?["outcome"], .string("cancelled"))
    }

    func testDraftInsertionIsNotMediaOrTextEnqueue() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.setOneTime(true)
        recording.beginTranscription()
        recording.draftInserted()
        recording.cancel()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["result"], .string("draft_inserted"))
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
        XCTAssertNil(sent.first?["submit_via"])
        XCTAssertNil(sent.first?["one_time"])
        XCTAssertEqual(steps(), ["attempt", "start", "one_time_on", "transcribe", "draft_inserted"])
    }

    func testTranscriptionSendNeedsObservedAcceptance() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.beginTranscription()
        let submission = recording.beginSubmission(via: .keyboard, scheduled: true)
        XCTAssertTrue(sent.isEmpty)
        recording.draftInserted()
        recording.cancel()
        submission?.complete { true }
        XCTAssertEqual(sent.first?["result"], .string("text_accepted"))
        XCTAssertEqual(sent.first?["scheduled"], .bool(true))
        XCTAssertNil(sent.first?["one_time"])
        XCTAssertEqual(steps(), ["attempt", "start", "transcribe", "submit", "accepted"])
    }

    func testAutomaticSubmissionRequiresActivelyRecordingVideo() {
        let analytics = hub()
        let voice = task(analytics)
        voice.started()
        XCTAssertNil(voice.beginSubmission(via: .durationLimit, scheduled: false))
        voice.discard()
        let video = task(analytics, kind: .video)
        video.started()
        video.beginTranscription()
        video.paused()
        XCTAssertNil(video.beginSubmission(via: .durationLimit, scheduled: false))
        video.resumed()
        video.beginSubmission(via: .durationLimit, scheduled: false)?.complete { true }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["submit_via"], .string("duration_limit"))
        XCTAssertEqual(sent.first?["result"], .string("media_accepted"))
        XCTAssertFalse(steps().contains("transcribe"))
    }

    func testInvalidOrderAndGenericStepCannotManufactureCompletion() {
        let analytics = hub()
        let recording = task(analytics)
        recording.previewReady()
        recording.trimApplied()
        recording.resumed()
        recording.beginTranscription()
        recording.draftInserted()
        recording.step(.accepted)
        recording.step(.submit)
        XCTAssertNil(recording.beginSubmission(via: .sendControl, scheduled: false))
        XCTAssertTrue(sent.isEmpty)
        recording.permissionResolved(granted: false)
        recording.fail(.permission)
        XCTAssertEqual(steps(), ["attempt", "permission_denied", "blocked"])
        XCTAssertEqual(sent.first?["outcome"], .string("fail"))
        XCTAssertNil(sent.first?["result"])
    }

    func testSubmissionFreezesStateAndDoesNotReevaluateDuplicateResult() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let submission = recording.beginSubmission(via: .release, scheduled: false)
        XCTAssertNil(recording.beginSubmission(via: .keyboard, scheduled: true))
        recording.paused()
        recording.setOneTime(true)
        recording.beginTranscription()
        recording.fail(.preparation)
        var builds = 0
        submission?.complete { builds += 1; return true }
        submission?.complete { builds += 1; return false }
        submission?.end()
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["one_time"], .bool(false))
        XCTAssertEqual(steps(), ["attempt", "start", "submit", "accepted"])
    }

    func testUnknownAndMissingResultsDiscardInsteadOfInventingCancellation() {
        let analytics = hub()
        for unknown in [false, true] {
            let recording = task(analytics)
            recording.started()
            var submission = recording.beginSubmission(via: .sendControl, scheduled: false)
            if unknown { submission?.complete { nil } }
            submission = nil
            recording.cancel()
            XCTAssertEqual(recording.retainedStateCount, 0)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testRejectedLocalEnqueueHasExplicitFailureResult() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.blocked(.preparation)
        recording.beginSubmission(via: .sendControl, scheduled: false)?.complete { false }
        XCTAssertEqual(sent.first?["result"], .string("rejected"))
        XCTAssertEqual(sent.first?["outcome"], .string("fail"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("enqueue_rejected"))
    }

    func testExcludedAndUnresolvedAttemptsHaveNoRecorderStateOrClockReads() {
        let analytics = hub()
        let baseline = clockReads
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let recording = AnalyticsRecordingJourney(context: context, kind: .voice, surface: .storyReply, initialMode: .locked)
            recording.started()
            recording.paused()
            recording.cancel()
            XCTAssertNil(recording.beginSubmission(via: .release, scheduled: false))
            XCTAssertEqual(recording.retainedStateCount, 0)
        }
        XCTAssertEqual(clockReads, baseline)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testSecretEntryErasesStateAndSkipsLateResultBuilder() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let submission = recording.beginSubmission(via: .sendControl, scheduled: false)
        let presentation = analytics.excludedContext().beginPresentation()
        presentation.end()
        var builds = 0
        submission?.complete { builds += 1; return true }
        XCTAssertEqual(builds, 0)
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testRevocationInsideResultBuilderCannotFinish() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.beginSubmission(via: .sendControl, scheduled: false)?.complete {
            analytics.isEnabled = false
            analytics.isEnabled = true
            return true
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testAccountSwitchErasesPausedState() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.paused()
        recording.previewReady()
        let nextOwner = NSObject()
        analytics.setSink({ _, _ in XCTFail("Old recording reached new account") }, owner: nextOwner)
        recording.resumed()
        recording.cancel()
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testTrimDragRecordsOnlyChangedCommitAndClearsPendingStateOnResume() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.paused()
        recording.previewReady()
        recording.trimChanged(changed: false, committed: true)
        for _ in 0..<100 {
            recording.trimChanged(changed: true, committed: false)
        }
        recording.trimChanged(changed: false, committed: true)
        recording.resumed()
        recording.paused()
        recording.previewReady()
        recording.trimChanged(changed: true, committed: false)
        recording.resumed()
        recording.paused()
        recording.previewReady()
        recording.trimChanged(changed: false, committed: true)
        recording.cancel()
        XCTAssertEqual(steps().filter { $0 == "trim" }.count, 1)
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testPrivateEntryErasesPendingTrimCommit() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.paused()
        recording.previewReady()
        recording.trimChanged(changed: true, committed: false)
        let presentation = analytics.excludedContext().beginPresentation()
        XCTAssertEqual(recording.retainedStateCount, 0)
        presentation.end()
        var evaluations = 0
        func changed() -> Bool {
            evaluations += 1
            return true
        }
        recording.trimChanged(changed: changed(), committed: true)
        XCTAssertEqual(evaluations, 0)
        recording.cancel()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testSpeechPermissionFailureRemainsOnRecordingToTextJourney() {
        let analytics = hub()
        let recording = task(analytics)
        recording.permissionResolved(granted: true)
        recording.started()
        recording.beginTranscription()
        recording.permissionResolved(granted: false)
        recording.fail(.permission)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(steps(), ["attempt", "permission_granted", "start", "transcribe", "permission_denied", "blocked"])
        XCTAssertEqual(sent.first?["outcome"], .string("fail"))
        XCTAssertNil(sent.first?["result"])
    }

    func testPreparationFreezesOptionsBeforeConversionAndScheduling() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.setOneTime(true)
        let request = recording.prepareSubmission(via: .release)
        XCTAssertNotNil(request)
        recording.setOneTime(false)
        recording.paused()
        recording.beginTranscription()
        recording.cancel()
        XCTAssertNil(recording.prepareSubmission(via: .keyboard))
        request?.step(.openSchedule)
        let submission = request?.commit(scheduled: true)
        XCTAssertNil(request?.commit(scheduled: false))
        submission?.complete { true }
        XCTAssertEqual(sent.first?["one_time"], .bool(true))
        XCTAssertEqual(sent.first?["submit_via"], .string("release"))
        XCTAssertEqual(sent.first?["scheduled"], .bool(true))
        XCTAssertEqual(steps(), ["attempt", "start", "one_time_on", "prepare_submission", "open_schedule", "submit", "accepted"])
    }

    func testExplicitScheduleCancellationEndsPreparedAttempt() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let request = recording.prepareSubmission(via: .keyboard)
        request?.step(.openSchedule)
        request?.step(.cancelSchedule)
        request?.cancel()
        XCTAssertNil(request?.commit(scheduled: true))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("cancelled"))
        XCTAssertEqual(steps(), ["attempt", "start", "prepare_submission", "open_schedule", "cancel_schedule", "cancel"])
        XCTAssertNil(sent.first?["result"])
    }

    func testReleasingPreparationHandleCannotEraseCommittedSubmission() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        var request = recording.prepareSubmission(via: .sendControl)
        let submission = request?.commit(scheduled: false)
        request?.end()
        request = nil
        XCTAssertTrue(sent.isEmpty)
        submission?.complete { true }
        XCTAssertEqual(sent.first?["result"], .string("media_accepted"))
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testUnknownPreparationDeinitIsNotCancellation() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        var request = recording.prepareSubmission(via: .sendControl)
        XCTAssertNotNil(request)
        request = nil
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testUnknownScheduleDismissalClearsPreparationDespiteRetainedConvertedOutput() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let request = recording.prepareSubmission(via: .release)
        var retainedRequest: AnalyticsRecordingRequest?
        let disposable = request?.observingPreparation(Signal<Int, NoError>.single(1)).start(next: { _ in
            retainedRequest = request
            request?.step(.openSchedule)
        })
        XCTAssertNotNil(retainedRequest)
        XCTAssertGreaterThan(recording.retainedStateCount, 0)
        request?.end()
        XCTAssertEqual(recording.retainedStateCount, 0)
        retainedRequest?.step(.cancelSchedule)
        retainedRequest?.cancel()
        XCTAssertNil(retainedRequest?.commit(scheduled: true))
        XCTAssertTrue(sent.isEmpty)
        disposable?.dispose()
    }

    func testConversionCompletingWithoutOutputDiscardsEvenWhileRequestIsRetained() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let request = recording.prepareSubmission(via: .release)
        var completed = false
        let disposable = request?.observingPreparation(Signal<Int, NoError>.complete()).start(completed: {
            completed = true
        })
        XCTAssertTrue(completed)
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertNil(request?.commit(scheduled: false))
        XCTAssertTrue(sent.isEmpty)
        disposable?.dispose()
    }

    func testConvertedOutputTransfersToDialogBeforeSignalCompletes() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let request = recording.prepareSubmission(via: .release)
        var values: [Int] = []
        let disposable = request?.observingPreparation(Signal<Int, NoError>.single(1)).start(next: { value in
            values.append(value)
            request?.step(.openSchedule)
        })
        XCTAssertEqual(values, [1])
        XCTAssertTrue(sent.isEmpty)
        request?.commit(scheduled: true)?.complete { true }
        XCTAssertEqual(sent.first?["result"], .string("media_accepted"))
        disposable?.dispose()
    }

    func testDisposingUnfinishedConversionDiscardsOnlyAnalytics() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let request = recording.prepareSubmission(via: .sendControl)
        var disposed = false
        let source = Signal<Int, NoError> { _ in
            return ActionDisposable { disposed = true }
        }
        let disposable = request?.observingPreparation(source).start()
        disposable?.dispose()
        XCTAssertTrue(disposed)
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testRevokedConversionStillForwardsFunctionalOutput() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let request = recording.prepareSubmission(via: .release)
        let presentation = analytics.excludedContext().beginPresentation()
        presentation.end()
        var values: [Int] = []
        let disposable = request?.observingPreparation(Signal<Int, NoError>.single(7)).start(next: { values.append($0) })
        XCTAssertEqual(values, [7])
        XCTAssertNil(request?.commit(scheduled: false))
        XCTAssertEqual(recording.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
        disposable?.dispose()
    }

    func testKnownRecorderFailureDuringConversionEndsPreparedAttemptOnce() {
        let analytics = hub()
        let recording = task(analytics, kind: .video)
        recording.started()
        let request = recording.prepareSubmission(via: .durationLimit)
        recording.fail(.preparation)
        request?.fail(.preparation)
        request?.cancel()
        XCTAssertNil(request?.commit(scheduled: false))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("fail"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("preparation"))
        XCTAssertEqual(steps(), ["attempt", "start", "prepare_submission", "blocked"])
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testTextRequestSurvivesOriginalOwnerAndReportsPartialAcceptance() {
        let analytics = hub()
        var recording: AnalyticsRecordingJourney? = task(analytics)
        weak var weakRecording = recording
        recording?.started()
        recording?.beginTranscription()
        let request = recording?.prepareSubmission(via: .sendControl)
        let submission = request?.commit(scheduled: false)
        recording = nil
        XCTAssertNotNil(weakRecording)
        submission?.completeEnqueue { .partiallyAccepted }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["result"], .string("text_partially_accepted"))
        XCTAssertEqual(sent.first?["outcome"], .string("fail"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("enqueue_rejected"))
        XCTAssertNil(sent.first?["one_time"])
        XCTAssertEqual(steps(), ["attempt", "start", "transcribe", "prepare_submission", "submit", "partially_accepted"])
        XCTAssertEqual(weakRecording?.retainedStateCount, 0)
    }

    func testTextAllAcceptedAndAllRejectedRemainDistinct() {
        let analytics = hub()
        for result: AnalyticsRecordingEnqueueResult in [.accepted, .rejected] {
            let recording = task(analytics)
            recording.started()
            recording.beginTranscription()
            let request = recording.prepareSubmission(via: .sendControl)
            let submission = request?.commit(scheduled: false)
            submission?.completeEnqueue { result }
            submission?.completeEnqueue { XCTFail("Duplicate result was evaluated"); return .accepted }
        }
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["result"], .string("text_accepted"))
        XCTAssertEqual(sent[0]["outcome"], .string("success"))
        XCTAssertEqual(sent[1]["result"], .string("rejected"))
        XCTAssertEqual(sent[1]["outcome"], .string("fail"))
    }

    func testPartialResultCannotClassifySingleRecordedMedia() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        let submission = recording.beginSubmission(via: .release, scheduled: false)
        submission?.completeEnqueue { .partiallyAccepted }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testPartialClassifierCannotFinishAcrossReentrantRevocation() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        recording.beginTranscription()
        recording.beginSubmission(via: .sendControl, scheduled: false)?.completeEnqueue {
            analytics.isEnabled = false
            analytics.isEnabled = true
            return .partiallyAccepted
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(recording.retainedStateCount, 0)
    }

    func testLongReviewSessionKeepsBoundedState() {
        let analytics = hub()
        let recording = task(analytics)
        recording.started()
        for _ in 0..<1000 {
            recording.paused()
            recording.previewReady()
            recording.trimApplied()
            recording.resumed()
        }
        XCTAssertLessThanOrEqual(recording.retainedStateCount, 55)
        recording.cancel()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(steps().count, 50)
        XCTAssertEqual(sent.first?["step_count"], .number(4003))
        XCTAssertEqual(recording.retainedStateCount, 0)
    }
}
