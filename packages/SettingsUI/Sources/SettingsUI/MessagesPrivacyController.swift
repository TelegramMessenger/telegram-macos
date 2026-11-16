import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import AppAnalytics


private final class Arguments {
    let context: any AccountContextProtocol
    let alert:()->Void
    let premium:()->Void
    let toggle:(GlobalPrivacySettings.NonContactChatsPrivacy)->Void
    let updatePrice: (Int64) -> Void
    let editPrice: (Double) -> Void
    let paidMessagesExceptions:()->Void
    init(context: any AccountContextProtocol, alert:@escaping()->Void, premium:@escaping()->Void, toggle:@escaping(GlobalPrivacySettings.NonContactChatsPrivacy)->Void, updatePrice: @escaping (Int64) -> Void, editPrice: @escaping (Double) -> Void, paidMessagesExceptions:@escaping()->Void) {
        self.context = context
        self.premium = premium
        self.alert = alert
        self.toggle = toggle
        self.updatePrice = updatePrice
        self.editPrice = editPrice
        self.paidMessagesExceptions = paidMessagesExceptions
    }
}

private struct State : Equatable {
    var globalSettings: GlobalPrivacySettings
    var isPremium: Bool
    var noPaidMessages: SelectivePrivacySettings
}

private let _id_everyone = InputDataIdentifier("_id_everyone")
private let _id_contacts = InputDataIdentifier("_id_contacts")
private let _id_charge = InputDataIdentifier("_id_charge")
private let _id_charge_price = InputDataIdentifier("_id_charge_price")
private let _id_exceptions = InputDataIdentifier("_id_exceptions")
private let _id_price_input = InputDataIdentifier("_id_price_input")

private struct MessagePriceScale {
    let maximum: Int64
    private let anchors: [Int64]

    init(configuredMaximum: Double) {
        let maximum = Int64(max(1, Int32(exactly: configuredMaximum) ?? 10_000))
        self.maximum = maximum
        self.anchors = [1, 10, 50, 100, 500, 1_000, 2_000, 5_000, 7_500, 10_000].filter { $0 < maximum } + [maximum]
    }

    func position(for price: Int64) -> CGFloat {
        let segmentCount = anchors.count - 1
        guard segmentCount > 0 else {
            return 0
        }
        let price = min(max(price, 1), maximum)
        for index in 0 ..< segmentCount where price <= anchors[index + 1] {
            let fraction = CGFloat(price - anchors[index]) / CGFloat(anchors[index + 1] - anchors[index])
            return (CGFloat(index) + fraction) / CGFloat(segmentCount)
        }
        return 1
    }

    func price(at position: CGFloat) -> Int64 {
        guard position.isFinite, position > 0 else {
            return 1
        }
        guard position < 1, anchors.count > 1 else {
            return maximum
        }

        let segmentCount = anchors.count - 1
        let offset = position * CGFloat(segmentCount)
        let index = min(Int(offset), segmentCount - 1)
        let price = CGFloat(anchors[index]) + (offset - CGFloat(index)) * CGFloat(anchors[index + 1] - anchors[index])
        let step: CGFloat
        switch price {
        case ..<100: step = 1
        case ..<500: step = 5
        case ..<1_000: step = 10
        case ..<5_000: step = 25
        default: step = 50
        }
        return min(maximum, Int64((price / step).rounded() * step))
    }

    static func allowsReplacementText(_ text: String) -> Bool {
        return text.utf8.allSatisfy { (48 ... 57).contains($0) }
    }

    func exactPrice(from text: String) -> Int64? {
        guard let price = parsedPrice(from: text), (1 ... maximum).contains(price) else {
            return nil
        }
        return price
    }

    func correctedInput(_ text: String) -> String {
        guard let price = parsedPrice(from: text) else {
            return text
        }
        if price > maximum {
            return String(maximum)
        }
        return String(text.drop(while: { $0 == "0" }))
    }

    func exceedsMaximum(_ text: String) -> Bool {
        return parsedPrice(from: text).map { $0 > maximum } ?? false
    }

    private func parsedPrice(from text: String) -> Int64? {
        guard !text.isEmpty, Self.allowsReplacementText(text) else {
            return nil
        }
        var price: Int64 = 0
        for digit in text.utf8 {
            price = min(maximum + 1, price * 10 + Int64(digit - 48))
        }
        return price
    }
}

