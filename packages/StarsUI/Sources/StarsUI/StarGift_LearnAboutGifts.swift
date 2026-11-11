import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView
import AppAnalytics


private final class HeaderItem : GeneralRowItem {
    fileprivate let state: State
    fileprivate let arguments: Arguments
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments) {
        self.state = state
        self.arguments = arguments
        super.init(initialSize, stableId: stableId)
    }

    public override var accessibilityLabel: String? {
        return strings().starGiftLearnAboutTitle
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
    
    public override var height: CGFloat {
        return 350
    }
}

private final class HeaderItemView : GeneralRowView {
    public let view = PremiumDemoLegacyPhoneView(frame: .zero)
    public let headerView = PremiumGradientView(frame: .zero)
    public let dismiss: ImageButton = ImageButton()
    public let decorationView: (NSView & PremiumDecorationProtocol)

    public required init(frame frameRect: NSRect) {
        decorationView = BadgeStarsView(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        addSubview(headerView)
        addSubview(decorationView)
        addSubview(view)
        addSubview(dismiss)
        
        decorationView.setVisible(true)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? HeaderItem else {
            return
        }
        view.setup(context: item.arguments.context, video: item.state.config.videos["gifts"], position: .top)

        
        
        dismiss.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(.white), for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.scaleOnClick = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.arguments.dismiss()
        }, for: .Click)
    }
    
    public override func layout() {
        super.layout()
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
        decorationView.frame = bounds
        view.frame = bounds
        headerView.frame = bounds
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss: ()->Void
    public init(context: (any AccountContextProtocol), dismiss: @escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
    }
}

private struct State : Equatable {
    public var config: PremiumPromoConfiguration = .defaultValue
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, state: state, arguments: arguments)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("**\(strings().starGiftLearnAboutTitle)**"), data: .init(color: theme.colors.text, detectBold: true, viewType: .plain(.single), fontSize: 18, centerViewAlignment: true, alignment: .center)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starGiftLearnAboutDescription), data: .init(color: theme.colors.listGrayText, viewType: .plain(.single), fontSize: 13, centerViewAlignment: true, alignment: .center)))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    
    let title1 = strings().giftUpgradeUniqueTitle
    let info1 = strings().giftUpgradeUniqueDescription
    
    let title2 = strings().giftUpgradeTransferableTitle
    let info2 = strings().giftUpgradeTransferableDescription
    
    let title3 = strings().giftUpgradeTradableTitle
    let info3 = strings().giftUpgradeUniqueDescription
    
    let image1 = TelegramThemeHooks.shared.image(.iconNFTUnique)
    let image2 = TelegramThemeHooks.shared.image(.iconNFTTransferable)
    let image3 = TelegramThemeHooks.shared.image(.iconNFTTradable)
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("options"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return GeneralOptionsRowItem(initialSize, stableId: stableId, input: [
            .init(image: image1, title: title1, info: info1),
            .init(image: image2, title: title2, info: info2),
            .init(image: image3, title: title3, info: info3)
        ])
    }))
  
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func StarGift_LearnAboutGifts(context: (any AccountContextProtocol)) -> InputDataModalController {
    
    

    let actionsDisposable = DisposableSet()

    let initialState = State()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let premiumPromo = context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.PremiumPromo())
    |> deliverOnMainQueue
    
    
    actionsDisposable.add(premiumPromo.startStrict(next: { value in
        updateState { current in
            var current = current
            current.config = value
            return current
        }
    }))
    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil

    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .giftsAbout
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().monetizationIntroUnderstood, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    modalController._hasBorder = false
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}


