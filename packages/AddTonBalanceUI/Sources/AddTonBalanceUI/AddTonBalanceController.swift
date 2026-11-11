import Cocoa
import TGUIKit
import SwiftSignalKit
import CurrencyFormat
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import LocalAnimations
import TelegramCore
import Postbox
import AppAnalytics
private final class Arguments {
    public let context: any AccountContextProtocol
    public init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {
    public var tonAmount: Int64
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
    
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        let attr = NSMutableAttributedString()
        let formattedAmount = formatCurrencyAmount(state.tonAmount, currency: TON).prettyCurrencyNumberUsd
        attr.append(string: strings().fragmentTonAddFundsHeaderAmount(formattedAmount), color: theme.colors.text, font: .medium(18))
        attr.append(string: "\n\n")
        attr.append(string: strings().fragmentTonAddFundsHeaderInfo, color: theme.colors.text, font: .normal(.text))
        return AddTonBalanceHooks.shared.makeStickerHeaderItem(initialSize, stableId, arguments.context, LocalAnimatedSticker.diamond, attr, NSMakeSize(120, 120), theme.colors.listBackground, nil)
    }))
  
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func AddTonBalanceController(context: any AccountContextProtocol, tonAmount: Int64) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(tonAmount: tonAmount)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    let arguments = Arguments(context: context)
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().fragmentTonAddFundsTitle)
    controller.analyticsScreen = .tonAddFunds

    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        close?()
        LinkHooks.shared.openExternalLink(strings().fragmentTonAddFundsLink, false)
        return .none
    }

    let modalInteractions = ModalInteractions(
        acceptTitle: strings().fragmentTonAddFundsAction,
        accept: { [weak controller] in
            _ = controller?.returnKeyAction()
        },
        singleButton: true
    )

    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
    
}

