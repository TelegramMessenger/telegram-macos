import Foundation

public final class AnalyticsShareJourney: AnalyticsRevocable {
    public typealias Spec = AnalyticsFlows.ChatShare

    public enum Result {
        case accepted
        case partiallyAccepted
        case rejected
        case unknown
    }

    private enum Stage {
        case loading
        case ready
        case picker
        case submitting
    }

    private let scope: AnalyticsScope?
    private var flow: AnalyticsFlow<Spec>?
    private var stage: Stage?
    private var retryPending = false
    private var retryCount = 0
    private var confirmationOpen = false

    public init(context: AnalyticsContext, entry: Spec.EntryPoint, source: AnalyticsScreen? = nil) {
        scope = context.isExcluded || source?.isAnalyticsExcluded == true ? nil : context.scope
        scope?.perform {
            guard let analytics = context.analytics else { return }
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: source)
            flow.set(entryPoint: entry)
            flow.set(retryCount: ._0)
            flow.step(.request)
            guard scope?.isValid == true else { return }
            self.flow = flow
            stage = entry == .profileContact ? .loading : .ready
            scope?.observe(self)
        }
    }

    public func sourceReady() {
        scope?.perform {
            guard stage == .loading else { return }
            stage = .ready
            flow?.step(.sourceReady)
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

    public func submitted() {
        scope?.perform {
            guard stage == .picker, !confirmationOpen else { return }
            retryIfBlocked()
            guard stage == .picker, scope?.isValid == true else { return }
            stage = .submitting
            flow?.step(.submit)
        }
    }

    public func blocked(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard stage == .picker else { return }
            retryPending = true
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
        }
    }

    public func retryIfBlocked() {
        scope?.perform {
            guard stage == .picker, retryPending, !confirmationOpen else { return }
            retryPending = false
            retryCount = min(retryCount + 1, 4)
            flow?.set(retryCount: retryCount == 1 ? ._1 : retryCount < 4 ? ._2_3 : ._4_plus)
            flow?.step(.retry)
        }
    }

    public func paymentConfirmationOpened() {
        scope?.perform {
            guard stage == .picker, !confirmationOpen else { return }
            confirmationOpen = true
            flow?.step(.openPaymentConfirmation)
        }
    }

    public func paymentConfirmationResolved(confirmed: Bool) {
        scope?.perform {
            guard stage == .picker, confirmationOpen else { return }
            confirmationOpen = false
            if !confirmed { retryPending = true }
            flow?.step(confirmed ? .confirmPayment : .cancelPaymentConfirmation)
        }
    }

    public func paymentConfirmationEnded() {
        scope?.policy.sync {
            if confirmationOpen { discard() }
        }
    }

    public func topUpOpened() {
        scope?.perform {
            guard stage == .picker else { return }
            flow?.step(.openTopUp)
        }
    }

    public func complete(_ result: Result) {
        scope?.perform {
            guard stage == .submitting else { return }
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
            }
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
        scope?.policy.sync {
            if stage == .submitting { discard() }
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
        retryPending = false
        retryCount = 0
        confirmationOpen = false
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
            if confirmationOpen {
                count += 1
            }
            return count
        } ?? 0
    }

    deinit {
        discard()
    }
}
