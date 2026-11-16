import XCTest
import TelegramCore
@testable import AppAnalytics

final class AnalyticsForwardPickerJourneyTests: XCTestCase {
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
    private func journey(_ analytics: Analytics, entry: AnalyticsForwardPickerJourney.Spec.EntryPoint = .messageMenu) -> AnalyticsForwardPickerJourney {
        AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: entry)
    }
    private func steps() -> [String] {
        guard case let .array(values)? = sent.last?["steps"] else { return [] }
        return values.compactMap { guard case let .array(pair) = $0, case let .string(value)? = pair.first else { return nil }; return value }
    }
    func testExplicitRoutesPreserveDistinctPreparationReadinessAndAcceptance() {
        let analytics = hub()
        for entry: AnalyticsForwardPickerJourney.Spec.EntryPoint in [.messageSelection, .messageMenu, .moreMenu, .replacementMenu, .rowAction] {
            for result: AnalyticsForwardPickerJourney.Spec.Result in [.draftPrepared, .destinationReady, .accepted] {
                now = 0; let task = journey(analytics, entry: entry)
                task.pickerOpened(); task.submitted(topic: result == .destinationReady); now = 3.76; task.complete(result)
                task.complete(.accepted); task.cancel()
                XCTAssertEqual(sent.last?["flow"], .string("chat.forward_picker")); XCTAssertEqual(sent.last?["entry_point"], .string(entry.rawValue))
                XCTAssertEqual(sent.last?["result"], .string(result.rawValue)); XCTAssertEqual(sent.last?["outcome"], .string("success"))
                XCTAssertEqual(sent.last?["destination"], .string(result == .destinationReady ? "topic" : "chat")); XCTAssertEqual(sent.last?["duration_ms"], .number(3000))
                XCTAssertEqual(task.retainedStateCount, 0)
                XCTAssertEqual(sent.last?["search_used"], .bool(false))
                for key in ["peer_id", "thread_id", "message_id", "comment", "query", "error", "source"] { XCTAssertNil(sent.last?[key]) }
            }
        }
        XCTAssertEqual(sent.count, 15)
    }
    func testMissingRejectedPartialAndUnknownRemainDistinctFailures() {
        let analytics = hub()
        for result: AnalyticsForwardPickerJourney.Spec.Result in [.sourceUnavailable, .targetUnavailable, .partiallyAccepted, .rejected, .acceptanceUnknown] {
            let task = journey(analytics); task.complete(result); XCTAssertEqual(task.retainedStateCount > 0, true)
            task.pickerOpened(); task.submitted(topic: false); task.complete(result)
            XCTAssertEqual(sent.last?["result"], .string(result.rawValue)); XCTAssertEqual(sent.last?["outcome"], .string("fail"))
        }
        XCTAssertEqual(sent.count, 5)
    }
    func testBlockerRetryIsBoundedAndPollErrorDoesNotOverwriteItsReason() {
        let analytics = hub()
        let tracked = journey(analytics); tracked.pickerOpened(); tracked.blocked(.premiumRequired)
        for _ in 0..<6 {
            tracked.submitted(topic: false); tracked.blocked(.pollRestriction); tracked.operationFailed(); tracked.submissionEnded()
        }
        tracked.submitted(topic: true); tracked.complete(.destinationReady)
        XCTAssertEqual(sent.last?["retry_count"], .string("4_plus")); XCTAssertEqual(sent.last?["last_blocker"], .string("poll_restriction"))
        XCTAssertEqual(steps().filter { $0 == "retry" }.count, 7)
        XCTAssertEqual(sent.last?["destination"], .string("topic"))
    }
    func testOperationalErrorCanRetryButUnexplainedDisposalDiscards() {
        let analytics = hub()
        let tracked = journey(analytics); tracked.pickerOpened(); tracked.submitted(topic: false); tracked.operationFailed(); tracked.submissionEnded()
        tracked.submitted(topic: false); tracked.complete(.draftPrepared)
        XCTAssertEqual(sent.last?["last_blocker"], .string("operation_failed")); XCTAssertEqual(sent.last?["retry_count"], .string("1"))
        let lost = journey(analytics); lost.pickerOpened(); lost.submitted(topic: false); lost.submissionEnded(); lost.cancel(); lost.complete(.accepted)
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(lost.retainedStateCount, 0)
    }
    func testExplicitCancellationHasNoAcceptanceResultAndIsOnceOnly() {
        let analytics = hub()
        for pending in [false, true] {
            let task = journey(analytics); task.pickerOpened()
            if pending { task.submitted(topic: false) } else { task.blocked(.premiumRequired) }
            task.cancel(); task.cancel(); task.complete(.accepted)
            XCTAssertEqual(sent.last?["outcome"], .string("cancelled")); XCTAssertNil(sent.last?["result"])
        }
        XCTAssertEqual(sent.count, 2)
    }
    func testPrivateAndMissingScopesDoNotCollectOrReadClock() {
        let analytics = hub()
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let task = AnalyticsForwardPickerJourney(context: context, entry: .replacementMenu)
            task.pickerOpened(); task.blocked(.premiumRequired); task.submitted(topic: false); task.complete(.accepted); task.cancel()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertEqual(reads, 0); XCTAssertTrue(sent.isEmpty)
    }
    func testRevocationDuringRetryCannotRestoreRecording() {
        let analytics = hub()
        let tracked = journey(analytics); tracked.pickerOpened(); tracked.blocked(.pollRestriction)
        onClock = { self.onClock = nil; analytics.isEnabled = false; analytics.isEnabled = true }
        tracked.submitted(topic: true); tracked.complete(.destinationReady); tracked.cancel()
        XCTAssertTrue(sent.isEmpty); XCTAssertEqual(tracked.retainedStateCount, 0)
    }
    func testOwnerDestructionDoesNotInventCancellation() {
        let analytics = hub()
        var task: AnalyticsForwardPickerJourney? = journey(analytics)
        task?.pickerOpened(); task = nil
        XCTAssertTrue(sent.isEmpty)
    }
    func testSourceCoverageIsCategoricalAndDoesNotChangeDeliveryMeaning() {
        let analytics = hub()
        for coverage: AnalyticsForwardPickerJourney.Spec.SourceCoverage in [.complete, .partial, .unexpected] {
            let task = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
            task.sourceReady(coverage: coverage); task.sourceReady(coverage: .unexpected)
            task.pickerOpened(); task.submitted(topic: false); task.complete(.draftPrepared)
            XCTAssertEqual(sent.last?["source_coverage"], .string(coverage.rawValue))
            XCTAssertEqual(sent.last?["result"], .string("draft_prepared"))
            XCTAssertEqual(sent.last?["outcome"], .string("success"))
            for key in ["selected_ids", "returned_ids", "message_ids", "source_count", "missing_count", "source_hash"] { XCTAssertNil(sent.last?[key]) }
        }
        XCTAssertEqual(sent.count, 3)
    }
    func testSourceCoverageIsNotGuessedForUnknownEmptyOrPickerOnlyStarts() {
        let analytics = hub()
        let unknown = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        unknown.sourceReady(); unknown.pickerOpened(); unknown.cancel()
        let empty = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        empty.sourceUnavailable()
        let legacy = journey(analytics); legacy.sourceReady(coverage: .complete); legacy.pickerOpened(); legacy.cancel()
        XCTAssertEqual(sent.count, 3)
        for summary in sent { XCTAssertNil(summary["source_coverage"]) }
    }
    func testSourceCoverageDoesNotEvaluateWhenPrivateRevokedOrAlreadyResolved() {
        let analytics = hub()
        var evaluations = 0
        func coverage() -> AnalyticsForwardPickerJourney.Spec.SourceCoverage { evaluations += 1; return .complete }
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let task = AnalyticsForwardPickerJourney(context: context, entry: .messageSelection, sourceLookup: true)
            task.sourceReady(coverage: coverage()); task.sourceUnavailable()
        }
        XCTAssertEqual(evaluations, 0); XCTAssertEqual(reads, 0)
        let task = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        task.sourceReady(coverage: coverage()); task.sourceReady(coverage: coverage())
        XCTAssertEqual(evaluations, 1)
        analytics.isEnabled = false; analytics.isEnabled = true
        task.sourceReady(coverage: coverage()); task.pickerOpened(); task.cancel()
        XCTAssertEqual(evaluations, 1); XCTAssertTrue(sent.isEmpty)
    }
    func testSourceCoverageCannotRestoreStateRevokedDuringEvaluation() {
        let analytics = hub()
        let task = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        task.sourceReady(coverage: {
            analytics.isEnabled = false; analytics.isEnabled = true
            return .partial
        }())
        task.pickerOpened(); task.submitted(topic: false); task.complete(.accepted)
        XCTAssertEqual(task.retainedStateCount, 0); XCTAssertTrue(sent.isEmpty)
    }
    func testSourceLookupContinuesIntoOnePickerSummary() {
        let analytics = hub()
        let task = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        task.pickerOpened(); task.searchUsed(); task.cancel()
        now = 1.9; task.sourceReady(); task.sourceReady()
        now = 2.5; task.pickerOpened(); task.submitted(topic: false)
        now = 4.9; task.complete(.accepted); task.sourceUnavailable()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["source_lookup"], .bool(true))
        XCTAssertEqual(sent.last?["duration_ms"], .number(4000))
        XCTAssertEqual(steps(), ["lookup_source", "source_ready", "open_picker", "choose_chat", "accepted"])
    }
    func testSourceLookupKnownEmptyIsFailureWithoutInventingPickerOrSelection() {
        let analytics = hub()
        let task = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        task.sourceUnavailable(); task.sourceUnavailable(); task.pickerOpened(); task.cancel()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(steps(), ["lookup_source", "source_unavailable"])
        XCTAssertEqual(sent.last?["outcome"], .string("fail"))
        XCTAssertEqual(sent.last?["result"], .string("source_unavailable"))
        XCTAssertNil(sent.last?["activation"]); XCTAssertNil(sent.last?["destination"])
        XCTAssertEqual(task.retainedStateCount, 0)
    }
    func testSourceLookupUnknownCompletionAndRevocationDiscard() {
        let analytics = hub()
        let task = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        task.discard(); task.sourceUnavailable(); task.pickerOpened(); task.cancel()
        let revoked = AnalyticsForwardPickerJourney(context: analytics.captureContext(owner: owner, privacy: .ordinary), entry: .messageSelection, sourceLookup: true)
        let lifetime = analytics.excludedContext().beginPresentation(); lifetime.end()
        revoked.sourceReady(); revoked.pickerOpened(); revoked.cancel()
        XCTAssertEqual(task.retainedStateCount, 0); XCTAssertEqual(revoked.retainedStateCount, 0); XCTAssertTrue(sent.isEmpty)
    }
    func testSourceLookupPrivateOriginsAreInertAndLegacyPickerDoesNotClaimLookup() {
        let analytics = hub()
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let task = AnalyticsForwardPickerJourney(context: context, entry: .messageSelection, sourceLookup: true)
            task.sourceReady(); task.sourceUnavailable(); task.pickerOpened(); task.cancel()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertEqual(reads, 0); XCTAssertTrue(sent.isEmpty)
        let task = journey(analytics, entry: .messageSelection); task.sourceUnavailable(); task.sourceReady(); task.pickerOpened(); task.cancel()
        XCTAssertEqual(sent.last?["source_lookup"], .bool(false))
        XCTAssertEqual(steps(), ["open_picker", "cancel"])
    }
    func testSourceJourneyCannotTransferToAnUnrelatedGrant() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let same = AnalyticsForwardPickerJourney(context: origin, entry: .messageSelection, sourceLookup: true)
        same.sourceReady(); same.restrict(to: origin); same.pickerOpened(); same.cancel()
        XCTAssertEqual(sent.count, 1)
        let unrelated = AnalyticsForwardPickerJourney(context: origin, entry: .messageSelection, sourceLookup: true)
        unrelated.sourceReady(); unrelated.restrict(to: analytics.captureContext(owner: owner, privacy: .ordinary))
        unrelated.pickerOpened(); unrelated.cancel()
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(unrelated.retainedStateCount, 0)
        let foreignAnalytics = Analytics(), foreignOwner = NSObject()
        foreignAnalytics.setSink({ _, _ in }, owner: foreignOwner); foreignAnalytics.isEnabled = true
        let foreign = foreignAnalytics.captureContext(owner: foreignOwner, privacy: .ordinary)
        let task = AnalyticsForwardPickerJourney(context: origin, entry: .messageSelection, sourceLookup: true)
        task.restrict(to: foreign); task.sourceReady(); task.pickerOpened(); task.cancel()
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(task.retainedStateCount, 0)
    }
    func testActivationBelongsToTheAdmittedSubmission() {
        let analytics = hub()
        for activation: AnalyticsForwardPickerJourney.Spec.Activation in [.rowAction, .returnKey, .numberShortcut, .savedMessagesShortcut, .sendButton, .sendMenu] {
            let task = journey(analytics); task.pickerOpened()
            let ended = task.beginSubmission(topic: false, activation: activation)
            let duplicateEnded = task.beginSubmission(topic: true, activation: .rowAction)
            duplicateEnded(); task.complete(.accepted); ended()
            XCTAssertEqual(sent.last?["activation"], .string(activation.rawValue))
            XCTAssertEqual(sent.last?["destination"], .string("chat"))
        }
        XCTAssertEqual(sent.count, 6)
    }
    func testRetryReplacesActivationAndUnknownNeverInheritsIt() {
        let analytics = hub()
        for activation: AnalyticsForwardPickerJourney.Spec.Activation? in [.rowAction, nil] {
            let task = journey(analytics); task.pickerOpened()
            let firstEnded = task.beginSubmission(topic: false, activation: .returnKey)
            task.blocked(.pollRestriction)
            let retryEnded = task.beginSubmission(topic: true, activation: activation)
            firstEnded(); task.complete(.destinationReady); retryEnded()
            XCTAssertEqual(sent.last?["activation"], activation.map { .string($0.rawValue) })
            XCTAssertEqual(sent.last?["retry_count"], .string("1"))
        }
    }
    func testActivationDoesNotCollectInPrivateMissingOrRevokedScopes() {
        let analytics = hub()
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let task = AnalyticsForwardPickerJourney(context: context, entry: .messageMenu)
            task.pickerOpened(); let ended = task.beginSubmission(topic: false, activation: .savedMessagesShortcut)
            task.complete(.accepted); ended()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertEqual(reads, 0)
        let task = journey(analytics); task.pickerOpened()
        onClock = { self.onClock = nil; analytics.isEnabled = false; analytics.isEnabled = true }
        let ended = task.beginSubmission(topic: false, activation: .sendButton)
        task.complete(.accepted); ended()
        XCTAssertTrue(sent.isEmpty); XCTAssertEqual(task.retainedStateCount, 0)
    }
    func testSearchAndDestinationBrowsingPreserveTheChosenRoute() {
        let analytics = hub()
        let task = journey(analytics, entry: .messageSelection)
        task.searchUsed(); task.navigated(.forum)
        task.pickerOpened(); task.searchUsed(); task.searchUsed()
        task.navigated(.community); task.navigated(.forum); task.navigated(.back)
        task.searchUsed(); task.submitted(topic: true)
        task.searchUsed(); task.navigated(.back); task.complete(.destinationReady)
        XCTAssertEqual(steps(), ["open_picker", "search", "open_community", "open_forum", "back", "choose_topic", "destination_ready"])
        XCTAssertEqual(sent.last?["entry_point"], .string("message_selection"))
        XCTAssertEqual(sent.last?["search_used"], .bool(true))
        XCTAssertEqual(task.retainedStateCount, 0)
    }
    func testSearchIsOncePerJourneyAcrossBlockersAndCancellation() {
        let analytics = hub()
        let task = journey(analytics); task.pickerOpened(); task.searchUsed()
        task.blocked(.premiumRequired); task.searchUsed(); task.submitted(topic: false)
        task.blocked(.pollRestriction); task.searchUsed(); task.navigated(.back); task.cancel()
        XCTAssertEqual(steps().filter { $0 == "search" }.count, 1)
        XCTAssertEqual(sent.last?["outcome"], .string("cancelled"))
        XCTAssertNil(sent.last?["query"]); XCTAssertNil(sent.last?["result"])
    }
    func testPrivateOrRevokedSearchAndNavigationDoNotReadClockOrRetainState() {
        let analytics = hub()
        var queryReads = 0
        func hasQuery() -> Bool { queryReads += 1; return true }
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let task = AnalyticsForwardPickerJourney(context: context, entry: .rowAction)
            task.pickerOpened(); task.searchUsed(if: hasQuery()); task.navigated(.community); task.navigated(.forum); task.navigated(.back); task.cancel()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertEqual(reads, 0); XCTAssertEqual(queryReads, 0)
        let task = journey(analytics); task.pickerOpened(); task.searchUsed()
        analytics.isEnabled = false; analytics.isEnabled = true
        let previousReads = reads
        task.searchUsed(if: hasQuery()); task.navigated(.forum); task.cancel()
        XCTAssertEqual(queryReads, 0)
        XCTAssertEqual(reads, previousReads); XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertTrue(sent.isEmpty)
    }
    func testNavigationAndSearchStateRemainBounded() {
        let analytics = hub()
        let task = journey(analytics); task.pickerOpened()
        for _ in 0..<1000 { task.navigated(.forum); task.navigated(.back) }
        task.searchUsed()
        XCTAssertLessThan(task.retainedStateCount, 100)
        task.cancel(); XCTAssertEqual(task.retainedStateCount, 0)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["search_used"], .bool(true))
    }
    func testPreviousSubmissionDisposalDoesNotEraseRetry() {
        let analytics = hub()
        let task = journey(analytics); task.pickerOpened()
        let firstEnded = task.beginSubmission(topic: false)
        task.blocked(.pollRestriction); task.operationFailed()
        let retryEnded = task.beginSubmission(topic: true)
        firstEnded(); firstEnded()
        task.complete(.destinationReady); retryEnded()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["retry_count"], .string("1"))
        XCTAssertEqual(sent.last?["last_blocker"], .string("poll_restriction"))
        XCTAssertEqual(steps(), ["open_picker", "choose_chat", "blocked", "retry", "choose_topic", "destination_ready"])
        XCTAssertEqual(task.retainedStateCount, 0)
    }
    func testCurrentSubmissionDisposalStillDiscardsWithoutInventingOutcome() {
        let analytics = hub()
        let task = journey(analytics); task.pickerOpened()
        let ended = task.beginSubmission(topic: false)
        ended(); ended(); task.cancel(); task.complete(.accepted)
        XCTAssertTrue(sent.isEmpty); XCTAssertEqual(task.retainedStateCount, 0)
    }
    func testUnadmittedSubmissionCleanupCannotDiscardExistingAttempt() {
        let analytics = hub()
        let task = journey(analytics); task.pickerOpened()
        let ended = task.beginSubmission(topic: false)
        let unadmittedEnded = task.beginSubmission(topic: true)
        unadmittedEnded(); task.complete(.accepted); ended()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.last?["destination"], .string("chat"))
        XCTAssertEqual(sent.last?["retry_count"], .string("0"))
    }
    func testSubmissionCleanupIsInertForPrivateRevokedAndReleasedOwners() {
        let analytics = hub()
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let task = AnalyticsForwardPickerJourney(context: context, entry: .messageMenu)
            task.pickerOpened(); let ended = task.beginSubmission(topic: false); ended()
            XCTAssertEqual(task.retainedStateCount, 0)
        }
        XCTAssertEqual(reads, 0)
        var task: AnalyticsForwardPickerJourney? = journey(analytics)
        weak var weakTask = task
        task?.pickerOpened(); let ended = task?.beginSubmission(topic: true)
        analytics.isEnabled = false; analytics.isEnabled = true
        ended?(); XCTAssertEqual(task?.retainedStateCount, 0)
        task = nil; XCTAssertNil(weakTask); ended?()
        XCTAssertTrue(sent.isEmpty)
    }
}
