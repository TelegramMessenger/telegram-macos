import Cocoa
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import CurrencyFormat
import InAppSettings
import TelegramMediaUtils
import AlertsUI
import AppAnalytics


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let select:(BotPaymentSavedCredentials)->Void
    public let addNew:()->Void
    public let addPaymentMethod:(String)->Void
    public init(context: (any AccountContextProtocol), select: @escaping(BotPaymentSavedCredentials)->Void, addNew:@escaping()->Void, addPaymentMethod:@escaping(String)->Void) {
        self.context = context
        self.select = select
        self.addNew = addNew
        self.addPaymentMethod = addPaymentMethod
    }
}

private struct State : Equatable {
    public var cards:[BotPaymentSavedCredentials]
    public var form: BotPaymentForm
    public var methods: [BotCheckoutPaymentMethod]
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
   
    
    for (i, method) in state.methods.enumerated() {
        let viewType = bestGeneralViewType(state.methods, for: i)
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("\(arc4random())"), data: .init(name: method.title, color: theme.colors.text, type: .none, viewType: viewType, action: {
            switch method {
            case let .other(method):
                arguments.addPaymentMethod(method.url)
            case let .savedCredentials(credeitials):
                arguments.select(credeitials)
            default:
                break
            }
        })))
        index += 1
    }
    
    if !state.methods.isEmpty {
        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1
    }
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("add_new"), data: .init(name: strings().checkoutPaymentMethodNew, color: theme.colors.accent, type: .context(""), viewType: .singleItem, action: {
        arguments.addNew()
    })))
    index += 1
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func PamentsSelectMethodController(context: (any AccountContextProtocol), cards:[BotPaymentSavedCredentials], form: BotPaymentForm, methods: [BotCheckoutPaymentMethod], select:@escaping(BotPaymentSavedCredentials)->Void, addNew: @escaping()->Void, addPaymentMethod:@escaping(String, BotPaymentForm)->Void) -> InputDataModalController {

    var close:(()->Void)? = nil
    
    let actionsDisposable = DisposableSet()

    let initialState = State(cards: cards, form: form, methods: methods)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let arguments = Arguments(context: context, select: { option in
        close?()
        select(option)
    }, addNew: {
        close?()
        addNew()
    }, addPaymentMethod: { url in
        addPaymentMethod(url, form)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().checkoutPaymentMethodTitle)
    controller.analyticsScreen = .paymentsMethod
    
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





