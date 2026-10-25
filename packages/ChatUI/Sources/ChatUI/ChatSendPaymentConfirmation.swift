import AlertsUI
import Dispatch
import TGUIKit
import TelegramCore
import Localization

public func verifyChatSendPayment(for window: Window, header: String, information: String, ok: String, option: String, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void = {}, dismissed: @escaping () -> Void = {}) {
    var resolved = false
    verifyAlert(for: window, header: header, information: information, ok: ok, option: option, optionIsSelected: false, successHandler: { result in
        guard !resolved else { return }
        resolved = true
        successHandler(result)
    }, cancelHandler: {
        guard !resolved else { return }
        resolved = true
        cancelHandler()
    }, onDeinit: {
        DispatchQueue.main.async {
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
    alert(for: chatInteraction.interactionContext.window, header: strings().chatPayStarsPriceChangedTitle, info: strings().chatPayStarsPriceChangedText)
    return false
}
