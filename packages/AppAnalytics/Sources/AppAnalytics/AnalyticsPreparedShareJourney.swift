import Foundation

public final class AnalyticsPreparedShareJourney: AnalyticsRevocable {
    public typealias Spec = AnalyticsFlows.BotPreparedShare

    public enum PickerResult {
        case accepted
        case partiallyAccepted
        case rejected
        case unknown
        case cancelled
        case notAccepted
    }

    private enum Stage {
        case loading
        case prepared
        case preview
        case picker
    }

    private let scope: AnalyticsScope?
    private var flow: AnalyticsFlow<Spec>?
    private var stage: Stage?

    public init(context: AnalyticsContext) {
        scope = context.isExcluded ? nil : context.scope
        scope?.perform {
            guard let analytics = context.analytics else { return }
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: .botMiniApp)
            flow.set(entryPoint: .miniAppRequest)
            flow.step(.request)
            guard scope?.isValid == true else { return }
            self.flow = flow
            stage = .loading
            scope?.observe(self)
        }
    }

    public func metadataReady() {
        scope?.perform {
            guard stage == .loading else { return }
            stage = .prepared
            flow?.step(.metadataReady)
        }
    }

    public func previewOpened() {
        scope?.perform {
            guard stage == .prepared else { return }
            stage = .preview
            flow?.step(.openPreview)
        }
    }

    public func pickerOpened() {
        scope?.perform {
            guard stage == .preview else { return }
            stage = .picker
            flow?.step(.openPicker)
        }
    }

    public func metadataUnavailable() {
        scope?.perform {
            guard stage == .loading else { return }
            flow?.set(result: .metadataUnavailable)
            flow?.step(.metadataUnavailable)
            finish(.fail)
        }
    }

    public func pickerFinished(accepted: Bool) {
        pickerFinished(result: accepted ? .accepted : .notAccepted)
    }

    public func pickerFinished(result: PickerResult) {
        scope?.perform {
            guard stage == .picker else { return }
            switch result {
            case .accepted:
                flow?.set(result: .accepted)
                flow?.step(.accepted)
                finish(.success)
            case .partiallyAccepted:
                flow?.set(result: .partiallyAccepted)
                flow?.step(.partiallyAccepted)
                finish(.fail)
            case .rejected:
                flow?.set(result: .rejected)
                flow?.step(.rejected)
                finish(.fail)
            case .unknown:
                flow?.set(result: .acceptanceUnknown)
                flow?.step(.acceptanceUnknown)
                finish(.fail)
            case .cancelled:
                flow?.step(.cancelPicker)
                finish(.cancelled)
            case .notAccepted:
                flow?.set(result: .notAccepted)
                flow?.step(.notAccepted)
                finish(.fail)
            }
        }
    }

    public func cancelPreview() {
        scope?.perform {
            guard stage == .preview || stage == .picker else { return }
            flow?.step(.cancelPreview)
            finish(.cancelled)
        }
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
    }

    var retainedStateCount: Int {
        return scope?.policy.sync { (flow?.storedStepCount ?? 0) + (stage == nil ? 0 : 1) } ?? 0
    }

    deinit {
        discard()
    }
}
