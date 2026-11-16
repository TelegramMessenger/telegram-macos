import AlertsUI
import AppAnalytics
import Dispatch
import TGUIKit
import TelegramCore
import Localization

public func verifyChatSendPayment(for window: Window, header: String, information: String, ok: String, option: String, analyticsContext: AnalyticsContext, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void = {}, dismissed: @escaping () -> Void = {}) {
    let lifetime = analyticsContext.beginPresentation()
    var resolved = false
    verifyAlert(for: window, header: header, information: information, ok: ok, option: option, optionIsSelected: false, successHandler: { result in
        guard !resolved else { return }
        resolved = true
        let delivery = analyticsContext.beginPresentation()
        defer { delivery.end() }
        successHandler(result)
    }, cancelHandler: {
        guard !resolved else { return }
        resolved = true
        let delivery = analyticsContext.beginPresentation()
        defer { delivery.end() }
        cancelHandler()
    }, onDeinit: {
        DispatchQueue.main.async {
            let delivery = analyticsContext.beginPresentation()
            defer {
                lifetime.end()
                delivery.end()
            }
            if !resolved {
                resolved = true
                dismissed()
            }
        }
    })
}

public func chatPaidMessagePriceIsCurrent(_ chatInteraction: ChatInteraction, _ price: StarsAmount) -> Bool {
    if chatInteraction.presentation.sendPaidMessageStars == price {
        return true
    }
    alert(for: chatInteraction.interactionContext.window, header: strings().chatSendPaymentConfirmationPriceChanged, info: strings().chatSendPaymentConfirmationPriceChangedInfo)
    return false
}
