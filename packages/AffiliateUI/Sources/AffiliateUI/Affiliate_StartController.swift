import Cocoa
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
import AvatarUI
import AlertsUI
import LocalAnimations
import SceneEffects
import ObjcUtils
import AppAnalytics

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let updateCommission:(Int32)->Void
    public let updateCommission2:(Int32)->Void
    public let updateDuration:(Int32)->Void
    public let viewExisting:()->Void
    public let end:()->Void
    public init(context: (any AccountContextProtocol), updateCommission:@escaping(Int32)->Void, updateCommission2:@escaping(Int32)->Void, updateDuration: @escaping(Int32)->Void, viewExisting:@escaping()->Void, end:@escaping()->Void) {
        self.context = context
        self.updateCommission = updateCommission
        self.updateDuration = updateDuration
        self.viewExisting = viewExisting
        self.updateCommission2 = updateCommission2
        self.end = end
    }
}

private struct State : Equatable {
    public var commission: Int32 = 110
    public var commission2: Int32 = 0
    public var duration: Int32 = 6
    
    public var current: TelegramStarRefProgram?
    
    public var mappedCommission: Int32 {
        return Int32(mappingRange(Double(self.commission), 0, 1000, 10, 900))
    }
    
    public var currentCommission: Int32 {
        return Int32(mappingRange(Double(self.commission), 0, 1000, 10, 900) / 10)
    }
}


private let _id_header = InputDataIdentifier("_id_header")
private let _id_promo = InputDataIdentifier("_id_promo")
private let _id_commission = InputDataIdentifier("_id_commission")
private let _id_commission_2 = InputDataIdentifier("_id_commission_2")
private let _id_duration = InputDataIdentifier("_id_duration")