private func showMessagePriceEditor(window: Window, scale: MessagePriceScale, commission: Double, apply: @escaping (Int64) -> Void) {
    let title = strings().messagesPrivacyControllerPriceForEachMessage
    let star = TelegramThemeHooks.shared.image(.iconStarCurrency).precomposed(zoom: 0.75)
    let payout = strings().starNftSellInfo("\(commission.string)%")
    let entries: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .desc(sectionId: 1, index: 0, text: .plain(strings().starNftSellHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
        .input(sectionId: 1, index: 1, value: .string(""), error: nil, identifier: _id_price_input, mode: .plain, data: .init(viewType: .singleItem, allowsReplacementText: MessagePriceScale.allowsReplacementText, shouldShakeOnFilterCorrection: scale.exceedsMaximum), placeholder: .init(icon: star, centersIconVertically: true), inputPlaceholder: title, filter: scale.correctedInput, limit: 10_000),
        .desc(sectionId: 1, index: 2, text: .markdown(payout, linkHandler: { _ in }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
        .sectionId(1, type: .normal)
    ]

    var close: (() -> Void)?
    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: title, validateData: { data in
        guard let text = data[_id_price_input]?.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }
        guard let price = scale.exactPrice(from: text) else {
            return .fail(.alert(strings().messagesPrivacyControllerEnterWholeNumber(Int(scale.maximum))))
        }
        return .success(.custom {
            apply(price)
            close?()
        })
    })
    controller.autoInputAction = true

    let interactions = ModalInteractions(acceptTitle: strings().modalOK, accept: { [weak controller] in
        controller?.validateInputValues()
    }, height: 70, inset: 10, singleButton: true)
    controller.didAppear = { [weak controller] _ in
        controller?.updateInputValues()
    }
    controller.updateDatas = { [weak interactions] data in
        let text = data[_id_price_input]?.stringValue ?? ""
        interactions?.updateEnables(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return .none
    }
    let modalController = InputDataModalController(controller, modalInteractions: interactions)
    close = { [weak modalController] in
        modalController?.close()
    }
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        close?()
    })
    showModal(with: modalController, for: window)
}

