import AppAnalytics
import Localization
import Postbox
import StarsUI
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramUtils
import TGUIKit

final class ChatPaidMediaPurchase {
    private let active = Atomic(value: false)
    private let request = MetaDisposable()

    func open(context: any AccountContextProtocol, messageId: MessageId, image: TelegramMediaImage, count: StarPurchaseType.PaidMediaCount, analyticsContext: AnalyticsContext) {
        guard !active.swap(true) else { return }
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: messageId.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let pending = MetaDisposable()
        request.set(pending)
        var receivedInvoice = false
        let signal = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: .message(messageId)) |> take(1) |> deliverOnMainQueue, for: context.window)
        pending.set(origin.preservingPresentation(signal).start(next: { [weak self] invoice in
            guard let self else { return }
            receivedInvoice = true
            let lifetime = origin.beginPresentation()
            let controller = Star_PurschaseInApp(context: context, invoice: invoice, source: .message(messageId), type: .paidMedia(image, count), analyticsContext: origin)
            let onDeinit = controller.onDeinit
            controller.onDeinit = { [weak self] in
                let delivery = origin.beginPresentation()
                defer { delivery.end(); lifetime.end() }
                onDeinit?()
                _ = self?.active.swap(false)
            }
            showModal(with: controller, for: context.window)
        }, error: { [weak self] _ in
            guard let self else { return }
            _ = self.active.swap(false)
            showModalText(for: context.window, text: strings().paymentsInvoiceNotExists)
        }, completed: { [weak self] in
            if !receivedInvoice { _ = self?.active.swap(false) }
        }))
    }

    deinit {
        request.dispose()
    }
}

func openChatMessagePayment(context: any AccountContextProtocol, messageId: MessageId, invoice: TelegramMediaInvoice, analyticsContext: AnalyticsContext) {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: messageId.peerId, inherited: analyticsContext)
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    if let receiptMessageId = invoice.receiptMessageId {
        ChatNavigationHooks.shared.showPaymentsReceiptObserved(context, receiptMessageId, invoice, context.window, analyticsContext: origin)
    } else if invoice.currency == XTR {
        showModal(with: Star_PurschaseInApp(context: context, invoice: invoice, source: .message(messageId), analyticsContext: origin), for: context.window)
    } else {
        ChatNavigationHooks.shared.showPaymentsCheckoutObserved(context, messageId, invoice, context.window, analyticsContext: origin)
    }
}
