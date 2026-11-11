import Foundation

private final class WeakAnalyticsMediaSubmissionGroup {
    weak var value: AnalyticsMediaSubmissionGroup?

    init(_ value: AnalyticsMediaSubmissionGroup) {
        self.value = value
    }
}

public final class AnalyticsMediaJourney: AnalyticsRevocable {
    public typealias Spec = AnalyticsFlows.ChatMediaCompose

    private enum Stage {
        case acquiring
        case preparing
        case ready
        case submitting
    }

    private enum PartResult {
        case result(Spec.SubmissionResult)
        case skipped
    }

    private let scope: AnalyticsScope?
    private let context: AnalyticsContext
    private var flow: AnalyticsFlow<Spec>?
    private var stage: Stage?
    private var hasAttachments = false
    private var retryCount = 0
    private var submissionWasBlocked = false
    private var expectedParts = 0
    private var partResults: [Int: PartResult] = [:]
    private var groups: [Int: WeakAnalyticsMediaSubmissionGroup] = [:]

    public init(context: AnalyticsContext, entry: Spec.EntryPoint, mode: Spec.MediaMode, via: AnalyticsValues.Via? = nil, source: AnalyticsScreen? = nil) {
        self.context = context
        self.scope = source?.isAnalyticsExcluded == true ? nil : context.scope
        scope?.perform {
            guard let analytics = context.analytics, !context.isExcluded else { return }
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: source)
            flow.set(entryPoint: entry)
            flow.set(mediaMode: mode)
            flow.set(via: via)
            flow.set(attachmentCount: ._0)
            flow.set(retryCount: ._0)
            flow.step(.acquire)
            self.flow = flow
            stage = .acquiring
            scope?.observe(self)
        }
    }

    public func restrict(to context: AnalyticsContext) {
        scope?.policy.sync {
            if context.isExcluded || context.scope !== scope { discard() }
        }
    }

    public func selected(count: Int, mode: Spec.MediaMode) {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            guard count >= 0 else {
                discard()
                return
            }
            hasAttachments = count > 0
            flow?.set(attachmentCount: Self.bucket(count))
            flow?.set(mediaMode: mode)
            if count > 0 {
                flow?.step(.acquired)
                self.stage = .ready
            }
        }
    }

    public func preparing() {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            self.stage = .preparing
            flow?.step(.prepare)
        }
    }

    public func previewShown() {
        scope?.perform {
            guard let stage = stage, stage != .submitting, hasAttachments else { return }
            self.stage = .ready
            flow?.step(.preview)
        }
    }

    public func step(_ step: Spec.Step) {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            switch step {
            case .addPaste, .addDrop, .addPicker, .addPasteUnchanged, .addDropUnchanged, .removeMedia, .reorderMedia,
                 .openCoverPicker, .cancelCoverPicker, .applyCover, .removeCover,
                 .openPrice, .applyPrice, .cancelPrice, .removePrice,
                 .openEffectPremium,
                 .openEditor, .applyEditor, .cancelEditor, .selectGrouped, .selectUngrouped,
                 .toggleSpoiler, .openSchedule, .cancelSchedule, .openConfirmation, .cancelConfirmation:
                flow?.step(step)
            case .selectMedia:
                flow?.set(mediaMode: .media)
                flow?.step(step)
            case .selectFile:
                flow?.set(mediaMode: .file)
                flow?.step(step)
            case .selectArchive:
                flow?.set(mediaMode: .archive)
                flow?.step(step)
            default:
                break
            }
        }
    }

    public func blocked(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
        }
    }

    public func retry() {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            submissionWasBlocked = false
            retryCount = min(retryCount + 1, 4)
            let bucket: Spec.RetryCount = retryCount == 1 ? ._1 : retryCount < 4 ? ._2_3 : ._4_plus
            flow?.set(retryCount: bucket)
            flow?.step(.retry)
        }
    }

    public func submissionBlocked(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            submissionWasBlocked = true
            blocked(reason)
        }
    }

    public func retrySubmissionIfBlocked() {
        scope?.perform {
            guard submissionWasBlocked else { return }
            retry()
        }
    }

    public func beginSubmission(parts: Int, via: Spec.SubmitVia, scheduled: Bool, silent: Bool) -> AnalyticsMediaSubmission? {
        return scope?.perform { () -> AnalyticsMediaSubmission? in
            guard stage == .ready, hasAttachments else { return nil }
            guard (1...256).contains(parts) else {
                discard()
                return nil
            }
            expectedParts = parts
            submissionWasBlocked = false
            stage = .submitting
            flow?.set(submitVia: via)
            flow?.set(scheduled: scheduled)
            flow?.set(silent: silent)
            flow?.step(.submit)
            return AnalyticsMediaSubmission(journey: self)
        } ?? nil
    }

    public func cancel() {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            flow?.step(.cancel)
            finish(.cancelled)
        }
    }

    public func close() {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            flow?.step(.close)
            finish(.abandoned)
        }
    }

    public func fail(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard let stage = stage, stage != .submitting else { return }
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
            finish(.fail)
        }
    }

    fileprivate var submissionContext: AnalyticsContext {
        return context.policy.sync {
            guard stage == .submitting, context.policy.accepts(scope) else {
                return context.analytics?.unresolvedContext() ?? Analytics.shared.unresolvedContext()
            }
            return context
        }
    }

    public func discard() {
        scope?.policy.sync {
            revokeAnalytics()
            scope?.removeObserver(self)
        }
    }

    fileprivate func complete(part: Int, result: Spec.SubmissionResult?) {
        resolve(part: part, result: result.map(PartResult.result))
    }

    fileprivate func complete(part: Int, buildResult: () -> Spec.SubmissionResult?) {
        scope?.perform {
            guard stage == .submitting, partResults[part] == nil else { return }
            guard (0..<expectedParts).contains(part) else {
                discard()
                return
            }
            complete(part: part, result: buildResult())
        }
    }

    fileprivate func skip(part: Int) {
        resolve(part: part, result: .skipped)
    }

    fileprivate func group(part: Int, count: Int) -> AnalyticsMediaSubmissionGroup? {
        return scope?.perform { () -> AnalyticsMediaSubmissionGroup? in
            guard stage == .submitting, (0..<expectedParts).contains(part), partResults[part] == nil, groups[part] == nil else { return nil }
            guard (0...2).contains(count) else {
                discard()
                return nil
            }
            if count == 0 {
                skip(part: part)
                return nil
            }
            let group = AnalyticsMediaSubmissionGroup(scope: scope, count: count, completion: { result in
                self.complete(part: part, result: result)
            })
            groups[part] = WeakAnalyticsMediaSubmissionGroup(group)
            return group
        } ?? nil
    }

    private func resolve(part: Int, result: PartResult?) {
        scope?.perform {
            guard stage == .submitting else { return }
            guard (0..<expectedParts).contains(part) else {
                discard()
                return
            }
            guard partResults[part] == nil else { return }
            guard let result = result else {
                discard()
                return
            }
            partResults[part] = result
            guard partResults.count == expectedParts else { return }
            let results: [Spec.SubmissionResult] = partResults.values.compactMap { part in
                if case let .result(result) = part { return result }
                return nil
            }
            guard !results.isEmpty else {
                discard()
                return
            }
            if results.allSatisfy({ $0 == .accepted }) {
                flow?.set(submissionResult: .accepted)
                flow?.step(.accepted)
                finish(.success)
            } else {
                let partial = results.contains { $0 != .rejected }
                flow?.set(submissionResult: partial ? .partiallyAccepted : .rejected)
                flow?.set(lastBlocker: .enqueueRejected)
                flow?.step(partial ? .partiallyAccepted : .rejected)
                finish(.fail)
            }
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
        hasAttachments = false
        retryCount = 0
        submissionWasBlocked = false
        expectedParts = 0
        partResults.removeAll()
        let groups = self.groups.values.compactMap { $0.value }
        self.groups.removeAll()
        for group in groups {
            group.revokeAnalytics()
        }
    }

    var retainedStateCount: Int {
        return scope?.policy.sync { () -> Int in
            var count: Int = flow?.storedStepCount ?? 0
            count += partResults.count
            count += retryCount
            count += expectedParts
            if stage != nil {
                count += 1
            }
            if submissionWasBlocked {
                count += 1
            }
            return count
        } ?? 0
    }

    private static func bucket(_ count: Int) -> Spec.AttachmentCount {
        switch count {
        case 0: return ._0
        case 1: return ._1
        case 2...5: return ._2_5
        case 6...20: return ._6_20
        case 21...100: return ._21_100
        default: return ._101_plus
        }
    }

    deinit {
        discard()
    }
}

