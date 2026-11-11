import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsMediaJourneyTests: XCTestCase {
    private let owner = NSObject()
    private var sent: [[String: JSON]] = []
    private var logs: [String] = []
    private var now: TimeInterval = 100
    private var clockReads = 0

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { [unowned self] in
            self.clockReads += 1
            return self.now
        })
        analytics.setSink({ [unowned self] type, data in
            XCTAssertEqual(type, AnalyticsEventName.flowEnd.rawValue)
            if case let .dictionary(params) = data { self.sent.append(params) }
        }, owner: owner)
        analytics.log = { [unowned self] in self.logs.append($0) }
        analytics.isEnabled = true
        return analytics
    }

    private func journey(_ analytics: Analytics, entry: AnalyticsMediaJourney.Spec.EntryPoint = .clipboard) -> AnalyticsMediaJourney {
        return AnalyticsMediaJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: entry, mode: .media, source: .chat)
    }

    private func stepNames(_ payload: [String: JSON]) -> [String] {
        guard case let .array(steps)? = payload["steps"] else { return [] }
        return steps.compactMap {
            guard case let .array(pair) = $0, case let .string(step) = pair.first else { return nil }
            return step
        }
    }

    func testMultipartSubmissionRetainsExactOriginalContextAcrossEveryPart() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let task = AnalyticsMediaJourney(context: origin, entry: .attachFile, mode: .media)
        task.selected(count: 21, mode: .media)
        let submission = task.beginSubmission(parts: 4, via: .enter, scheduled: false, silent: false)
        XCTAssertTrue(submission?.context === origin)
        submission?.restrict(to: origin)
        submission?.skip(part: 0)
        for part in [3, 1, 2] {
            submission?.restrict(to: origin)
            submission?.group(part: part, count: 1)?.complete(index: 0, result: .accepted)
        }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["attachment_count"], .string("21_100"))
        XCTAssertEqual(sent[0]["entry_point"], .string("attach_file"))
        XCTAssertEqual(sent[0]["outcome"], .string("success"))
        submission?.complete(part: 3, result: .rejected)
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(submission?.context.isExcluded == true)
    }

    func testMultipartScopeMismatchDiscardsEarlierSuccessAndOutstandingResults() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let task = AnalyticsMediaJourney(context: origin, entry: .clipboard, mode: .media)
        task.selected(count: 11, mode: .media)
        let submission = task.beginSubmission(parts: 3, via: .enter, scheduled: false, silent: false)
        submission?.complete(part: 0, result: .accepted)
        let pending = submission?.group(part: 1, count: 2)
        pending?.complete(index: 0, result: .accepted)
        submission?.restrict(to: analytics.excludedContext())
        let reads = clockReads
        submission?.restrict(to: origin)
        pending?.complete(index: 1, buildResult: { XCTFail("Read result after private batch handoff"); return .accepted })
        submission?.complete(part: 2, buildResult: { XCTFail("Read later batch result"); return .accepted })
        XCTAssertNil(submission?.group(part: 2, count: 1))
        XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testDiscardedSubmissionCannotGrantContextToLaterBatchObservation() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let task = AnalyticsMediaJourney(context: origin, entry: .clipboard, mode: .media)
        task.selected(count: 2, mode: .media)
        let submission = task.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)!
        submission.restrict(to: analytics.excludedContext())
        XCTAssertTrue(submission.context.isExcluded)
        XCTAssertNil(submission.context.scope)
        let later = analytics.captureContext(owner: owner, privacy: .ordinary, inherited: submission.context)
        XCTAssertTrue(later.isExcluded)
        XCTAssertNil(later.scope)
        submission.restrict(to: origin)
        XCTAssertTrue(submission.context.isExcluded)
        XCTAssertTrue(sent.isEmpty)
    }

    func testSubmissionContextDoesNotRefreshAfterAccountOrPolicyChange() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let task = AnalyticsMediaJourney(context: origin, entry: .dropTarget, mode: .file)
        task.selected(count: 2, mode: .file)
        let submission = task.beginSubmission(parts: 2, via: .direct, scheduled: false, silent: false)
        submission?.complete(part: 0, result: .accepted)
        analytics.setSink({ _, _ in XCTFail("Emitted previous account's batch") }, owner: NSObject())
        let reads = clockReads
        XCTAssertTrue(submission?.context.isExcluded == true)
        XCTAssertFalse(submission?.context.scope?.isValid == true)
        submission?.restrict(to: analytics.unresolvedContext())
        submission?.complete(part: 1, result: .accepted)
        XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
    }

    func testOriginSurvivesAdditionsRecoveryAndDifferentSubmitMethod() {
        let analytics = hub()
        let task = journey(analytics, entry: .attachFile)
        task.selected(count: 1, mode: .file)
        task.previewShown()
        task.step(.addPaste)
        task.selected(count: 3, mode: .mixed)
        task.step(.addDrop)
        task.blocked(.captionLimit)
        task.retry()
        let submission = task.beginSubmission(parts: 1, via: .cmdEnter, scheduled: true, silent: true)
        submission?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["entry_point"], .string("attach_file"))
        XCTAssertEqual(sent.first?["submit_via"], .string("cmd_enter"))
        XCTAssertEqual(sent.first?["media_mode"], .string("mixed"))
        XCTAssertEqual(sent.first?["attachment_count"], .string("2_5"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("caption_limit"))
        XCTAssertEqual(sent.first?["retry_count"], .string("1"))
        XCTAssertEqual(sent.first?["scheduled"], .bool(true))
        XCTAssertEqual(sent.first?["silent"], .bool(true))
        XCTAssertNil(sent.first?["via"])
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "preview", "add_paste", "acquired", "add_drop", "blocked", "retry", "submit", "accepted"])
    }

    func testMatchingPreviewContextPreservesTheOriginalMediaJourney() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let task = AnalyticsMediaJourney(context: origin, entry: .attachFile, mode: .file)
        task.selected(count: 1, mode: .file)
        task.restrict(to: origin)
        task.previewShown()
        task.restrict(to: origin)
        task.cancel()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["entry_point"], .string("attach_file"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "preview", "cancel"])
    }

    func testPrivateUnknownAndDifferentPreviewScopesDiscardBeforeVisibility() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let otherHub = Analytics()
        otherHub.setSink({ _, _ in XCTFail("Foreign hub received preview event") }, owner: owner)
        otherHub.isEnabled = true
        let contexts = [analytics.excludedContext(), analytics.unresolvedContext(),
                        analytics.captureContext(owner: owner, privacy: .ordinary),
                        analytics.captureContext(owner: NSObject(), privacy: .ordinary),
                        otherHub.captureContext(owner: owner, privacy: .ordinary)]
        for context in contexts {
            let task = AnalyticsMediaJourney(context: origin, entry: .clipboard, mode: .media)
            task.selected(count: 1, mode: .media)
            task.restrict(to: context)
            XCTAssertEqual(task.retainedStateCount, 0)
            let reads = clockReads
            task.restrict(to: origin)
            task.previewShown()
            task.step(.addPaste)
            task.cancel()
            XCTAssertEqual(clockReads, reads)
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testPreviewRestrictionDiscardsPendingSubmissionAndLateResults() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let task = AnalyticsMediaJourney(context: origin, entry: .dropTarget, mode: .media)
        task.selected(count: 1, mode: .media)
        let submission = task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)
        let group = submission?.group(part: 0, count: 2)
        group?.complete(index: 0, result: .accepted)
        task.restrict(to: analytics.excludedContext())
        let reads = clockReads
        group?.complete(index: 1, buildResult: { XCTFail("Built result after private preview restriction"); return .accepted })
        submission?.complete(part: 0, result: .accepted)
        task.restrict(to: origin)
        task.close()
        XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testFreshPreviewContextCannotReviveDisabledOrRevokedOrigin() {
        let analytics = hub()
        analytics.isEnabled = false
        let disabled = journey(analytics)
        analytics.isEnabled = true
        disabled.restrict(to: analytics.captureContext(owner: owner, privacy: .ordinary))
        disabled.step(.addDrop)
        disabled.cancel()
        XCTAssertEqual(clockReads, 0)
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        let privateSurface = analytics.excludedContext().beginPresentation()
        privateSurface.end()
        let reads = clockReads
        task.restrict(to: analytics.captureContext(owner: owner, privacy: .ordinary))
        task.previewShown()
        task.cancel()
        XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
    }

    func testUnchangedAdditionsPreserveOriginSelectionBlockerAndRetryMeaning() {
        let analytics = hub()
        let task = journey(analytics, entry: .attachFile)
        task.selected(count: 2, mode: .file)
        task.previewShown()
        task.blocked(.permission)
        task.step(.addPasteUnchanged)
        task.step(.addDropUnchanged)
        task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["entry_point"], .string("attach_file"))
        XCTAssertEqual(sent[0]["attachment_count"], .string("2_5"))
        XCTAssertEqual(sent[0]["media_mode"], .string("file"))
        XCTAssertEqual(sent[0]["last_blocker"], .string("permission"))
        XCTAssertEqual(sent[0]["retry_count"], .string("0"))
        XCTAssertEqual(sent[0]["outcome"], .string("success"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "preview", "blocked", "add_paste_unchanged", "add_drop_unchanged", "submit", "accepted"])
    }

    func testRepeatedUnchangedAdditionsStayBoundedWithoutSendRetries() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        task.previewShown()
        task.step(.addPasteUnchanged)
        task.step(.addPasteUnchanged)
        task.step(.addDropUnchanged)
        for _ in 0..<100 {
            task.step(.addPasteUnchanged)
            task.step(.addDropUnchanged)
        }
        XCTAssertLessThanOrEqual(task.retainedStateCount, 56)
        task.cancel()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(stepNames(sent[0]).count, 50)
        XCTAssertEqual(Array(stepNames(sent[0]).prefix(5)), ["acquire", "acquired", "preview", "add_paste_unchanged", "add_drop_unchanged"])
        XCTAssertEqual(sent[0]["attachment_count"], .string("1"))
        XCTAssertEqual(sent[0]["retry_count"], .string("0"))
        XCTAssertEqual(sent[0]["outcome"], .string("cancelled"))
        XCTAssertNil(sent[0]["last_blocker"])
        XCTAssertEqual(task.retainedStateCount, 0)
    }

    func testUnchangedAdditionsNeverObserveDeniedOrRevokedContexts() {
        let analytics = hub()
        let steps: [AnalyticsMediaJourney.Spec.Step] = [.addPasteUnchanged, .addDropUnchanged]
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let task = AnalyticsMediaJourney(context: analytics.captureContext(owner: owner, privacy: privacy), entry: .clipboard, mode: .media)
            steps.forEach { task.step($0) }
            task.cancel()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        analytics.isEnabled = false
        let disabled = journey(analytics)
        steps.forEach { disabled.step($0) }
        analytics.isEnabled = true
        steps.forEach { disabled.step($0) }
        disabled.cancel()
        XCTAssertEqual(clockReads, 0)
        for exclusion in [false, true] {
            let task = journey(analytics)
            task.selected(count: 1, mode: .media)
            task.step(.addPasteUnchanged)
            if exclusion {
                let privateSurface = analytics.excludedContext().beginPresentation()
                privateSurface.end()
            } else {
                analytics.isEnabled = false
                analytics.isEnabled = true
            }
            let reads = clockReads
            steps.forEach { task.step($0) }
            task.cancel()
            XCTAssertEqual(task.retainedStateCount, 0)
            XCTAssertEqual(clockReads, reads)
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testAcquisitionFailureHasNoPreviewOrSubmissionAndEndsOnce() {
        let analytics = hub()
        for blocker in [AnalyticsMediaJourney.Spec.LastBlocker.sizeLimit, .fileUnavailable, .permission] {
            let task = journey(analytics)
            task.fail(blocker)
            task.fail(.preparation)
            task.cancel()
            XCTAssertEqual(sent.last?["entry_point"], .string("clipboard"))
            XCTAssertEqual(sent.last?["last_blocker"], .string(blocker.rawValue))
            XCTAssertEqual(sent.last?["outcome"], .string("fail"))
            XCTAssertEqual(sent.last?["attachment_count"], .string("0"))
            XCTAssertNil(sent.last?["submission_result"])
            XCTAssertNil(sent.last?["submit_via"])
            XCTAssertEqual(stepNames(sent.last!), ["acquire", "blocked"])
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertEqual(sent.count, 3)
    }

    func testPartialAcquisitionCanSucceedWithoutInventingRetry() {
        let analytics = hub()
        let task = journey(analytics)
        task.blocked(.fileUnavailable)
        task.selected(count: 2, mode: .media)
        task.previewShown()
        task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["entry_point"], .string("clipboard"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("file_unavailable"))
        XCTAssertEqual(sent.first?["attachment_count"], .string("2_5"))
        XCTAssertEqual(sent.first?["retry_count"], .string("0"))
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "blocked", "acquired", "preview", "submit", "accepted"])
    }

    func testAcquisitionFailuresRespectPrivateDisabledAndRevokedContexts() {
        let analytics = hub()
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let task = AnalyticsMediaJourney(context: analytics.captureContext(owner: owner, privacy: privacy), entry: .clipboard, mode: .media)
            task.blocked(.fileUnavailable)
            task.fail(.permission)
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        analytics.isEnabled = false
        let disabled = journey(analytics)
        disabled.fail(.sizeLimit)
        analytics.isEnabled = true
        disabled.fail(.fileUnavailable)
        XCTAssertEqual(clockReads, 0)
        let revoked = journey(analytics)
        revoked.blocked(.fileUnavailable)
        let exclusion = analytics.excludedContext().beginPresentation()
        exclusion.end()
        let readsAfterRevocation = clockReads
        revoked.fail(.permission)
        XCTAssertEqual(clockReads, readsAfterRevocation)
        XCTAssertEqual(revoked.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testVideoCoverChoicesRemainWithinOriginalMediaJourney() {
        let analytics = hub()
        let task = journey(analytics, entry: .dropTarget)
        task.selected(count: 1, mode: .media)
        task.previewShown()
        task.step(.openCoverPicker)
        task.step(.cancelCoverPicker)
        task.step(.openCoverPicker)
        task.step(.openEditor)
        task.step(.applyCover)
        task.step(.removeCover)
        let submission = task.beginSubmission(parts: 1, via: .sendControl, scheduled: false, silent: false)
        task.step(.applyCover)
        submission?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["entry_point"], .string("drop_target"))
        XCTAssertEqual(sent.first?["attachment_count"], .string("1"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "preview", "open_cover_picker", "cancel_cover_picker", "open_cover_picker", "open_editor", "apply_cover", "remove_cover", "submit", "accepted"])
    }

    func testVideoCoverStepsAreSuppressedForExcludedAndRevokedTasks() {
        let analytics = hub()
        let privateTask = AnalyticsMediaJourney(context: analytics.excludedContext(), entry: .clipboard, mode: .media)
        for step in [AnalyticsMediaJourney.Spec.Step.openCoverPicker, .cancelCoverPicker, .applyCover, .removeCover] { privateTask.step(step) }
        privateTask.close()
        XCTAssertEqual(clockReads, 0)
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        task.step(.openCoverPicker)
        analytics.isEnabled = false
        analytics.isEnabled = true
        let reads = clockReads
        task.step(.applyCover)
        task.close()
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testMediaPriceChoicesPreserveOriginAndFreezeAfterSubmission() {
        let analytics = hub()
        let task = journey(analytics, entry: .attachPhotoVideo)
        task.selected(count: 2, mode: .media)
        task.previewShown()
        for step in [AnalyticsMediaJourney.Spec.Step.openPrice, .cancelPrice, .openPrice, .applyPrice, .removePrice] { task.step(step) }
        let submission = task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)
        task.step(.applyPrice)
        submission?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["entry_point"], .string("attach_photo_video"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "preview", "open_price", "cancel_price", "open_price", "apply_price", "remove_price", "submit", "accepted"])
        XCTAssertFalse(sent[0].keys.contains { $0.contains("price") || $0.contains("amount") })
    }

    func testMediaPriceActionsAreSuppressedForExcludedUnresolvedDisabledAndRevokedOrigins() {
        let analytics = hub()
        let steps: [AnalyticsMediaJourney.Spec.Step] = [.openPrice, .applyPrice, .cancelPrice, .removePrice]
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let task = AnalyticsMediaJourney(context: analytics.captureContext(owner: owner, privacy: privacy), entry: .clipboard, mode: .media)
            steps.forEach { task.step($0) }
            task.close()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        analytics.isEnabled = false
        let disabled = journey(analytics)
        steps.forEach { disabled.step($0) }
        analytics.isEnabled = true
        disabled.close()
        XCTAssertEqual(clockReads, 0)
        let revoked = journey(analytics)
        revoked.step(.openPrice)
        analytics.isEnabled = false
        analytics.isEnabled = true
        let reads = clockReads
        steps.forEach { revoked.step($0) }
        revoked.close()
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testEffectPremiumDetourKeepsAcquisitionAndDoesNotImplyPurchase() {
        let analytics = hub()
        let task = journey(analytics, entry: .dropTarget)
        task.selected(count: 1, mode: .media)
        task.previewShown()
        task.step(.openEffectPremium)
        let submission = task.beginSubmission(parts: 1, via: .sendControl, scheduled: false, silent: false)
        task.step(.openEffectPremium)
        submission?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["entry_point"], .string("drop_target"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "preview", "open_effect_premium", "submit", "accepted"])
        XCTAssertFalse(sent[0].keys.contains { $0.contains("effect") || $0.contains("purchase") || $0.contains("premium") })
    }

    func testEffectPremiumStepDoesNotObservePrivateDisabledOrRevokedOrigins() {
        let analytics = hub()
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let task = AnalyticsMediaJourney(context: analytics.captureContext(owner: owner, privacy: privacy), entry: .clipboard, mode: .media)
            task.step(.openEffectPremium)
            task.close()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        analytics.isEnabled = false
        let disabled = journey(analytics)
        disabled.step(.openEffectPremium)
        analytics.isEnabled = true
        disabled.close()
        XCTAssertEqual(clockReads, 0)
        let revoked = journey(analytics)
        let exclusion = analytics.excludedContext().beginPresentation()
        exclusion.end()
        let reads = clockReads
        revoked.step(.openEffectPremium)
        revoked.close()
        XCTAssertEqual(clockReads, reads)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testDirectDropDoesNotInventPreview() {
        let analytics = hub()
        let task = AnalyticsMediaJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .dropTarget, mode: .file, via: .dragDrop)
        task.preparing()
        task.selected(count: 2, mode: .file)
        task.beginSubmission(parts: 1, via: .direct, scheduled: false, silent: false)?.complete(part: 0, result: .accepted)
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "prepare", "acquired", "submit", "accepted"])
        XCTAssertEqual(sent.first?["via"], .string("drag_drop"))
    }

    func testMultipleEnqueuesProduceOneOutcomeAfterEveryPart() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 21, mode: .media)
        let submission = task.beginSubmission(parts: 4, via: .sendControl, scheduled: false, silent: false)
        XCTAssertNil(task.beginSubmission(parts: 4, via: .enter, scheduled: false, silent: false))
        task.close()
        task.cancel()
        submission?.complete(part: 3, result: .accepted)
        submission?.complete(part: 0, result: .accepted)
        submission?.complete(part: 0, result: .rejected)
        submission?.complete(part: 2, result: .accepted)
        XCTAssertTrue(sent.isEmpty)
        submission?.complete(part: 1, result: .accepted)
        submission?.complete(part: 1, result: .rejected)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
        XCTAssertEqual(sent.first?["attachment_count"], .string("21_100"))
        XCTAssertEqual(task.retainedStateCount, 0)
    }

    func testPartialAcceptanceWithinOneBatchIsNotSuccessOrTotalRejection() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 3, mode: .media)
        task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)?.complete(part: 0, result: .partiallyAccepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("fail"))
        XCTAssertEqual(sent.first?["submission_result"], .string("partially_accepted"))
    }

    func testMixedAndFullyRejectedBatches() {
        let analytics = hub()
        for first in [AnalyticsMediaJourney.Spec.SubmissionResult.accepted, .rejected] {
            let task = journey(analytics)
            task.selected(count: 12, mode: .media)
            let submission = task.beginSubmission(parts: 2, via: .sendControl, scheduled: false, silent: false)
            submission?.complete(part: 0, result: first)
            submission?.complete(part: 1, result: .rejected)
        }
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["submission_result"], .string("partially_accepted"))
        XCTAssertEqual(sent[1]["submission_result"], .string("rejected"))
        XCTAssertTrue(sent.allSatisfy { $0["outcome"] == .string("fail") })
    }

    func testMissingResultAndDestroyedOwnerDoNotInventFailureOrAbandonment() {
        let analytics = hub()
        var task: AnalyticsMediaJourney? = journey(analytics)
        task?.selected(count: 1, mode: .media)
        task = nil
        var submitting: AnalyticsMediaJourney? = journey(analytics)
        submitting?.selected(count: 1, mode: .media)
        let submission = submitting?.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)
        submitting = nil
        submission?.complete(part: 0, result: .accepted)
        submission?.complete(part: 1, result: nil)
        submission?.complete(part: 1, result: .accepted)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testSubmissionRetainsTaskUntilKnownResults() {
        let analytics = hub()
        var task: AnalyticsMediaJourney? = journey(analytics)
        task?.selected(count: 1, mode: .media)
        let submission = task?.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)
        task = nil
        submission?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
    }

    func testExplicitCancellationAndCloseAreDistinctAndDeduplicated() {
        let analytics = hub()
        let cancelled = journey(analytics)
        cancelled.cancel()
        cancelled.close()
        cancelled.fail(.preparation)
        let closed = journey(analytics)
        closed.selected(count: 1, mode: .media)
        closed.step(.openEditor)
        closed.step(.cancelEditor)
        XCTAssertEqual(sent.count, 1)
        closed.close()
        closed.cancel()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["outcome"], .string("cancelled"))
        XCTAssertEqual(sent[0]["attachment_count"], .string("0"))
        XCTAssertEqual(sent[1]["outcome"], .string("abandoned"))
    }

    func testDeniedContextsDoNotReadClockOrRetainState() {
        let analytics = hub()
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let context = analytics.captureContext(owner: owner, privacy: privacy)
            let task = AnalyticsMediaJourney(context: context, entry: .clipboard, mode: .media)
            task.selected(count: 10, mode: .file)
            task.blocked(.permission)
            task.retry()
            task.preparing()
            task.previewShown()
            task.step(.addDrop)
            XCTAssertNil(task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false))
            task.cancel()
            task.close()
            task.fail(.preparation)
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        analytics.isEnabled = false
        let disabled = journey(analytics)
        disabled.selected(count: 1, mode: .media)
        analytics.isEnabled = true
        disabled.cancel()
        XCTAssertEqual(disabled.retainedStateCount, 0)
        XCTAssertEqual(clockReads, 0)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testRevocationErasesPendingResultsAndNeverRevives() {
        let analytics = hub()
        for revoke in 0..<3 {
            let task = journey(analytics)
            task.selected(count: 11, mode: .media)
            task.blocked(.captionLimit)
            task.retry()
            let submission = task.beginSubmission(parts: 2, via: .sendMenu, scheduled: false, silent: false)
            submission?.complete(part: 0, result: .accepted)
            XCTAssertGreaterThan(task.retainedStateCount, 0)
            switch revoke {
            case 0:
                analytics.isEnabled = false
                analytics.isEnabled = true
            case 1:
                let privateSurface = analytics.excludedContext().beginPresentation()
                privateSurface.end()
            default:
                analytics.setSink(nil, owner: nil)
                analytics.setSink({ _, _ in XCTFail("Revived task") }, owner: owner)
            }
            XCTAssertEqual(task.retainedStateCount, 0)
            submission?.complete(part: 1, result: .accepted)
            task.close()
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testConcurrentDuplicateResultsFinishOnce() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 100, mode: .media)
        let submission = task.beginSubmission(parts: 10, via: .sendControl, scheduled: false, silent: false)
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            submission?.complete(part: index % 10, result: .accepted)
        }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(task.retainedStateCount, 0)
    }

    func testInvalidAndOversizedSubmissionIsDiscardedWithoutAResult() {
        let analytics = hub()
        for count in [0, -1, 257, Int.max] {
            let task = journey(analytics)
            task.selected(count: 1, mode: .media)
            XCTAssertNil(task.beginSubmission(parts: count, via: .enter, scheduled: false, silent: false))
            task.close()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)?.complete(part: 1, result: .accepted)
        XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testEmptyOrStillPreparingTasksCannotClaimSubmission() {
        let analytics = hub()
        let task = journey(analytics)
        task.previewShown()
        XCTAssertNil(task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false))
        task.selected(count: 1, mode: .media)
        task.preparing()
        XCTAssertNil(task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false))
        task.previewShown()
        task.selected(count: 0, mode: .media)
        XCTAssertNil(task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false))
        task.cancel()
        XCTAssertEqual(sent.first?["attachment_count"], .string("0"))
    }

    func testTimingsAreCoarseAndFineGrainedPayloadsAreRejected() {
        let analytics = hub()
        let task = journey(analytics)
        now += 0.234
        task.selected(count: 1, mode: .media)
        now += 1.7
        task.previewShown()
        now += 0.9
        task.close()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["duration_ms"], .number(2000))
        var payload = sent[0]
        XCTAssertTrue(Analytics.validate(type: AnalyticsEventName.flowEnd.rawValue, params: payload).isEmpty)
        payload["duration_ms"] = .number(2001)
        XCTAssertFalse(Analytics.validate(type: AnalyticsEventName.flowEnd.rawValue, params: payload).isEmpty)
        payload["duration_ms"] = .number(2000)
        payload["steps"] = .array([.array([.string("acquire"), .number(1)])])
        payload["step_count"] = .number(1)
        XCTAssertFalse(Analytics.validate(type: AnalyticsEventName.flowEnd.rawValue, params: payload).isEmpty)
    }

    func testRetryAndStepStorageAreBoundedWithoutExactAttachmentCounts() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: Int.max, mode: .file)
        for _ in 0..<100 {
            task.blocked(.permission)
            task.retry()
        }
        XCTAssertLessThanOrEqual(task.retainedStateCount, 55)
        task.close()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["retry_count"], .string("4_plus"))
        XCTAssertEqual(sent.first?["attachment_count"], .string("101_plus"))
        XCTAssertEqual(stepNames(sent[0]).count, 50)
        XCTAssertEqual(sent.first?["step_count"], .number(203))
    }

    func testNegativeSelectionAndExcludedSourceDiscardWithoutAClock() {
        let analytics = hub()
        let context = analytics.captureContext(owner: owner, privacy: .ordinary)
        let excluded = AnalyticsMediaJourney(context: context, entry: .clipboard, mode: .media, source: .createSecretChat)
        excluded.selected(count: 1, mode: .media)
        excluded.cancel()
        XCTAssertEqual(clockReads, 0)
        XCTAssertEqual(excluded.retainedStateCount, 0)
        let task = journey(analytics)
        task.selected(count: -1, mode: .media)
        task.fail(.preparation)
        XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testEmptyComposerDoesNotPreventMediaSuccess() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        let submission = task.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)
        XCTAssertNil(submission?.group(part: 0, count: 0))
        XCTAssertTrue(sent.isEmpty)
        submission?.complete(part: 1, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
    }

    func testAllSkippedPartsDoNotInventASend() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        let submission = task.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)
        submission?.skip(part: 0)
        submission?.skip(part: 1)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(task.retainedStateCount, 0)
    }

    func testComposerGroupAggregatesTextAndForwardBeforeMediaOutcome() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 11, mode: .media)
        let submission = task.beginSubmission(parts: 3, via: .cmdEnter, scheduled: true, silent: false)
        let group = submission?.group(part: 0, count: 2)
        XCTAssertNotNil(group)
        XCTAssertNil(submission?.group(part: 0, count: 2))
        submission?.complete(part: 2, result: .accepted)
        group?.complete(index: 1, result: .rejected)
        group?.complete(index: 1, result: .accepted)
        submission?.complete(part: 1, result: .accepted)
        XCTAssertTrue(sent.isEmpty)
        group?.complete(index: 0, result: .accepted)
        group?.end()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["submission_result"], .string("partially_accepted"))
        XCTAssertEqual(sent.first?["outcome"], .string("fail"))
        XCTAssertEqual(group?.retainedStateCount, 0)
    }

    func testUnfinishedGroupEndOrReleaseDiscardsWholeSubmission() {
        let analytics = hub()
        for explicitlyEnd in [false, true] {
            let task = journey(analytics)
            task.selected(count: 1, mode: .media)
            let submission = task.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)
            var group = submission?.group(part: 0, count: 2)
            group?.complete(index: 0, result: .accepted)
            if explicitlyEnd {
                group?.end()
                group?.complete(index: 1, result: .accepted)
            }
            group = nil
            submission?.complete(part: 1, result: .accepted)
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testGroupRevocationErasesStateAndSuppressesResultBuilders() {
        let analytics = hub()
        for revoke in 0..<3 {
            let task = journey(analytics)
            task.selected(count: 1, mode: .media)
            let submission = task.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)
            let group = submission?.group(part: 0, count: 2)
            group?.complete(index: 0, result: .accepted)
            XCTAssertGreaterThan(group?.retainedStateCount ?? 0, 0)
            switch revoke {
            case 0:
                analytics.isEnabled = false
                analytics.isEnabled = true
            case 1:
                let presentation = analytics.excludedContext().beginPresentation()
                presentation.end()
            default:
                analytics.setSink(nil, owner: nil)
                analytics.setSink({ _, _ in XCTFail("Revived group") }, owner: owner)
            }
            group?.complete(index: 1, buildResult: { XCTFail("Built revoked result"); return .accepted })
            submission?.complete(part: 1, buildResult: { XCTFail("Built revoked part"); return .accepted })
            XCTAssertEqual(group?.retainedStateCount, 0)
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testInvalidGroupAndPartIndicesNeverBuildResults() {
        let analytics = hub()
        for invalid in [-1, 2, Int.max] {
            let task = journey(analytics)
            task.selected(count: 1, mode: .media)
            let submission = task.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)
            let group = submission?.group(part: 0, count: 2)
            group?.complete(index: invalid, buildResult: { XCTFail("Built invalid group result"); return .accepted })
            XCTAssertEqual(task.retainedStateCount, 0)
            XCTAssertEqual(group?.retainedStateCount, 0)

            let other = journey(analytics)
            other.selected(count: 1, mode: .media)
            other.beginSubmission(parts: 2, via: .enter, scheduled: false, silent: false)?.complete(part: invalid, buildResult: { XCTFail("Built invalid part result"); return .accepted })
            XCTAssertEqual(other.retainedStateCount, 0)
        }
        for count in [-1, 3, Int.max] {
            let task = journey(analytics)
            task.selected(count: 1, mode: .media)
            let submission = task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)
            XCTAssertNil(submission?.group(part: 0, count: count))
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testDuplicateAndFinishedGroupResultsAreNotBuilt() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        let submission = task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)
        let group = submission?.group(part: 0, count: 2)
        group?.complete(index: 0, result: .accepted)
        group?.complete(index: 0, buildResult: { XCTFail("Built duplicate result"); return .accepted })
        group?.complete(index: 1, result: .accepted)
        group?.complete(index: 1, buildResult: { XCTFail("Built finished result"); return .accepted })
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(group?.retainedStateCount, 0)
    }

    func testConcurrentGroupCallbacksFinishOnce() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        let submission = task.beginSubmission(parts: 1, via: .enter, scheduled: false, silent: false)
        let group = submission?.group(part: 0, count: 2)
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            group?.complete(index: index % 2, result: .accepted)
        }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
        XCTAssertEqual(group?.retainedStateCount, 0)
    }

    func testSelectionBlockerDoesNotTurnFirstSubmissionIntoRetry() {
        let analytics = hub()
        let task = journey(analytics, entry: .attachFile)
        task.blocked(.sizeLimit)
        task.selected(count: 1, mode: .file)
        task.retrySubmissionIfBlocked()
        task.beginSubmission(parts: 1, via: .sendControl, scheduled: false, silent: false)?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.first?["retry_count"], .string("0"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("size_limit"))
        XCTAssertFalse(stepNames(sent[0]).contains("retry"))
    }

    func testBlockedSubmissionCountsEachNewAttemptOnceAcrossPreviewChanges() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        task.retrySubmissionIfBlocked()
        task.submissionBlocked(.captionLimit)
        task.submissionBlocked(.captionLimit)
        task.step(.addDrop)
        task.selected(count: 2, mode: .media)
        task.retrySubmissionIfBlocked()
        task.retrySubmissionIfBlocked()
        task.submissionBlocked(.slowMode)
        task.retrySubmissionIfBlocked()
        task.beginSubmission(parts: 1, via: .cmdEnter, scheduled: false, silent: false)?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["retry_count"], .string("2_3"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("slow_mode"))
        XCTAssertEqual(stepNames(sent[0]).filter { $0 == "retry" }.count, 2)
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
        XCTAssertEqual(task.retainedStateCount, 0)
    }

    func testBlockedRetryStateIsErasedOnEveryRevocationBoundary() {
        for revoke in 0..<3 {
            let analytics = hub()
            let task = journey(analytics)
            task.selected(count: 1, mode: .media)
            task.submissionBlocked(.permission)
            switch revoke {
            case 0:
                analytics.isEnabled = false
                analytics.isEnabled = true
            case 1:
                let presentation = analytics.excludedContext().beginPresentation()
                presentation.end()
            default:
                analytics.setSink(nil, owner: nil)
                analytics.setSink({ _, _ in XCTFail("Revived retry") }, owner: owner)
            }
            let reads = clockReads
            task.retrySubmissionIfBlocked()
            task.submissionBlocked(.captionLimit)
            task.close()
            XCTAssertEqual(task.retainedStateCount, 0)
            XCTAssertEqual(clockReads, reads)
        }
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testLatePreviewChangesAndBlockersCannotRewritePendingSubmission() {
        let analytics = hub()
        let task = journey(analytics, entry: .attachFile)
        task.selected(count: 1, mode: .file)
        task.submissionBlocked(.preparation)
        task.retrySubmissionIfBlocked()
        let submission = task.beginSubmission(parts: 1, via: .sendControl, scheduled: false, silent: false)
        task.step(.addPaste)
        task.step(.addPasteUnchanged)
        task.step(.addDropUnchanged)
        task.selected(count: 100, mode: .mixed)
        task.submissionBlocked(.captionLimit)
        task.retrySubmissionIfBlocked()
        submission?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.first?["retry_count"], .string("1"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("preparation"))
        XCTAssertEqual(sent.first?["attachment_count"], .string("1"))
        XCTAssertEqual(sent.first?["media_mode"], .string("file"))
        XCTAssertFalse(stepNames(sent[0]).contains("add_paste"))
        XCTAssertFalse(stepNames(sent[0]).contains("add_paste_unchanged"))
        XCTAssertFalse(stepNames(sent[0]).contains("add_drop_unchanged"))
    }

    func testRepeatedBlockedSubmissionAttemptsRemainBounded() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .media)
        for _ in 0..<100 {
            task.submissionBlocked(.preparation)
            task.retrySubmissionIfBlocked()
        }
        task.submissionBlocked(.permission)
        XCTAssertLessThanOrEqual(task.retainedStateCount, 56)
        task.cancel()
        XCTAssertEqual(sent.first?["retry_count"], .string("4_plus"))
        XCTAssertEqual(stepNames(sent[0]).count, 50)
        XCTAssertEqual(task.retainedStateCount, 0)
    }

    func testCancellingScheduleAndConfirmationKeepsPreviewJourneyActive() {
        let analytics = hub()
        let task = journey(analytics, entry: .attachPhotoVideo)
        task.selected(count: 3, mode: .media)
        task.previewShown()
        task.step(.openSchedule)
        task.step(.cancelSchedule)
        task.step(.openConfirmation)
        task.step(.cancelConfirmation)
        XCTAssertTrue(sent.isEmpty)
        task.step(.openSchedule)
        task.beginSubmission(parts: 1, via: .sendMenu, scheduled: true, silent: false)?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("success"))
        XCTAssertEqual(sent.first?["entry_point"], .string("attach_photo_video"))
        XCTAssertEqual(sent.first?["scheduled"], .bool(true))
        XCTAssertEqual(sent.first?["retry_count"], .string("0"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "preview", "open_schedule", "cancel_schedule", "open_confirmation", "cancel_confirmation", "open_schedule", "submit", "accepted"])
    }

    func testConfirmedPreviewDiscardEndsOnceAfterReturningFromDialog() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 1, mode: .file)
        task.step(.openConfirmation)
        task.step(.cancelConfirmation)
        XCTAssertTrue(sent.isEmpty)
        task.step(.openConfirmation)
        task.cancel()
        task.cancel()
        task.step(.cancelConfirmation)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("cancelled"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "open_confirmation", "cancel_confirmation", "open_confirmation", "cancel"])
    }

    func testDirectDropScheduleCancellationEndsWithoutPreviewOrSubmission() {
        let analytics = hub()
        let task = journey(analytics, entry: .dropTarget)
        task.selected(count: 2, mode: .file)
        task.step(.openSchedule)
        task.step(.cancelSchedule)
        task.cancel()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["outcome"], .string("cancelled"))
        XCTAssertNil(sent.first?["submission_result"])
        XCTAssertNil(sent.first?["scheduled"])
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "open_schedule", "cancel_schedule", "cancel"])
    }

    func testPrivateEntryDuringChildDialogSuppressesLateSelectionAndCancel() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 2, mode: .media)
        task.step(.openSchedule)
        let presentation = analytics.excludedContext().beginPresentation()
        presentation.end()
        let reads = clockReads
        task.step(.cancelSchedule)
        task.step(.openConfirmation)
        task.step(.cancelConfirmation)
        XCTAssertNil(task.beginSubmission(parts: 1, via: .sendMenu, scheduled: true, silent: false))
        task.cancel()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertEqual(clockReads, reads)
    }

    func testArchiveChoicePreservesInputCountAndAcquisitionAcrossRetry() {
        let analytics = hub()
        let task = journey(analytics, entry: .attachFile)
        task.selected(count: 4, mode: .file)
        task.previewShown()
        task.step(.selectArchive)
        task.submissionBlocked(.preparation)
        task.retrySubmissionIfBlocked()
        task.selected(count: 4, mode: .archive)
        task.beginSubmission(parts: 1, via: .sendControl, scheduled: false, silent: false)?.complete(part: 0, result: .accepted)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["entry_point"], .string("attach_file"))
        XCTAssertEqual(sent.first?["media_mode"], .string("archive"))
        XCTAssertEqual(sent.first?["attachment_count"], .string("2_5"))
        XCTAssertEqual(sent.first?["retry_count"], .string("1"))
        XCTAssertEqual(sent.first?["last_blocker"], .string("preparation"))
        XCTAssertTrue(stepNames(sent[0]).contains("select_archive"))
        XCTAssertTrue(Analytics.validate(type: AnalyticsEventName.flowEnd.rawValue, params: sent[0]).isEmpty)
    }

    func testReturningFromArchiveToMediaPreservesChoiceHistoryAndFinalMode() {
        let analytics = hub()
        let task = journey(analytics)
        task.selected(count: 3, mode: .media)
        task.step(.selectArchive)
        task.step(.selectFile)
        task.step(.selectMedia)
        task.cancel()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["media_mode"], .string("media"))
        XCTAssertEqual(sent.first?["entry_point"], .string("clipboard"))
        XCTAssertEqual(stepNames(sent[0]), ["acquire", "acquired", "select_archive", "select_file", "select_media", "cancel"])
    }

    func testBackwardsClockWithinOneTimingBucketIsDiscarded() {
        let analytics = hub()
        let task = journey(analytics)
        now += 0.8
        task.selected(count: 1, mode: .media)
        now -= 0.3
        task.previewShown()
        task.close()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }
}
