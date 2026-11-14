import Foundation
import SwiftSignalKit

public enum AnalyticsRecordingEnqueueResult {
    case accepted
    case partiallyAccepted
    case rejected
}

public final class AnalyticsRecordingJourney: AnalyticsRevocable {
    public typealias Spec = AnalyticsFlows.ChatRecording

    private enum Stage {
        case attempt
        case recording
        case paused
        case transcribing
        case preparingMedia
        case preparingText
        case submittingMedia
        case submittingText
    }

    private let scope: AnalyticsScope?
    private var flow: AnalyticsFlow<Spec>?
    private var stage: Stage?
    private var kind: Spec.RecordingKind?
    private var locked = false
    private var reviewed = false
    private var pendingTrimChange = false
    private var oneTime = false

    public init(context: AnalyticsContext, kind: Spec.RecordingKind, surface: Spec.Surface, initialMode: Spec.InitialMode, via: AnalyticsValues.Via? = nil, source: AnalyticsScreen? = nil) {
        self.scope = source?.isAnalyticsExcluded == true ? nil : context.scope
        scope?.perform {
            guard let analytics = context.analytics, !context.isExcluded else { return }
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: source)
            flow.set(recordingKind: kind)
            flow.set(surface: surface)
            flow.set(initialMode: initialMode)
            flow.set(via: via)
            flow.step(.attempt)
            guard scope?.isValid == true else { return }
            self.flow = flow
            self.kind = kind
            self.locked = initialMode == .locked
            self.stage = .attempt
            scope?.observe(self)
        }
    }

    fileprivate func restrict(to context: AnalyticsContext) {
        scope?.policy.sync {
            if context.isExcluded || context.scope !== scope { discard() }
        }
    }

    public func permissionResolved(granted: Bool) {
        scope?.perform {
            guard stage == .attempt || stage == .transcribing else { return }
            flow?.step(granted ? .permissionGranted : .permissionDenied)
        }
    }

    public func started() {
        scope?.perform {
            guard stage == .attempt else { return }
            stage = .recording
            flow?.step(.start)
        }
    }

    public func lock() {
        scope?.perform {
            guard stage == .recording, !locked else { return }
            locked = true
            flow?.step(.lock)
        }
    }

    public func paused() {
        scope?.perform {
            guard stage == .recording else { return }
            stage = .paused
            reviewed = false
            pendingTrimChange = false
            flow?.step(.pause)
        }
    }

    public func previewReady() {
        scope?.perform {
            guard stage == .paused, !reviewed else { return }
            reviewed = true
            flow?.step(.review)
        }
    }

    public func trimChanged(changed: @autoclosure () -> Bool, committed: Bool) {
        scope?.perform {
            guard stage == .paused, reviewed else { return }
            let changed = pendingTrimChange || changed()
            guard stage == .paused, reviewed, scope?.isValid == true else { return }
            pendingTrimChange = changed
            if committed {
                if pendingTrimChange { trimApplied() }
                pendingTrimChange = false
            }
        }
    }

    public func trimApplied() {
        scope?.perform {
            guard stage == .paused, reviewed else { return }
            flow?.step(.trim)
        }
    }

    public func resumed() {
        scope?.perform {
            guard stage == .paused else { return }
            stage = .recording
            reviewed = false
            pendingTrimChange = false
            flow?.step(.resume)
        }
    }

    public func setOneTime(_ value: Bool) {
        scope?.perform {
            guard stage == .recording || stage == .paused, oneTime != value else { return }
            oneTime = value
            flow?.set(oneTime: value)
            flow?.step(value ? .oneTimeOn : .oneTimeOff)
        }
    }

    public func beginTranscription() {
        scope?.perform {
            guard kind == .voice, stage == .recording || stage == .paused else { return }
            stage = .transcribing
            reviewed = false
            pendingTrimChange = false
            oneTime = false
            flow?.set(oneTime: nil)
            flow?.step(.transcribe)
        }
    }

    public func draftInserted() {
        scope?.perform {
            guard stage == .transcribing else { return }
            flow?.set(result: .draftInserted)
            flow?.step(.draftInserted)
            finish(.success)
        }
    }

    public func step(_ step: Spec.Step) {
        scope?.perform {
            guard isInteractive else { return }
            switch step {
            case .openConfirmation, .cancelConfirmation:
                flow?.step(step)
            case .openSchedule, .cancelSchedule:
                guard stage != .attempt else { return }
                flow?.step(step)
            default:
                break
            }
        }
    }

    public func blocked(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard isInteractive else { return }
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
        }
    }

    public func fail(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard isInteractive || isPreparing else { return }
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
            finish(.fail)
        }
    }

    public func cancel() {
        scope?.perform {
            guard isInteractive else { return }
            flow?.step(.cancel)
            finish(.cancelled)
        }
    }

    public func prepareSubmission(via: Spec.SubmitVia) -> AnalyticsRecordingRequest? {
        return prepareSubmission(via: via, recordPreparation: true)
    }

    private func prepareSubmission(via: Spec.SubmitVia, recordPreparation: Bool) -> AnalyticsRecordingRequest? {
        return scope?.perform {
            guard stage == .recording || stage == .paused || stage == .transcribing else { return nil }
            if via == .durationLimit, kind != .video || stage != .recording {
                return nil
            }
            let isText = stage == .transcribing
            stage = isText ? .preparingText : .preparingMedia
            pendingTrimChange = false
            flow?.set(submitVia: via)
            flow?.set(oneTime: isText ? nil : oneTime)
            if recordPreparation { flow?.step(.prepareSubmission) }
            return AnalyticsRecordingRequest(journey: self)
        } ?? nil
    }

    public func beginSubmission(via: Spec.SubmitVia, scheduled: Bool) -> AnalyticsRecordingSubmission? {
        return prepareSubmission(via: via, recordPreparation: false)?.commit(scheduled: scheduled)
    }

    fileprivate func commit(scheduled: Bool) -> AnalyticsRecordingSubmission? {
        return scope?.perform {
            guard isPreparing else { return nil }
            stage = stage == .preparingText ? .submittingText : .submittingMedia
            flow?.set(scheduled: scheduled)
            flow?.step(.submit)
            return AnalyticsRecordingSubmission(journey: self)
        } ?? nil
    }

    fileprivate func preparationStep(_ step: Spec.Step) {
        scope?.perform {
            guard isPreparing else { return }
            switch step {
            case .openSchedule, .cancelSchedule, .openConfirmation, .cancelConfirmation:
                flow?.step(step)
            default:
                break
            }
        }
    }

    fileprivate func cancelPreparation() {
        scope?.perform {
            guard isPreparing else { return }
            flow?.step(.cancel)
            finish(.cancelled)
        }
    }

    fileprivate func failPreparation(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard isPreparing else { return }
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
            finish(.fail)
        }
    }

    fileprivate func endPreparation() {
        scope?.policy.sync {
            guard isPreparing else { return }
            discard()
        }
    }

    private var isPreparing: Bool {
        return stage == .preparingMedia || stage == .preparingText
    }

    fileprivate func resolve(_ buildResult: () -> AnalyticsRecordingEnqueueResult?) {
        scope?.perform {
            guard stage == .submittingMedia || stage == .submittingText else { return }
            let submittingStage = stage
            let result = buildResult()
            guard stage == submittingStage, scope?.isValid == true else { return }
            guard let result else {
                discard()
                return
            }
            switch result {
            case .accepted:
                flow?.set(result: stage == .submittingText ? .textAccepted : .mediaAccepted)
                flow?.step(.accepted)
                finish(.success)
            case .partiallyAccepted:
                guard stage == .submittingText else {
                    discard()
                    return
                }
                flow?.set(result: .textPartiallyAccepted)
                flow?.set(lastBlocker: .enqueueRejected)
                flow?.step(.partiallyAccepted)
                finish(.fail)
            case .rejected:
                flow?.set(result: .rejected)
                flow?.set(lastBlocker: .enqueueRejected)
                flow?.step(.rejected)
                finish(.fail)
            }
        }
    }

    private var isInteractive: Bool {
        return stage != nil && !isPreparing && stage != .submittingMedia && stage != .submittingText
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
        kind = nil
        locked = false
        reviewed = false
        pendingTrimChange = false
        oneTime = false
    }

    var retainedStateCount: Int {
        return scope?.policy.sync { () -> Int in
            var count: Int = flow?.storedStepCount ?? 0
            if stage != nil {
                count += 1
            }
            if kind != nil {
                count += 1
            }
            if locked {
                count += 1
            }
            if reviewed {
                count += 1
            }
            if pendingTrimChange {
                count += 1
            }
            if oneTime {
                count += 1
            }
            return count
        } ?? 0
    }

    deinit {
        discard()
    }
}

