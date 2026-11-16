import Foundation

public final class AnalyticsForwardPickerJourney: AnalyticsRevocable {
    public typealias Spec = AnalyticsFlows.ChatForwardPicker
    public enum Navigation { case forum, community, back }
    private enum Stage { case loading, ready, picker, submitting }
    private let scope: AnalyticsScope?
    private var flow: AnalyticsFlow<Spec>?
    private var stage: Stage?
    private var retryPending = false
    private var retryCount = 0
    private var submission: UUID?
    private var searched = false

    public convenience init(context: AnalyticsContext, entry: Spec.EntryPoint) {
        self.init(context: context, entry: entry, sourceLookup: false)
    }

    public init(context: AnalyticsContext, entry: Spec.EntryPoint, sourceLookup: Bool) {
        scope = context.isExcluded ? nil : context.scope
        scope?.perform {
            guard let analytics = context.analytics else { return }
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope)
            flow.set(entryPoint: entry)
            flow.set(retryCount: ._0)
            flow.set(searchUsed: false)
            flow.set(sourceLookup: sourceLookup)
            guard scope?.isValid == true else { return }
            self.flow = flow
            stage = sourceLookup ? .loading : .ready
            scope?.observe(self)
            if sourceLookup { flow.step(.lookupSource) }
        }
    }

    public func sourceReady() {
        resolveSource { nil }
    }

    public func sourceReady(coverage: @autoclosure () -> Spec.SourceCoverage) {
        resolveSource { coverage() }
    }

    private func resolveSource(_ coverage: () -> Spec.SourceCoverage?) {
        scope?.perform {
            guard stage == .loading else { return }
            let value = coverage()
            guard stage == .loading, scope?.isValid == true else { return }
            stage = .ready
            flow?.set(sourceCoverage: value)
            flow?.step(.sourceReady)
        }
    }

    public func restrict(to context: AnalyticsContext) {
        scope?.policy.sync {
            if context.isExcluded || context.scope !== scope { discard() }
        }
    }

    public func sourceUnavailable() {
        scope?.perform {
            guard stage == .loading else { return }
            flow?.set(result: .sourceUnavailable)
            flow?.step(.sourceUnavailable)
            finish(.fail)
        }
    }

    public func pickerOpened() {
        scope?.perform {
            guard stage == .ready else { return }
            stage = .picker
            flow?.step(.openPicker)
        }
    }

    public func submitted(topic: Bool) {
        _ = beginSubmission(topic: topic)
    }

    public func searchUsed() {
        searchUsed(if: true)
    }

    public func searchUsed(if hasQuery: @autoclosure () -> Bool) {
        scope?.perform {
            guard stage == .picker, !searched, hasQuery() else { return }
            searched = true
            flow?.set(searchUsed: true)
            flow?.step(.search)
        }
    }

    public func navigated(_ navigation: Navigation) {
        scope?.perform {
            guard stage == .picker else { return }
            switch navigation {
            case .forum: flow?.step(.openForum)
            case .community: flow?.step(.openCommunity)
            case .back: flow?.step(.back)
            }
        }
    }

    public func beginSubmission(topic: Bool) -> () -> Void {
        beginSubmission(topic: topic, activation: nil)
    }

    public func beginSubmission(topic: Bool, activation: Spec.Activation?) -> () -> Void {
        var submission: UUID?
        scope?.perform {
            guard stage == .picker else { return }
            if retryPending {
                retryPending = false
                retryCount = min(retryCount + 1, 4)
                flow?.set(retryCount: retryCount == 1 ? ._1 : retryCount < 4 ? ._2_3 : ._4_plus)
                flow?.step(.retry)
            }
            guard stage == .picker, scope?.isValid == true else { return }
            stage = .submitting
            let identity = UUID()
            self.submission = identity
            submission = identity
            flow?.set(destination: topic ? .topic : .chat)
            flow?.set(activation: activation)
            flow?.step(topic ? .chooseTopic : .chooseChat)
        }
        return { [weak self] in
            guard let self, let submission else { return }
            self.scope?.policy.sync {
                guard self.submission == submission, self.stage == .submitting else { return }
                self.discard()
            }
        }
    }

    public func blocked(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard stage == .picker || stage == .submitting else { return }
            stage = .picker
            submission = nil
            retryPending = true
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
        }
    }

    public func operationFailed() {
        scope?.perform {
            if stage == .submitting { blocked(.operationFailed) }
        }
    }

    public func complete(_ result: Spec.Result) {
        scope?.perform {
            guard stage == .submitting else { return }
            flow?.set(result: result)
            switch result {
            case .draftPrepared: flow?.step(.draftPrepared)
            case .destinationReady: flow?.step(.destinationReady)
            case .accepted: flow?.step(.accepted)
            case .partiallyAccepted: flow?.step(.partiallyAccepted)
            case .rejected: flow?.step(.rejected)
            case .acceptanceUnknown: flow?.step(.acceptanceUnknown)
            case .sourceUnavailable: flow?.step(.sourceUnavailable)
            case .targetUnavailable: flow?.step(.targetUnavailable)
            }
            finish(result == .draftPrepared || result == .destinationReady || result == .accepted ? .success : .fail)
        }
    }

    public func cancel() {
        scope?.perform {
            guard stage == .picker || stage == .submitting else { return }
            flow?.step(.cancel)
            finish(.cancelled)
        }
    }

    public func submissionEnded() {
        scope?.policy.sync { if stage == .submitting { discard() } }
    }

    private func finish(_ outcome: AnalyticsFlowOutcome) {
        let flow = self.flow
        self.flow = nil
        revokeAnalytics()
        scope?.removeObserver(self)
        flow?.finish(outcome)
    }

    public func discard() {
        scope?.policy.sync {
            revokeAnalytics()
            scope?.removeObserver(self)
        }
    }

    func revokeAnalytics() {
        flow?.discard()
        flow = nil
        stage = nil
        retryPending = false
        retryCount = 0
        submission = nil
        searched = false
    }

    var retainedStateCount: Int {
        return scope?.policy.sync { () -> Int in
            var count: Int = flow?.storedStepCount ?? 0
            if stage != nil {
                count += 1
            }
            if retryPending {
                count += 1
            }
            if retryCount != 0 {
                count += 1
            }
            if submission != nil {
                count += 1
            }
            if searched {
                count += 1
            }
            return count
        } ?? 0
    }

    deinit { discard() }
}
