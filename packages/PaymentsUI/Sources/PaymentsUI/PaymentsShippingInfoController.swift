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

private let cManager: CountryManager = CountryManager()


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let toggleSaveInfo:()->Void
    public init(context: (any AccountContextProtocol), toggleSaveInfo: @escaping()->Void) {
        self.context = context
        self.toggleSaveInfo = toggleSaveInfo
    }
}

private let _id_checkout_info_address1 = InputDataIdentifier("_id_checkout_info_address1")
private let _id_checkout_info_address2 = InputDataIdentifier("_id_checkout_info_address2")
private let _id_checkout_info_city = InputDataIdentifier("_id_checkout_info_city")
private let _id_checkout_info_state = InputDataIdentifier("_id_checkout_info_state")
private let _id_checkout_info_country = InputDataIdentifier("_id_checkout_info_country")
private let _id_checkout_info_postcode = InputDataIdentifier("_id_checkout_info_postcode")
private let _id_checkout_info_name = InputDataIdentifier("_id_checkout_info_name")
private let _id_checkout_info_email = InputDataIdentifier("_id_checkout_info_email")
private let _id_checkout_info_phone = InputDataIdentifier("_id_checkout_info_phone")
private let _id_checkout_info_save_info = InputDataIdentifier("_id_checkout_info_save_info")


private struct State : Equatable {
    
    public struct Address : Equatable {
        public var address1: String
        public var address2: String
        public var city: String
        public var state: String
        public var country: String
        public var postcode: String
        public init(address1: String, address2: String, city: String, state: String, country: String, postcode: String) {
            self.address1 = address1
            self.address2 = address2
            self.city = city
            self.state = state
            self.country = country
            self.postcode = postcode
        }
    }
    
    public var address: Address?
    public var name: String?
    public var email: String?
    public var phone: String?
    
    public var saveInfo: Bool
    
    public var errors:[InputDataIdentifier: InputDataValueError]
    
    public var firstEmptyId: InputDataIdentifier? {
        if let address = address {
            if address.address1.isEmpty {
                return _id_checkout_info_address1
            }
            if address.city.count < 2 {
                return _id_checkout_info_city
            }
            if address.state.count < 2 && address.country.lowercased() == "us" {
                return _id_checkout_info_state
            }
            if address.country.isEmpty {
                return _id_checkout_info_country
            }
            if address.postcode.count < 2 {
                return _id_checkout_info_postcode
            }
        }
        if let value = name, value.isEmpty {
            return _id_checkout_info_name
        }
        if let value = email, value.isEmpty {
            return _id_checkout_info_email
        }
        if let value = phone, value.isEmpty {
            return _id_checkout_info_phone
        }
        return nil
    }
    
