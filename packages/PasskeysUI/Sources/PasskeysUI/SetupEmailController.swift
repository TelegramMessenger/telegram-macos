import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import LocalAnimations
import DateUtils
import TelegramIconsTheme
import Postbox
import AppAnalytics

private final class CodeEntryRow : GeneralRowItem {
    fileprivate let count: Int
    fileprivate let locked: Bool
    fileprivate let takeNext: (String)->Void
    fileprivate let takeError: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, count: Int, locked: Bool, takeNext: @escaping(String)->Void, takeError: @escaping()->Void) {
        self.count = count
        self.locked = locked
        self.takeNext = takeNext
        self.takeError = takeError
        super.init(initialSize, height: 50, stableId: stableId, viewType: viewType)
    }
    public override func viewClass() -> AnyClass {
        return CodeEntryRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().loginCodePlaceholder
    }
}

private final class CodeEntryRowView : GeneralContainableRowView {
    fileprivate let input: CodeEntryControl = CodeEntryControl(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(input)
    }
    
    public override var firstResponder: NSResponder? {
        return input.firstResponder()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func shakeView() {
        input.shake(beep: true)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? CodeEntryRow else {
            return
        }
        
        let size = self.input.update(count: item.count)
        self.input.setFrameSize(size)
        self.input.takeNext = item.takeNext
        self.input.takeError = item.takeError
        self.input.set(locked: item.locked, animated: true)

    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func layout() {
        super.layout()
        self.input.center()
    }
}


private final class Arguments {
    public let context: any AccountContextProtocol
    fileprivate let takeNext: (String)->Void
    fileprivate let takeError: ()->Void

    public init(context: any AccountContextProtocol, takeNext: @escaping(String)->Void, takeError: @escaping()->Void) {
        self.context = context
        self.takeNext = takeNext
        self.takeError = takeError
    }
}


private struct State : Equatable {
    
    public enum State : Equatable {
        case email
        case code(ChangeLoginEmailData)
    }
    
    public var error: InputDataValueError?
    public var value: InputDataValue
    public var isLoading: Bool
    
    public var state: State = .email
    
    
}

private let _id_input = InputDataIdentifier("_id_input")
private let _id_code = InputDataIdentifier("_id_code")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    var sectionId:Int32 = 0
    var index:Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    
    switch state.state {
    case .email:
        entries.append(.input(sectionId: sectionId, index: index, value: state.value, error: state.error, identifier: _id_input, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().emailEnterPlaceholder, filter: { $0 }, limit: 255))
        index += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().loginEmailDescription), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
        index += 1
    case let .code(data):
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_code, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return CodeEntryRow(initialSize, stableId: stableId, viewType: .singleItem, count: Int(data.length), locked: state.isLoading, takeNext: arguments.takeNext, takeError: arguments.takeError)
        }))
        index += 1
        
        if let error = state.error {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(error.description), data: InputDataGeneralTextData(color: theme.colors.redUI, detectBold: false, viewType: .textBottomItem, centerViewAlignment: true, alignment: .center)))
            index += 1
        }
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().loginEnterCodeNewEmailText(data.email)), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem, centerViewAlignment: true, alignment: .center)))
        index += 1

    }
    
    
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func SetupEmailController(context: any AccountContextProtocol, pattern: String?) -> InputDataModalController {
    
    
    
    let requestDisposable = MetaDisposable()
    var requestGeneration = 0
    var isClosed = false

    let initialState = State(error: nil, value: .string(""), isLoading: false)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->InputDataController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    func trackRequest<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> {
        requestGeneration += 1
        let generation = requestGeneration
        updateState { current in
            var current = current
            current.isLoading = true
            current.error = nil
            return current
        }
        return signal |> afterDisposed {
            Queue.mainQueue().async {
                guard generation == requestGeneration, !isClosed else {
                    return
                }
                updateState { current in
                    var current = current
                    current.isLoading = false
                    return current
                }
            }
        }
    }

    let arguments = Arguments(context: context, takeNext: { value in
        let state = stateValue.with { $0 }
        guard !isClosed, !state.isLoading, case .code = state.state else {
            return
        }
        requestDisposable.set(showModalProgress(signal: trackRequest(verifyLoginEmailChange(account: context.account, code: .emailCode(value))), for: window).start(error: { error in
            let text: String
            switch error {
            case .limitExceeded:
                text = strings().emailCodeFloodError
            case .invalidCode:
                text = strings().emailInvalidCodeError
            case .generic:
                text = strings().emailUnknownError
            case .codeExpired:
                text = strings().phoneCodeExpired
            case .timeout:
                text = strings().emailNetworkError
            case .invalidEmailToken:
                text = strings().emailInvalidEmailTokenError
            case .emailNotAllowed:
                text = strings().emailEmailNotAllowedError
            }
            updateState { current in
                var current = current
                current.error = InputDataValueError(description: text, target: .data)
                current.isLoading = false
                return current
            }
            getController?()?.proccessValidation(.fail(.fields([_id_code : .shake])))
        }, completed: {
            close?()
            showModalText(for: window, text: strings().loginEmailChanged)
        }))
    }, takeError: {
        updateState { current in
            var current = current
            current.error = nil
            return current
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().loginEnterNewEmailTitle)
    controller.analyticsScreen = .settingsPrivacyLoginEmail
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.validateData = { _ in
        guard !isClosed else {
            return .fail(.none)
        }
        let state = stateValue.with { $0 }
        let value = state.value.stringValue ?? ""
        
        switch state.state {
        case .email:
            guard !state.isLoading else {
                return .fail(.none)
            }
            if isValidEmail(value) {
                return .fail(.doSomething(next: { f in
                    guard !isClosed, !stateValue.with({ $0.isLoading }) else {
                        f(.none)
                        return
                    }
                    
                    requestDisposable.set(showModalProgress(signal: trackRequest(sendLoginEmailChangeCode(account: context.account, email: value)), for: window).start(next: { value in
                        updateState { current in
                            var current = current
                            current.state = .code(value)
                            current.isLoading = false
                            return current
                        }
                        f(.none)
                    }, error: { error in
                        let text: String
                        switch error {
                        case .limitExceeded:
                            text = strings().loginFloodWait
                        case .generic, .codeExpired:
                            text = strings().unknownError
                        case .timeout:
                            text = strings().emailNetworkError
                        case .invalidEmail:
                            text = strings().emailInvalidEmailError
                        case .emailNotAllowed:
                            text = strings().emailEmailNotAllowedError
                        }
                        updateState { current in
                            var current = current
                            current.isLoading = false
                            return current
                        }
                        f(.none)
                        showModalText(for: window, text: text)
                    }))
                    
                }))
            } else {
                updateState { current in
                    var current = current
                    current.error = .init(description: strings().emailInvalidEmailError, target: .data)
                    return current
                }
                return .fail(.fields([_id_input : .shake]))
            }
        case .code:
            requestDisposable.set(nil)
            requestGeneration += 1
            updateState { current in
                var current = current
                current.state = .email
                current.error = nil
                current.isLoading = false
                return current
            }
            return .none
            
        }
        
    }
    
    controller.updateDatas = { data in
        guard !isClosed, let value = data[_id_input] else {
            return .fail(.none)
        }
        updateState { current in
            var current = current
            current.value = value
            current.error = nil
            return current
        }
        return .fail(.none)
    }
    
    controller.onDeinit = {
        requestDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().loginNext, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, closeHandler: { close in
        isClosed = true
        requestGeneration += 1
        requestDisposable.dispose()
        close()
    })
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.afterTransaction = { [weak modalInteractions, weak modalController] controller in
        let state = stateValue.with { $0 }
        modalInteractions?.updateDone { f in
            switch state.state {
            case .email:
                f.isEnabled = !state.isLoading
                f.set(text: strings().loginNext, for: .Normal)
                f.set(background: theme.colors.accent, for: .Normal)
            case .code:
                f.isEnabled = true
                f.set(text: strings().modalCancel, for: .Normal)
                f.set(background: theme.colors.redUI, for: .Normal)
            }
        }
        switch state.state {
        case .email:
            if let _ = pattern {
                controller.centerModalHeader = .init(title: strings().loginEnterNewEmailTitle)
            } else {
                controller.centerModalHeader = .init(title: strings().loginEmailTitle)
            }
        case .code:
            controller.centerModalHeader = .init(title: strings().loginHeaderCode)
            if controller.analyticsScreen != .settingsPrivacyLoginEmailCode {
                controller.analyticsScreen = .settingsPrivacyLoginEmailCode
                Analytics.shared.screens.show(ObjectIdentifier(controller), screen: .settingsPrivacyLoginEmailCode)
            }
        }
        modalController?.updateLocalizationAndTheme(theme: theme)
    }
        
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
    
}





