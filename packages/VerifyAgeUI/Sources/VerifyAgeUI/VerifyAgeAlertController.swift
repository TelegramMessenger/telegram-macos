import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
import InputDataUI
import GeneralRows
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import LocalAnimations
import TelegramCore
import Postbox
import WebAppUI
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {

}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    let attr = NSMutableAttributedString()
    
    attr.append(string: strings().ageVerificationTitle, color: theme.colors.text, font: .medium(.huge))
    attr.append(string: "\n", color: theme.colors.text, font: .medium(.text))
    let country = arguments.context.appConfiguration.getStringValue("verify_age_country", orElse: "")
    if country.isEmpty {
        attr.append(string: _NSLocalizedString("AgeVerification.Text"), color: theme.colors.text, font: .normal(.text))
    } else {
        attr.append(string: _NSLocalizedString("AgeVerification.Text.\(country)"), color: theme.colors.text, font: .normal(.text))
    }
    
    attr.detectBoldColorInString(with: .medium(.text))
    
    let image = generateImage(NSMakeSize(90, 90), contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.setFillColor(theme.colors.accent.cgColor)
        ctx.fillEllipse(in: size.bounds)
        let image = TelegramThemeHooks.shared.image(.iconAgeVerification).precomposed(theme.colors.underSelectedColor)
        ctx.draw(image, in: size.bounds.focus(image.backingSize))
    })

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("body"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return VerifyAgeHooks.shared.makeStickerHeaderItem(initialSize, stableId, arguments.context, nil, attr, NSMakeSize(90, 90), nil, image)
    }))
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func VerifyAgeAlertController(context: any AccountContextProtocol) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State()
    
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
    
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .appAgeVerification
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        let botUsername = context.appConfiguration.getStringValue("verify_age_bot_username", orElse: "")
        
        if !botUsername.isEmpty {
            _ = showModalProgress(signal: context.engine.peers.resolvePeerByName(name: botUsername, referrer: nil), for: window).start(next: { result in
                switch result {
                case let .result(peer):
                    if let peer {
                        BrowserStateContext.get(context).open(tab: .mainapp(bot: peer, source: .generic))
                    }
                default:
                    break
                }
            })
        }
        
        close?()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().ageVerificationVerify, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}


/*
 
 */



