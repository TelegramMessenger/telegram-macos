import AppAnalytics
import InputDataUI
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TGUIKit

final class StarsScreenContext {
    let analytics: AnalyticsContext
    let disposables = DisposableSet()
    let purchase = StarPurchaseSession()
    private let closed = Atomic(value: false)

    var isOpen: Bool { !closed.with { $0 } }

    init(context: any AccountContextProtocol, source: Star_ListScreenSource, analyticsContext: AnalyticsContext?) {
        var origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
        switch source {
        case let .purchase(peer, _), let .purchaseSubscribe(peer, _), let .prolongSubscription(peer, _), let .reactions(peer, _), let .gift(peer):
            origin = origin.restricting(peerId: peer.id)
        case .buy, .account:
            break
        }
        analytics = origin
    }

    func action(_ callback: @escaping () -> Void) -> () -> Void {
        return {
            guard self.isOpen else { return }
            let presentation = self.analytics.beginPresentation()
            defer { presentation.end() }
            callback()
        }
    }

    func action<Value>(_ callback: @escaping (Value) -> Void) -> (Value) -> Void {
        return { value in self.action { callback(value) }() }
    }

    func preserving<Value, Failure>(_ signal: Signal<Value, Failure>) -> Signal<Value, Failure> {
        return Signal { subscriber in
            guard self.isOpen else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            return self.analytics.preservingPresentation(signal).start(next: { value in
                if self.isOpen { subscriber.putNext(value) }
            }, error: { error in
                if self.isOpen { subscriber.putError(error) }
            }, completed: {
                subscriber.putCompletion()
            })
        }
    }

    func showChild(_ build: () -> ModalViewController, show: (ModalViewController) -> Void) {
        guard isOpen else { return }
        let lifetime = analytics.beginPresentation()
        let controller = build()
        controller.analyticsContext = analytics
        (controller as? InputDataModalController)?.current.analyticsContext = analytics
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            let delivery = self.analytics.beginPresentation()
            defer { delivery.end(); lifetime.end() }
            onDeinit?()
        }
        guard isOpen else { return }
        show(controller)
    }

    func close() {
        guard !closed.swap(true) else { return }
        let presentation = analytics.beginPresentation()
        defer { presentation.end() }
        _ = purchase.close()
        disposables.dispose()
    }
}