private let _id_view_existing = InputDataIdentifier("_id_view_existing")
private let _id_end = InputDataIdentifier("_id_end")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return Affiliate_HeaderItem(initialSize, stableId: stableId, context: arguments.context, presentation: theme, peer: arguments.context.myPeer, title: strings().affiliateSetupTitleNew, info: strings().affiliateSetupHeaderInfo, detectBold: false, viewType: .legacy)
    }))
  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_promo, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return Affiliate_PromoItem(initialSize, stableId: stableId, context: arguments.context, options: [
            .init(image: TelegramThemeHooks.shared.image(.iconBotAffiliateStar).precomposed(theme.colors.accent), title: strings().affiliateSetupIntroNewTitle1, text: strings().affiliateSetupIntroNewText1),
            .init(image: TelegramThemeHooks.shared.image(.iconBotAffiliateChannel).precomposed(theme.colors.accent), title: strings().affiliateSetupIntroNewTitle2, text: strings().affiliateSetupIntroNewText2),
            .init(image: TelegramThemeHooks.shared.image(.iconBotAffiliateLink).precomposed(theme.colors.accent), title: strings().affiliateSetupIntroNewTitle3, text: strings().affiliateSetupIntroNewText3)
        ])
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().affiliateSetupSectionCommission), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_commission, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return PrecieSliderRowItem(initialSize, stableId: stableId, current: Double(state.commission) / 1000.0, magnit: [], markers: ["1%", "90%"], showValue: "\(state.currentCommission)%", update: { value in
            arguments.updateCommission(Int32(value * 1000))
        }, viewType: .singleItem)
    }))
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().affiliateSetupSectionCommissionFooter), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    
    
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
//    
//    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("COMMISSION FOR 2-LEVEL AFFILIATES"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
//    index += 1
//    
//    
//    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_commission_2, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
//        let values: [Int32] = [0, 5, 10, 15, 20, 30, 50, 90]
//        return SelectSizeRowItem(initialSize, stableId: stableId, current: state.commission2, sizes: values, hasMarkers: false, titles:  values.map {"\($0)%"}, viewType: .singleItem, selectAction: { selected in
//            arguments.updateCommission2(values[selected])
//        })
//    }))
//    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("Set the percentage of star revenue earned by affiliates who refer other affiliates that bring users to your bot."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
//    index += 1
//    

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
        
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().affiliateDuration), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem, rightItem: .init(isLoading: false, text: .initialize(string: strings().affiliateDurationOneYear, color: theme.colors.listGrayText, font: .normal(.small))))))
    index += 1
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_duration, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        let values: [Int32] = [1, 3, 6, 12, 24, 36, .max]
        
        let titles: [String] = values.map { value in
            if value < 12 {
                return "\(value)m"
            } else if value != .max {
                return "\(value / 12)y"
            } else {
                return "∞"
            }
        }
        
        return SelectSizeRowItem(initialSize, stableId: stableId, current: state.duration, sizes: values, hasMarkers: false, titles:  titles, viewType: .singleItem, selectAction: { selected in
            arguments.updateDuration(values[selected])
           // arguments.updateAwayPeriod(values[selected])
        })
    }))
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().affiliateSetupSectionDurationFooter), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_view_existing, data: .init(name: strings().affiliateSetupExistingProgramsAction, color: theme.colors.text, type: .next, viewType: .singleItem, action: arguments.viewExisting)))
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().affiliateSetupExistingProgramsFooter), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    // entries
    
        
    if state.current != nil, state.current?.endDate == nil {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_end, data: .init(name: strings().affiliateSetupEndAction, color: theme.colors.redUI, viewType: .singleItem, action: arguments.end)))
    }
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func Affiliate_StartController(context: (any AccountContextProtocol), peerId: PeerId, starRefProgram: TelegramStarRefProgram?) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let commissionPermille: Int32
    if let starRefProgram {
        commissionPermille = Int32(ceil(mappingRange(Double(starRefProgram.commissionPermille), 10, 900, 0, 100)))
    } else {
        commissionPermille = Int32(ceil(mappingRange(100, 10, 900, 0, 1000)))
    }
    
    let initialState = State(commission: commissionPermille, duration: starRefProgram?.durationMonths ?? 3, current: starRefProgram)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, updateCommission: { value in
        updateState { current in
            var current = current
            if let starRefProgram {
                current.commission = max(starRefProgram.commissionPermille, value)
            } else {
                current.commission = value
            }
            return current
        }
    }, updateCommission2: { value in
        updateState { current in
            var current = current
            current.commission2 = value
            return current
        }
    }, updateDuration: { value in
        updateState { current in
            var current = current
            if let starRefProgram {
                current.duration = max(starRefProgram.durationMonths ?? .max, value)
            } else {
                current.duration = value
            }
            return current
        }
    }, viewExisting: {
        context.bindings.rootNavigation().push(Affiliate_PeerController(context: context, peerId: peerId, onlyDemo: true))
    }, end: {
                
        verifyAlert(for: window, header: strings().affiliateSetupAlertTerminateTitle, information: strings().affiliateSetupAlertTerminateText, ok: strings().affiliateSetupAlertTerminateAction, successHandler: { _ in
            _ = context.engine.peers.updateStarRefProgram(id: peerId, program: nil).start()
            showModalText(for: window, text: strings().affiliateSetupToastTerminatedText, title: strings().affiliateSetupToastTerminatedTitle)
            context.bindings.rootNavigation().back()
            //Affiliate program ended
            //Participating affiliates have been notified. All referral links will be disabled in 24 hours.
        })
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().affiliateSetupTitleNew, removeAfterDisappear: false, doneString: { starRefProgram == nil ? strings().affiliateStart : strings().affiliateUpdate })
    controller.analyticsScreen = .peerInfoAffiliateProgram
    
    controller.validateData = { _ in
        return .fail(.doSomething(next: { next in
            
            let endDate = starRefProgram?.endDate ?? 0
            
            if endDate == 0 || endDate < context.timestamp {
                
                let info = strings().affiliateSetupAlertApplyText;
                
                var rows: [InputDataTableBasedItem.Row] = []
                let comission = stateValue.with { $0.mappedCommission }
                _ = stateValue.with { $0.commission2 }
                let duration = stateValue.with { $0.duration }
                
                rows.append(.init(left: .init(.initialize(string: strings().affiliateSetupAlertApplySectionCommission, color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: "\(comission.decemial)%", color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1))))
//
//                if comission2 > 0 {
//                    rows.append(.init(left: .init(.initialize(string: "Commission for\n2-Level Affiliates", color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: "\(comission2)%", color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1))))
//
//                }
                
                let localizedDuration = duration < 12 ? strings().timerMonthsOther(Int(duration)) : duration == .max ? strings().affiliateProgramDurationLifetime : strings().timerYearsOther(Int(duration))
                
                rows.append(.init(left: .init(.initialize(string: strings().affiliateSetupAlertApplySectionDuration, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1), right: .init(name: .init(.initialize(string: localizedDuration, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1))))

                
                let data = ModalAlertData(title: strings().affiliateSetupAlertApplyTitle, info: info, description: nil, ok: starRefProgram != nil ? strings().affiliateSetupUpdate : strings().affiliateSetupStart, options: [], mode: .confirm(text: strings().modalCancel, isThird: false), footer: .init(id: "footer", value: { initialSize, stableId, presentation, _ in
                    return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .legacy, rows: rows, context: arguments.context)
                }))
                
                showModalAlert(for: window, data: data, completion: { result in
                    _ = context.engine.peers.updateStarRefProgram(id: peerId, program: (comission, duration == .max ? nil : duration)).start()
                    showModalText(for: window, text: strings().affiliateSetupToastStartedText)
                    next(.success(.navigationBack))
                })
            } else {
                alert(for: window, info: strings().affiliateProgramStartDelay(stringForFullDate(timestamp: endDate)))
            }
            
        }))
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
    
}