    public var formInfo: BotPaymentRequestedInfo {
        var shippingAddress: BotPaymentShippingAddress?
        if let address = self.address {
            shippingAddress = BotPaymentShippingAddress(streetLine1: address.address1, streetLine2: address.address2, city: address.city, state: address.state, countryIso2: address.country, postCode: address.postcode)
        }
        return BotPaymentRequestedInfo(name: self.name, phone: self.phone, email: self.email, shippingAddress: shippingAddress)
    }

}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
  
    
    if let address = state.address {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().checkoutInfoShippingInfoTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        entries.append(.input(sectionId: sectionId, index: index, value: .string(address.address1), error: nil, identifier: _id_checkout_info_address1, mode: .plain, data: .init(viewType: .firstItem), placeholder: InputDataInputPlaceholder(strings().checkoutInfoShippingInfoAddress1), inputPlaceholder: strings().checkoutInfoShippingInfoAddress1Placeholder, filter: { $0 }, limit: 64))
        index += 1
        
        entries.append(.input(sectionId: sectionId, index: index, value: .string(address.address2), error: nil, identifier: _id_checkout_info_address2, mode: .plain, data: .init(viewType: .innerItem), placeholder: InputDataInputPlaceholder(strings().checkoutInfoShippingInfoAddress2), inputPlaceholder: strings().checkoutInfoShippingInfoAddress2Placeholder, filter: { $0 }, limit: 64))
        index += 1
        
        entries.append(.input(sectionId: sectionId, index: index, value: .string(address.city), error: nil, identifier: _id_checkout_info_city, mode: .plain, data: .init(viewType: .innerItem), placeholder: InputDataInputPlaceholder(strings().checkoutInfoShippingInfoCity), inputPlaceholder: strings().checkoutInfoShippingInfoCityPlaceholder, filter: { $0 }, limit: 64))
        index += 1
        
        entries.append(.input(sectionId: sectionId, index: index, value: .string(address.state), error: nil, identifier: _id_checkout_info_state, mode: .plain, data: .init(viewType: .innerItem), placeholder: InputDataInputPlaceholder(strings().checkoutInfoShippingInfoState), inputPlaceholder: strings().checkoutInfoShippingInfoStatePlaceholder, filter: { $0 }, limit: 64))
        index += 1
        
        
        let filedata = try! String(contentsOfFile: Bundle.main.path(forResource: "countries", ofType: nil)!)
        
        let countries: [ValuesSelectorValue<InputDataValue>] = filedata.components(separatedBy: "\n").compactMap { country in
            let entry = country.components(separatedBy: ";")
            if entry.count >= 3 {
                return ValuesSelectorValue(localized: entry[2], value: .string(entry[1]))
            } else {
                return nil
            }
        }.sorted(by: { $0.localized < $1.localized})
        
        entries.append(InputDataEntry.selector(sectionId: sectionId, index: index, value: .string(state.address?.country), error: nil, identifier: _id_checkout_info_country, placeholder: strings().checkoutInfoShippingInfoCountry, viewType: .innerItem, values: countries))
        index += 1


        
        entries.append(.input(sectionId: sectionId, index: index, value: .string(address.postcode), error: nil, identifier: _id_checkout_info_postcode, mode: .plain, data: .init(viewType: .lastItem), placeholder: InputDataInputPlaceholder(strings().checkoutInfoShippingInfoPostcode), inputPlaceholder: strings().checkoutInfoShippingInfoPostcodePlaceholder, filter: { $0 }, limit: 12))
        index += 1

    }
    
    if state.email != nil  || state.name != nil  || state.phone != nil {
        if state.address != nil {
            entries.append(.sectionId(sectionId, type: .customModern(20)))
            sectionId += 1
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().checkoutInfoReceiverInfoTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        
        struct Tuple : Equatable {
            let id: InputDataIdentifier
            let name: String
            let placeholder: String
            let value: InputDataValue
            let error: InputDataValueError?
        }
        
        var items:[Tuple] = []
        
        if let name = state.name {
            items.append(Tuple(id: _id_checkout_info_name, name: strings().checkoutInfoReceiverInfoName, placeholder: strings().checkoutInfoReceiverInfoNamePlaceholder, value: .string(name), error: state.errors[_id_checkout_info_name]))
        }
        if let email = state.email {
            items.append(Tuple(id: _id_checkout_info_email, name: strings().checkoutInfoReceiverInfoEmail, placeholder: strings().checkoutInfoReceiverInfoEmailPlaceholder, value: .string(email), error: state.errors[_id_checkout_info_email]))
        }
        if let phone = state.phone {
            items.append(Tuple(id: _id_checkout_info_phone, name: strings().checkoutInfoReceiverInfoPhone, placeholder: strings().checkoutInfoReceiverInfoPhone, value: .string(phone), error: state.errors[_id_checkout_info_phone]))
        }
        
        for item in items {
            entries.append(.input(sectionId: sectionId, index: index, value: item.value, error: item.error, identifier: item.id, mode: .plain, data: .init(viewType: bestGeneralViewType(items, for: item)), placeholder: InputDataInputPlaceholder(item.name), inputPlaceholder: item.placeholder, filter: { $0 }, limit: 255))
            index += 1
        }
    }
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_checkout_info_save_info, data: .init(name: strings().checkoutInfoSaveInfo, color: theme.colors.text, type: .switchable(state.saveInfo), viewType: .singleItem, action: arguments.toggleSaveInfo)))
    index += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().checkoutInfoSaveInfoHelp), data: InputDataGeneralTextData.init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public enum PaymentsShippingInfoFocus {
    case address
    case name
    case email
    case phone
}

