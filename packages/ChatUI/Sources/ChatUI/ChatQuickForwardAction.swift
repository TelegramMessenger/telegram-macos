import AppAnalytics
import Postbox
import SwiftSignalKit
import TelegramContext

final class ChatQuickForwardAction {
    private typealias Spec = AnalyticsFlows.ChatQuickForward
    private let disposable = MetaDisposable()
    private var generation: UInt64 = 0
    private var pending: UInt64?
    private var flow: AnalyticsFlow<Spec>?

    func reset() {
        generation &+= 1
        pending = nil
        flow?.discard()
        flow = nil
        disposable.set(nil)
    }

    func start(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?, analyticsContext: AnalyticsContext, isCurrent: () -> Bool, request: () -> Signal<ChatHistoryForwardResult, String>) {
        guard pending == nil, isCurrent() else { return }
        generation &+= 1
        let generation = self.generation
        pending = generation
        let subscription = MetaDisposable()
        disposable.set(subscription)
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext).restricting(peerId: peerId)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let flow = AnalyticsFlow<Spec>(analytics: Analytics.shared, scope: origin.scope)
        guard pending == generation else { flow.discard(); return }
        self.flow = flow
        flow.set(entryPoint: threadId == nil ? .directTarget : .topicTarget)
        flow.step(.request)
        guard pending == generation else { return }
        let signal = request()
        guard pending == generation else { return }
        subscription.set(origin.preservingPresentation(signal |> take(1) |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, self.pending == generation else { return }
            switch result {
            case .draftPrepared: self.finish(.draftPrepared, .draftPrepared, .success)
            case .destinationReady: self.finish(.destinationReady, .destinationReady, .success)
            case .accepted: self.finish(.accepted, .accepted, .success)
            case .partiallyAccepted: self.finish(.partiallyAccepted, .partiallyAccepted, .fail)
            case .rejected: self.finish(.rejected, .rejected, .fail)
            case .acceptanceUnknown: self.finish(.acceptanceUnknown, .acceptanceUnknown, .fail)
            case .sourceUnavailable: self.finish(.sourceUnavailable, .sourceUnavailable, .fail)
            case .targetUnavailable: self.finish(.targetUnavailable, .targetUnavailable, .fail)
            case .restricted: self.finish(.restricted, .restricted, .fail)
            case .completionUnknown: self.finish(.completionUnknown, .completionUnknown, .fail)
            }
        }, error: { [weak self] _ in
            guard let self, self.pending == generation else { return }
            self.finish(.operationFailed, .operationFailed, .fail)
        }, completed: { [weak self] in
            guard let self, self.pending == generation else { return }
            self.reset()
        }))
    }

    private func finish(_ result: Spec.Result, _ step: Spec.Step, _ outcome: AnalyticsFlowOutcome) {
        let flow = self.flow
        self.flow = nil
        flow?.set(result: result)
        flow?.step(step)
        reset()
        flow?.finish(outcome)
    }

    deinit {
        disposable.dispose()
        flow?.discard()
    }
}
