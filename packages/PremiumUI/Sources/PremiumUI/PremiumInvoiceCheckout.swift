import AppAnalytics
import InputDataUI
import Localization
import SceneEffects
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TGUIKit

func premiumInvoiceCheckout(context: any AccountContextProtocol, slug: String, analyticsContext: AnalyticsContext, paid: @escaping () -> Void) {
    let presentation = analyticsContext.beginPresentation()
    defer { presentation.end() }
    let signal = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: .slug(slug)) |> take(1) |> deliverOnMainQueue, for: context.window)
    _ = analyticsContext.preservingPresentation(signal).start(next: { invoice in
        var completed = false
        if let controller = FeatureNavigationHooks.shared.makePaymentsCheckoutObserved(context, .slug(slug), invoice, analyticsContext: analyticsContext, completion: { status in
            guard !completed else { return }
            completed = true
            if case .paid = status {
                PlayConfetti(for: context.window)
                paid()
            }
        }) {
            showModal(with: controller, for: context.window)
        }
    }, error: { _ in
        showModalText(for: context.window, text: strings().paymentsInvoiceNotExists)
    })
}