public func PaymentsShippingInfoController(context: (any AccountContextProtocol), invoice: BotPaymentInvoice, source: BotPaymentInvoiceSource, formInfo: BotPaymentRequestedInfo, focus: PaymentsShippingInfoFocus?, formInfoUpdated: @escaping (BotPaymentRequestedInfo, BotPaymentValidatedFormInfo) -> Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let requestState = PaymentFormRequestState()
    let requestDisposable = MetaDisposable()
    actionsDisposable.add(requestDisposable)
    var close:(()->Void)? = nil
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }
    
    let initialState = State(address: invoice.requestedFields.contains(.shippingAddress) ? State.Address(address1: formInfo.shippingAddress?.streetLine1 ?? "", address2: formInfo.shippingAddress?.streetLine2 ?? "", city: formInfo.shippingAddress?.city ?? "", state: formInfo.shippingAddress?.state ?? "", country: formInfo.shippingAddress?.countryIso2 ?? "", postcode: formInfo.shippingAddress?.postCode ?? "") : nil, name: invoice.requestedFields.contains(.name) ? formInfo.name ?? "" : nil, email: invoice.requestedFields.contains(.email) ? formInfo.email ?? "" : nil, phone: invoice.requestedFields.contains(.phone) ? formInfo.phone ?? "" : nil, saveInfo: true, errors: [:])
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            let updated = f(current)
            if current.formInfo != updated.formInfo || current.saveInfo != updated.saveInfo {
                requestState.invalidate()
            }
            return updated
        })
    }

    let arguments = Arguments(context: context, toggleSaveInfo: {
        updateState { current in
            var current = current
            current.saveInfo = !current.saveInfo
            return current
        }
    })
    
    let signal = statePromise.get() |> deliverOnMainQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().checkoutInfoTitle)
    controller.analyticsScreen = .paymentsShippingInfo
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.willDisappear = { _ in
        requestState.suspend()
        requestDisposable.set(nil)
    }

    controller.onDeinit = {
        requestState.suspend()
        actionsDisposable.dispose()
    }
    
    controller.didAppear = { controller in
        requestState.resume()
        DispatchQueue.main.async {
            if let focus = focus {
                let id: InputDataIdentifier
                switch focus {
                case .address:
                    id = _id_checkout_info_address1
                case .name:
                    id = _id_checkout_info_name
                case .email:
                    id = _id_checkout_info_email
                case .phone:
                    id = _id_checkout_info_phone
                }
                controller.makeFirstResponderIfPossible(for: id, focusIdentifier: id)
            }
        }
    }
    
    controller.validateData = { _ in
        
        let emptyId = stateValue.with { $0.firstEmptyId }
        if let emptyId = emptyId {
            return .fail(.fields([emptyId: .shake]))
        }
        
        let state = stateValue.with { $0 }
        let formInfo = state.formInfo
        
        return .fail(.doSomething(next: { f in
            guard let controller = getController?(), stateValue.with({ $0.formInfo == formInfo && $0.saveInfo == state.saveInfo }), let requestId = requestState.begin() else { return }
            let analyticsContext = controller.analyticsContext ?? Analytics.shared.unresolvedContext()
            let presentation = analyticsContext.beginPresentation()
            defer { presentation.end() }
            let operation = MetaDisposable()
            requestDisposable.set(operation)
            let validation = showModalProgress(signal: context.engine.payments.validateBotPaymentForm(saveInfo: state.saveInfo, source: source, formInfo: formInfo), for: window) |> deliverOnMainQueue
            operation.set(analyticsContext.preservingPresentation(validation).start(next: { result in
                guard getController?() != nil, requestState.take(requestId) else { return }
                formInfoUpdated(formInfo, result)
                close?()
            }, error: { error in
                guard getController?() != nil, requestState.take(requestId) else { return }
                let text: String
                var id: InputDataIdentifier? = nil
                switch error {
                    case .shippingNotAvailable:
                        text = strings().checkoutInfoErrorShippingNotAvailable
                    case .addressStateInvalid:
                        text = strings().checkoutInfoErrorStateInvalid
                        id = _id_checkout_info_state
                    case .addressPostcodeInvalid:
                        text = strings().checkoutInfoErrorPostcodeInvalid
                        id = _id_checkout_info_postcode
                    case .addressCityInvalid:
                        text = strings().checkoutInfoErrorCityInvalid
                        id = _id_checkout_info_city
                    case .nameInvalid:
                        text = strings().checkoutInfoErrorNameInvalid
                        id = _id_checkout_info_name
                    case .emailInvalid:
                        text = strings().checkoutInfoErrorEmailInvalid
                        id = _id_checkout_info_email
                    case .phoneInvalid:
                        text = strings().checkoutInfoErrorPhoneInvalid
                        id = _id_checkout_info_phone
                    case .generic:
                        text = strings().unknownError
                }
                let alertPresentation = analyticsContext.beginPresentation()
                alert(for: window, info: text, onDeinit: { alertPresentation.end() })
                if let id = id {
                    f(.fail(.fields([id: .shake])))
                }
            }, completed: {
                _ = requestState.take(requestId)
            }))
        }))
        
    }
    
    controller.updateDatas = { data in
        updateState { current in
            var current = current
            
            current.address?.address1 = data[_id_checkout_info_address1]?.stringValue ?? ""
            current.address?.address2 = data[_id_checkout_info_address2]?.stringValue ?? ""
            current.address?.city = data[_id_checkout_info_city]?.stringValue ?? ""
            current.address?.state = data[_id_checkout_info_state]?.stringValue ?? ""
            current.address?.country = data[_id_checkout_info_country]?.stringValue ?? ""
            current.address?.postcode = data[_id_checkout_info_postcode]?.stringValue ?? ""

            
            if let value = data[_id_checkout_info_name]?.stringValue {
                current.name = value
            }
            if let value = data[_id_checkout_info_email]?.stringValue {
                current.email = value
            }
            if let value = data[_id_checkout_info_phone]?.stringValue {
                current.phone = value
            }
            current.errors = [:]
            return current
        }
        return .none
    }
    
   

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    

    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}


