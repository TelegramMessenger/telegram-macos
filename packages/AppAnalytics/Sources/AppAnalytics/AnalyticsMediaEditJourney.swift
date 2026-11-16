import Foundation

public final class AnalyticsMediaEditJourney: AnalyticsRevocable {
    public typealias Spec = AnalyticsFlows.ChatMediaEdit

    public enum Result {
        case applied
        case failed(Spec.LastBlocker)
    }

    private enum Stage {
        case editing
        case submitting
    }

    private let scope: AnalyticsScope?
    private var flow: AnalyticsFlow<Spec>?
    private var stage: Stage?
    private var generation = 0
    private var pendingReplacement: Int?
    private var pendingMode: Spec.MediaMode?
    private var pendingEntry: Spec.EntryPoint?
    private var replacementCount = 0
    private var attempt = 0
    private var retryPending = false
    private var retryCount = 0
    private var allowsRetry = false
    private var editingActive = true

    public init(context: AnalyticsContext, entry: Spec.EntryPoint, mode: Spec.MediaMode, source: AnalyticsScreen? = nil) {
        scope = source?.isAnalyticsExcluded == true ? nil : context.scope
        scope?.perform {
            guard let analytics = context.analytics, !context.isExcluded else { return }
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: source)
            flow.set(entryPoint: entry)
            flow.set(mediaMode: mode)
            flow.set(replacementCount: ._0)
            flow.set(retryCount: ._0)
            self.flow = flow
            stage = .editing
            scope?.observe(self)
        }
    }

    public func beginReplacement(entry: Spec.EntryPoint, mode: Spec.MediaMode) -> Int? {
        return scope?.perform { () -> Int? in
            if stage == .submitting, allowsRetry, editingActive {
                stage = .editing
                retryPending = true
                flow?.step(.supersedeSubmission)
            }
            guard stage == .editing else { return nil }
            guard generation < 256 else {
                discard()
                return nil
            }
            if pendingReplacement != nil {
                flow?.step(.supersedeReplacement)
            }
            generation += 1
            pendingReplacement = generation
            pendingMode = mode
            pendingEntry = entry
            recordEntry(entry)
            return generation
        } ?? nil
    }

    public func rejectedReplacement(entry: Spec.EntryPoint, reason: Spec.LastBlocker) {
        scope?.perform {
            guard stage == .editing else { return }
            guard generation < 256 else { discard(); return }
            generation += 1
            recordEntry(entry)
            blocked(reason)
        }
    }

    public func failedReplacement(_ token: Int, reason: Spec.LastBlocker) {
        scope?.perform {
            guard stage == .editing, pendingReplacement == token else { return }
            pendingReplacement = nil
            pendingMode = nil
            pendingEntry = nil
            blocked(reason)
        }
    }

    private func recordEntry(_ entry: Spec.EntryPoint) {
        switch entry {
        case .clipboard: flow?.step(.paste)
        case .dropTarget: flow?.step(.drop)
        case .replacementPicker: flow?.step(.openPicker)
        case .attachment: flow?.step(.attach)
        case .photoEditor: flow?.step(.openEditor)
        }
    }

    public func appliedReplacement(_ token: Int) {
        scope?.perform {
            guard stage == .editing, pendingReplacement == token else { return }
            pendingReplacement = nil
            if let pendingMode { flow?.set(mediaMode: pendingMode) }
            pendingMode = nil
            pendingEntry = nil
            replacementCount += 1
            flow?.set(replacementCount: Self.bucket(replacementCount))
            flow?.step(.applyReplacement)
        }
    }

    public func cancelledSelection(_ token: Int) {
        scope?.perform {
            guard stage == .editing, pendingReplacement == token else { return }
            pendingReplacement = nil
            pendingMode = nil
            flow?.step(pendingEntry == .photoEditor ? .cancelEditor : .cancelSelection)
            pendingEntry = nil
        }
    }

    public func blocked(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard stage == .editing else { return }
            retryPending = true
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
        }
    }

    public func beginSubmission(scheduled: Bool) -> AnalyticsMediaEditSubmission? {
        return beginSubmission(scheduled: scheduled, allowsRetry: scheduled)
    }

    public func beginSubmission(scheduled: Bool, allowsRetry: Bool) -> AnalyticsMediaEditSubmission? {
        return scope?.perform { () -> AnalyticsMediaEditSubmission? in
            guard stage == .editing else { return nil }
            guard pendingReplacement == nil, replacementCount > 0, attempt < 256 else {
                discard()
                return nil
            }
            stage = .submitting
            attempt += 1
            self.allowsRetry = allowsRetry
            if retryPending {
                retryPending = false
                retryCount += 1
                flow?.set(retryCount: Self.retryBucket(retryCount))
                flow?.step(.retry)
            }
            flow?.set(scheduled: scheduled)
            flow?.step(.submit)
            return AnalyticsMediaEditSubmission(journey: self, attempt: attempt)
        } ?? nil
    }

    public func endEditing() {
        scope?.policy.sync {
            editingActive = false
            if stage != .submitting { discard() }
        }
    }

    public func cancelSubmission() {
        scope?.perform {
            guard stage == .submitting, allowsRetry, editingActive else { return }
            stage = .editing
            retryPending = true
            flow?.step(.cancelSubmission)
        }
    }

    public func cancel() {
        scope?.perform {
            guard stage == .editing else { return }
            flow?.step(.cancel)
            finish(.cancelled)
        }
    }

    public func discard() {
        scope?.policy.sync {
            revokeAnalytics()
            scope?.removeObserver(self)
        }
    }

    fileprivate func complete(attempt: Int, buildResult: () -> Result?) {
        scope?.perform {
            guard stage == .submitting, self.attempt == attempt else { return }
            let result = buildResult()
            guard stage == .submitting, self.attempt == attempt, scope?.isValid == true else { return }
            switch result {
            case .applied?:
                flow?.step(.applied)
                finish(.success)
            case let .failed(reason)?:
                flow?.set(lastBlocker: reason)
                flow?.step(.rejected)
                if allowsRetry && editingActive {
                    stage = .editing
                    retryPending = true
                } else {
                    finish(.fail)
                }
            case nil:
                discard()
            }
        }
    }

    fileprivate func end(attempt: Int) {
        scope?.policy.sync {
            guard stage == .submitting, self.attempt == attempt else { return }
            discard()
        }
    }

    private func finish(_ outcome: AnalyticsFlowOutcome) {
        let flow = self.flow
        self.flow = nil
        revokeAnalytics()
        scope?.removeObserver(self)
        flow?.finish(outcome)
    }

    func revokeAnalytics() {
        flow?.discard()
        flow = nil
        stage = nil
        generation = 0
        pendingReplacement = nil
        pendingMode = nil
        pendingEntry = nil
        replacementCount = 0
        attempt = 0
        retryPending = false
        retryCount = 0
        allowsRetry = false
        editingActive = false
    }

    private static func bucket(_ count: Int) -> Spec.ReplacementCount {
        switch count {
        case 0: return ._0
        case 1: return ._1
        case 2...3: return ._2_3
        default: return ._4_plus
        }
    }

    private static func retryBucket(_ count: Int) -> Spec.RetryCount {
        switch count {
        case 0: return ._0
        case 1: return ._1
        case 2...3: return ._2_3
        default: return ._4_plus
        }
    }

    deinit {
        discard()
    }
}

public final class AnalyticsMediaEditSubmission {
    private let journey: AnalyticsMediaEditJourney
    private let attempt: Int

    fileprivate init(journey: AnalyticsMediaEditJourney, attempt: Int) {
        self.journey = journey
        self.attempt = attempt
    }

    public func complete(buildResult: () -> AnalyticsMediaEditJourney.Result?) {
        journey.complete(attempt: attempt, buildResult: buildResult)
    }

    public func discard() {
        journey.end(attempt: attempt)
    }

    deinit {
        journey.end(attempt: attempt)
    }
}