private func entries(_ state: State, arguments: Arguments, priceScale: MessagePriceScale) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().privacySettingsMessagesHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_everyone, data: .init(name: strings().privacySettingsMessagesEveryone, color: theme.colors.text, type: .selectable(state.globalSettings.nonContactChatsPrivacy == .everybody), viewType: .firstItem, action: {
        arguments.toggle(.everybody)
    })))
    
    let new_noncontact_peers_require_premium_without_ownpremium = arguments.context.appConfiguration.getBoolValue("new_noncontact_peers_require_premium_without_ownpremium", orElse: false)
    
    let isAvailable = state.isPremium || new_noncontact_peers_require_premium_without_ownpremium
    let paidAvailable = arguments.context.appConfiguration.getBoolValue("stars_paid_messages_available", orElse: false)

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_contacts, data: .init(name: strings().privacySettingsMessagesContacts, color: theme.colors.text, type: state.globalSettings.nonContactChatsPrivacy == .requirePremium ? .selectable(true) : isAvailable ? .selectable(false) : .image(theme.icons.premium_lock_gray), viewType: paidAvailable ? .innerItem : .lastItem, action: {
        if isAvailable {
            arguments.toggle(.requirePremium)
        } else {
            arguments.alert()
        }
    })))
        
    let paidMessages: Bool
    switch state.globalSettings.nonContactChatsPrivacy {
    case .paidMessages:
        paidMessages = true
    default:
        paidMessages = false
    }
    
    
    if paidAvailable {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_charge, data: .init(name: strings().messagesPrivacyChargeforMessages, color: theme.colors.text, type: isAvailable ? .selectable(paidMessages) : .image(theme.icons.premium_lock_gray), viewType: .lastItem, action: {
            if isAvailable {
                arguments.toggle(.paidMessages(.init(value: min(10, priceScale.maximum), nanos: 0)))
            } else {
                arguments.alert()
            }
        })))
        
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().messagesPrivacyChargeforMessagesInfo, linkHandler: { _ in
            arguments.premium()
        }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
    }
   
    
    let commission = arguments.context.appConfiguration.getGeneralValue("stars_paid_message_commission_permille", orElse: 850).decemial

    
    switch state.globalSettings.nonContactChatsPrivacy {
    case let .paidMessages(stars):
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().messagesPrivacyChargeforMessagesSelectHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        let displayedPrice = strings().starListItemCountOther(Int(stars.value)).replacingOccurrences(of: String(stars.value), with: stars.value.formattedWithSeparator)
        let priceInUsd = "\(Double(stars.value) * 0.013)".prettyCurrencyNumberUsd
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_charge_price, equatable: .init(stars), comparable: nil, item: { initialSize, stableId in
            return PrecieSliderRowItem(initialSize, stableId: stableId, current: priceScale.position(for: stars.value), markers: ["1", String(priceScale.maximum)], showValue: displayedPrice, valueDetail: "~$\(priceInUsd)", editValue: {
                arguments.editPrice(commission)
            }, update: { position in
                arguments.updatePrice(priceScale.price(at: position))
            }, viewType: .singleItem)
        }))
        index += 1

        let amount = "\(Double(stars.value) * 0.013 * (commission / 100))".prettyCurrencyNumberUsd

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().messagesPrivacyChargeforMessagesSelectInfo("\(commission.string)%", amount)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().messagesPrivacyChargeforMessagesExceptions), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        
        var enabledFor: [PeerId: SelectivePrivacyPeer] = [:]
        
        switch state.noPaidMessages {
        case let .enableContacts(_enableFor, _, _, _):
            enabledFor = _enableFor
        default:
            break
        }

        let count = countForSelectivePeers(enabledFor)
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_exceptions, data: .init(name: strings().messagesPrivacyChargeforMessagesExceptionsRemoveFee, color: theme.colors.text, type: .nextContext(count > 0 ?  "\(countForSelectivePeers(enabledFor))" : ""), viewType: .singleItem, action: arguments.paidMessagesExceptions)))

        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().messagesPrivacyChargeforMessagesExceptionsInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    default:
        break
    }
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func MessagesPrivacyController<Context: AccountContextProtocol>(context: Context, noPaidMessages: SelectivePrivacySettings, globalSettings: GlobalPrivacySettings, updated:@escaping(SelectivePrivacySettings, GlobalPrivacySettings)->Void) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State(globalSettings: globalSettings, isPremium: context.isPremium, noPaidMessages: noPaidMessages)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let priceScale = MessagePriceScale(configuredMaximum: context.appConfiguration.getGeneralValueDouble("stars_paid_message_amount_max", orElse: 10_000))
    let updatePrice: (Int64) -> Void = { price in
        updateState { current in
            guard case let .paidMessages(amount) = current.globalSettings.nonContactChatsPrivacy, amount.value != price else {
                return current
            }
            var current = current
            current.globalSettings.nonContactChatsPrivacy = .paidMessages(.init(value: price, nanos: 0))
            return current
        }
    }

    let arguments = Arguments(context: context, alert: {
        if !context.isPremium {
            showModalText(for: context.window, text: strings().privacySettingsMessagesPremiumError, button: strings().alertLearnMore, callback: { _ in
                SettingsNavigationHooks.shared.showPremiumBoarding(context, .messagePrivacy, true, context.window, nil)
            })
            return
        }
    }, premium: {
        SettingsNavigationHooks.shared.showPremiumBoarding(context, .messagePrivacy, true, context.window, nil)
    }, toggle: { value in
        updateState { current in
            var current = current
            current.globalSettings.nonContactChatsPrivacy = value
            return current
        }
    }, updatePrice: updatePrice, editPrice: { commission in
        guard case .paidMessages = stateValue.with({ $0 }).globalSettings.nonContactChatsPrivacy else {
            return
        }
        showMessagePriceEditor(window: context.window, scale: priceScale, commission: commission, apply: updatePrice)
    }, paidMessagesExceptions: {
        
        let state = stateValue.with { $0 }
        
        let initialPeers: [PeerId: SelectivePrivacyPeer]
        switch state.noPaidMessages {
        case let .enableContacts(enableFor, _, _, _):
            initialPeers = enableFor
        default:
            initialPeers = [:]
        }
        
        context.bindings.rootNavigation().push(SelectivePrivacySettingsPeersController(context, title: strings().privacySettingsControllerRemoveFee, initialPeers: initialPeers, premiumUsers: nil, enableForBots: nil, feeExceptions: true, updated: { updatedPeerIds in
            updateState { current in
                var current = current
                current.noPaidMessages = .enableContacts(enableFor: updatedPeerIds, disableFor: [:], enableForPremium: false, enableForBots: false)
                return current
            }
        }))
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments, priceScale: priceScale))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().privacySettingsMessages, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .settingsPrivacyMessages
    
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.afterDisappear = {
        let state = stateValue.with { $0 }
        if state != initialState {
            updated(state.noPaidMessages, state.globalSettings)
        }
        if state.globalSettings != initialState.globalSettings {
            _ = context.engine.privacy.updateGlobalPrivacySettings(settings: state.globalSettings).start()
        }
    }

    return controller
    
}