public final class AnalyticsRecordingSubmission {
    private let journey: AnalyticsRecordingJourney

    fileprivate init(journey: AnalyticsRecordingJourney) {
        self.journey = journey
    }

    public func complete(buildResult: () -> Bool?) {
        journey.resolve { buildResult().map { $0 ? .accepted : .rejected } }
    }

    public func completeEnqueue(buildResult: () -> AnalyticsRecordingEnqueueResult?) {
        journey.resolve(buildResult)
    }

    public func end() {
        journey.discard()
    }

    deinit {
        end()
    }
}


public final class AnalyticsRecordingRequest {
    private let journey: AnalyticsRecordingJourney

    fileprivate init(journey: AnalyticsRecordingJourney) {
        self.journey = journey
    }

    public func restrict(to context: AnalyticsContext) {
        journey.restrict(to: context)
    }

    public func observingPreparation<Value, Failure>(_ signal: Signal<Value, Failure>) -> Signal<Value, Failure> {
        return Signal { subscriber in
            let delivered = Atomic(value: false)
            let disposable = signal.start(next: { value in
                _ = delivered.swap(true)
                subscriber.putNext(value)
            }, error: { error in
                subscriber.putError(error)
            }, completed: {
                subscriber.putCompletion()
            })
            return ActionDisposable {
                disposable.dispose()
                if !delivered.with({ $0 }) { self.end() }
            }
        }
    }

    public func commit(scheduled: Bool) -> AnalyticsRecordingSubmission? {
        return journey.commit(scheduled: scheduled)
    }

    public func step(_ step: AnalyticsRecordingJourney.Spec.Step) {
        journey.preparationStep(step)
    }

    public func cancel() {
        journey.cancelPreparation()
    }

    public func fail(_ reason: AnalyticsRecordingJourney.Spec.LastBlocker) {
        journey.failPreparation(reason)
    }

    public func end() {
        journey.endPreparation()
    }

    deinit {
        end()
    }
}