public final class AnalyticsMediaSubmission {
    private let journey: AnalyticsMediaJourney
    public var context: AnalyticsContext { journey.submissionContext }

    fileprivate init(journey: AnalyticsMediaJourney) {
        self.journey = journey
    }

    public func restrict(to context: AnalyticsContext) {
        journey.restrict(to: context)
    }

    public func complete(part: Int, result: AnalyticsFlows.ChatMediaCompose.SubmissionResult?) {
        journey.complete(part: part, result: result)
    }

    public func complete(part: Int, buildResult: () -> AnalyticsFlows.ChatMediaCompose.SubmissionResult?) {
        journey.complete(part: part, buildResult: buildResult)
    }

    public func skip(part: Int) {
        journey.skip(part: part)
    }

    public func group(part: Int, count: Int) -> AnalyticsMediaSubmissionGroup? {
        return journey.group(part: part, count: count)
    }

    public func discard() {
        journey.discard()
    }
}

public final class AnalyticsMediaSubmissionGroup: AnalyticsRevocable {
    public typealias Result = AnalyticsFlows.ChatMediaCompose.SubmissionResult
    private let scope: AnalyticsScope?
    private var count: Int
    private var results: [Int: Result] = [:]
    private var completion: ((Result?) -> Void)?

    fileprivate init(scope: AnalyticsScope?, count: Int, completion: @escaping (Result?) -> Void) {
        self.scope = scope
        self.count = count
        self.completion = completion
        scope?.observe(self)
    }

