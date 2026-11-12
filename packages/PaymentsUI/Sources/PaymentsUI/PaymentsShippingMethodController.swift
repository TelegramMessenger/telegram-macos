import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import CurrencyFormat
import InAppSettings
import TelegramMediaUtils
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import AppAnalytics


private final class Arguments {
    public let context: any AccountContextProtocol
    public let select:(BotPaymentShippingOption)->Void
    public init(context: any AccountContextProtocol, select: @escaping(BotPaymentShippingOption)->Void) {
        self.context = context
        self.select = select
    }
}

private struct State : Equatable {
    public var shippingOptions: [BotPaymentShippingOption]
    public var form: BotPaymentForm
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    for option in state.shippingOptions {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier(option.title), data: .init(name: option.title, color: theme.colors.text, type: .context(formatCurrencyAmount(option.prices.reduce(0, { $0 + $1.amount }), currency: state.form.invoice.currency)), viewType: bestGeneralViewType(state.shippingOptions, for: option), action: {
            arguments.select(option)
        })))
        index += 1
    }
  
    // entries
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func PaymentsShippingMethodController(context: any AccountContextProtocol, shippingOptions: [BotPaymentShippingOption], form: BotPaymentForm, select:@escaping(BotPaymentShippingOption)->Void) -> InputDataModalController {

    var close:(()->Void)? = nil
    
    let actionsDisposable = DisposableSet()

    let initialState = State(shippingOptions: shippingOptions, form: form)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let arguments = Arguments(context: context, select: { option in
        close?()
        select(option)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().checkoutShippingMethod)
    controller.analyticsScreen = .paymentsShippingMethod
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalCancel, accept: {
        close?()
    }, singleButton: true)


    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    

    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}





