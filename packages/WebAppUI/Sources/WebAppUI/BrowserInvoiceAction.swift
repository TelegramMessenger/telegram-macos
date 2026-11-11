import AppAnalytics
import Localization
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TGUIKit

final class BrowserInvoiceAction {
    private var generation: UInt64 = 0
    private var active = false
    private let request = MetaDisposable()

    func reset() {
        generation &+= 1
        active = false
        request.set(nil)
    }

    private func finish(_ generation: UInt64) -> Bool {
        guard active, self.generation == generation else { return false }
        active = false
        return true
    }

    func open(context: any AccountContextProtocol, slug: String, window: Window, analyticsContext: AnalyticsContext, canPresent: @escaping () -> Bool, completion: @escaping (String) -> Void) {
        guard !active, !slug.isEmpty else { return }
        active = true
        generation &+= 1
        let generation = self.generation
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let pending = MetaDisposable()
        request.set(pending)
        var receivedInvoice = false
        let signal = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: .slug(slug)) |> take(1) |> deliverOnMainQueue, for: window)
        guard active, self.generation == generation else { return }
        pending.set(origin.preservingPresentation(signal).start(next: { [weak self] invoice in
            guard let self else { return }
            receivedInvoice = true
            guard canPresent(), self.active, self.generation == generation else {
                _ = self.finish(generation)
                return
            }
            BrowserHooks.shared.openInvoiceObserved(context, invoice, slug, window, analyticsContext: origin, completion: { [weak self] status in
                guard let self, self.finish(generation) else { return }
                let delivery = origin.beginPresentation()
                defer { delivery.end() }
                completion(status)
            })
        }, error: { [weak self] _ in
            guard let self, self.finish(generation) else { return }
            guard canPresent() else { return }
            showModalText(for: window, text: strings().paymentsInvoiceNotExists)
            if self.generation == generation { completion("failed") }
        }, completed: { [weak self] in
            if !receivedInvoice { _ = self?.finish(generation) }
        }))
    }

    deinit {
        request.dispose()
    }
}