    public func complete(index: Int, result: Result?) {
        scope?.perform {
            guard completion != nil else { return }
            guard (0..<count).contains(index) else {
                finish(nil)
                return
            }
            guard results[index] == nil else { return }
            guard let result = result else {
                finish(nil)
                return
            }
            results[index] = result
            guard results.count == count else { return }
            if results.values.allSatisfy({ $0 == .accepted }) {
                finish(.accepted)
            } else if results.values.contains(where: { $0 != .rejected }) {
                finish(.partiallyAccepted)
            } else {
                finish(.rejected)
            }
        }
    }

    public func complete(index: Int, buildResult: () -> Result?) {
        scope?.perform {
            guard completion != nil, results[index] == nil else { return }
            guard (0..<count).contains(index) else {
                finish(nil)
                return
            }
            complete(index: index, result: buildResult())
        }
    }

    public func end() {
        scope?.perform { finish(nil) }
    }

    private func finish(_ result: Result?) {
        let completion = self.completion
        revokeAnalytics()
        scope?.removeObserver(self)
        completion?(result)
    }

    func revokeAnalytics() {
        completion = nil
        count = 0
        results.removeAll()
    }

    var retainedStateCount: Int {
        return scope?.policy.sync { count + results.count + (completion == nil ? 0 : 1) } ?? 0
    }

    deinit {
        end()
    }
}
