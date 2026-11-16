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
import InlineStickerLayer
import AppAnalytics

private final class HeaderItem : GeneralRowItem {
    fileprivate let gift: StarGift.Gift
    fileprivate let uniqueGift: StarGift.UniqueGift
    fileprivate let valueInfo: StarGift.UniqueGift.ValueInfo
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let dismiss:()->Void
    
    fileprivate let priceLayout: TextViewLayout?
    
    public var giftFile: TelegramMediaFile {
        if !valueInfo.valueIsAverage {
            return uniqueGift.file ?? gift.file
        } else {
            return gift.file
        }
    }
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, gift: StarGift.Gift, uniqueGift: StarGift.UniqueGift, valueInfo: StarGift.UniqueGift.ValueInfo, context: (any AccountContextProtocol), dismiss:@escaping()->Void) {
        self.gift = gift
        self.uniqueGift = uniqueGift
        self.valueInfo = valueInfo
        self.context = context
        self.dismiss = dismiss
        
        let text: String
        
        text = formatCurrencyAmount(valueInfo.value, currency: valueInfo.currency)
        
        let priceLayout = TextViewLayout(.initialize(string: text, color: theme.colors.underSelectedColor, font: .avatar(20)), alignment: .center)
        priceLayout.measure(width: .greatestFiniteMagnitude)

        self.priceLayout = priceLayout

        
        super.init(initialSize, stableId: stableId)
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
    
    override var accessibilityLabel: String? {
        return uniqueGift.title
    }
    
    override var accessibilityValue: String? {
        return priceLayout?.attributedString.string
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 120
        
        if let _ = priceLayout {
            height += 55
        }
        return height
    }
}

private final class HeaderItemView : GeneralRowView {
    fileprivate let mediaView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 100, 100))
    fileprivate let dismiss = ImageButton()
    fileprivate let privateView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(mediaView)
        addSubview(dismiss)
        addSubview(privateView)
        
        privateView.userInteractionEnabled = false
        privateView.isSelectable = false
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)
        
        
        self.privateView.isHidden = item.priceLayout == nil
        
        if let priceLayout = item.priceLayout {
            self.privateView.update(priceLayout)
            self.privateView.setFrameSize(NSMakeSize(priceLayout.layoutSize.width + 20, priceLayout.layoutSize.height + 15))
        }
        self.privateView.backgroundColor = theme.colors.accent
        self.privateView.layer?.cornerRadius = self.privateView.frame.height / 2
        (mediaView as? StarsStickerView)?.updateStarsSticker(file: item.giftFile, size: mediaView.frame.size, context: item.context, colors: [], playback: .standard, animated: animated)
    }
    
    public override func layout() {
        super.layout()
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
        mediaView.centerX(y: 20)
        self.privateView.centerX(y: mediaView.frame.maxY + 10)
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss:()->Void
    public let openMarket:()->Void
    public init(context: (any AccountContextProtocol), dismiss:@escaping()->Void, openMarket:@escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.openMarket = openMarket
    }
}

private struct State : Equatable {
    public var gift: StarGift.Gift
    public var uniqueGift: StarGift.UniqueGift
    public var valueInfo: StarGift.UniqueGift.ValueInfo
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, gift: state.gift, uniqueGift: state.uniqueGift, valueInfo: state.valueInfo, context: arguments.context, dismiss: arguments.dismiss)
    }))
    
 
    let suffixText: String
    if state.valueInfo.isLastSaleOnFragment {
        suffixText = strings().starGiftValueSourceFragment
    } else {
        suffixText = strings().starGiftValueSourceTelegram
    }

    let text: String
    if state.valueInfo.valueIsAverage {
        text = strings().starGiftValueDescriptionAverage(state.uniqueGift.title)
    } else {
        let fullTitle = state.uniqueGift.title + " #\(state.uniqueGift.number)"
        text = strings().starGiftValueDescriptionLastSale(fullTitle, suffixText)
    }

    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: .init(color: theme.colors.text, viewType: .textBottomItem, fontSize: 13, centerViewAlignment: true, alignment: .center)))
    index += 1


    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    var rows: [InputDataTableBasedItem.Row] = []

    rows.append(.init(left: .init(.initialize(string: "Initial Sale", color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: stringForFullDate(timestamp: state.valueInfo.initialSaleDate), color: theme.colors.text, font: .normal(.text))))))

    rows.append(.init(left: .init(.initialize(string: "Initial Price", color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: "\(state.valueInfo.initialSaleStars) (~\(formatCurrencyAmount(state.valueInfo.initialSalePrice, currency: state.valueInfo.currency)))", color: theme.colors.text, font: .normal(.text))), leftView: { previous in
        let control: ImageView
        if let previous = previous as? ImageView {
            control = previous
        } else {
            control = ImageView(frame: NSMakeRect(0, 0, 20, 20))
        }
        control.image = TelegramThemeHooks.shared.image(.iconStarCurrency).precomposed()
        control.setAccessibilityLabel(strings().voiceOverCommonStars)
        return control
    })))

    
    if let lastSaleDate = state.valueInfo.lastSaleDate {
        rows.append(.init(left: .init(.initialize(string: "Last Sale", color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: stringForFullDate(timestamp: lastSaleDate), color: theme.colors.text, font: .normal(.text))))))
    }
    
    _ = state.valueInfo.lastSalePrice
    

    if let lastSalePrice = state.valueInfo.lastSalePrice, !state.valueInfo.valueIsAverage {
        let difference = lastSalePrice - state.valueInfo.initialSalePrice
        var badge: InputDataTableBasedItem.Row.Right.Badge? = nil
        
        if difference > 0 {
            let percentIncrease = (CGFloat(difference) / CGFloat(state.valueInfo.initialSalePrice)) * 100
            let formattedPercent = String(format: "+%.0f%%", percentIncrease)
            badge = .init(text: formattedPercent, callback: { })
        }
        rows.append(.init(left: .init(.initialize(string: "Last Price", color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: formatCurrencyAmount(lastSalePrice, currency: state.valueInfo.currency), color: theme.colors.text, font: .normal(.text))), badge: badge)))
    } else if let averagePrice = state.valueInfo.averagePrice {
        let currency = formatCurrencyAmount(averagePrice, currency: state.valueInfo.currency)
        let tooltip = "\(currency) is the average sale price of \(state.uniqueGift.title)s on Telegram and Fragment over the past month."

        
        rows.append(.init(left: .init(.initialize(string: "Average Price", color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: currency, color: theme.colors.text, font: .normal(.text))), badge: .init(text: "?", tooltipText: tooltip, callback: { }))))
    }
    

    if let floorPrice = state.valueInfo.floorPrice {
        let currency = formatCurrencyAmount(floorPrice, currency: state.valueInfo.currency)
        
        let tooltip = "\(currency) is the floor price for \(state.uniqueGift.title) gifts listed on Telegram and Fragment."
        
        rows.append(.init(left: .init(.initialize(string: "Minimum Price", color: theme.colors.text, font: .normal(.text))), right: .init(name: .init(.initialize(string: currency, color: theme.colors.text, font: .normal(.text))), badge: .init(text: "?", tooltipText: tooltip, callback: { }))))
    }
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("data"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: rows, context: arguments.context)
    }))
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    
    let linkExecutor = LinkHooks.shared.globalLinkExecutor()
    linkExecutor.processURL = { url in
        if let link = LinkHooks.shared.linkPayload(url) {
            if link == "telegram" {
                arguments.openMarket()
            } else {
                LinkHooks.shared.openAnyLink(url)
            }
        } else {
            LinkHooks.shared.openAnyLink(url)
        }
    }
    
    if let listedCount = state.valueInfo.listedCount {
        let telegram = NSMutableAttributedString()
        telegram.append(
            string: strings().starGiftValueListingTelegram(
                Int(listedCount),
                clown
            ),
            color: theme.colors.accent,
            font: .normal(.title)
        )
        telegram.add(link: LinkHooks.shared.externalLink("telegram", false), for: telegram.range)
        telegram.insertEmbedded(.embeddedAnimated(state.gift.file), for: clown)
        
        entries.append(.desc(
            sectionId: sectionId,
            index: index,
            text: .attributed(telegram),
            data: .init(
                color: theme.colors.accent,
                viewType: .textBottomItem,
                centerViewAlignment: true,
                alignment: .center,
                context: arguments.context,
                linkExecutor: linkExecutor
            )
        ))
        index += 1
    }

    if let listedCount = state.valueInfo.fragmentListedCount,
       let fragmentUrl = state.valueInfo.fragmentListedUrl {
        
        if state.valueInfo.listedCount != nil {
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
        }
        
        let fragment = NSMutableAttributedString()
        fragment.append(
            string: strings().starGiftValueListingFragment(
                Int(listedCount),
                clown
            ),
            color: theme.colors.accent,
            font: .normal(.title)
        )
        fragment.add(link: LinkHooks.shared.externalLink(fragmentUrl, false), for: fragment.range)
        fragment.insertEmbedded(.embeddedAnimated(state.gift.file), for: clown)
        
        entries.append(.desc(
            sectionId: sectionId,
            index: index,
            text: .attributed(fragment),
            data: .init(
                color: theme.colors.accent,
                viewType: .textBottomItem,
                centerViewAlignment: true,
                alignment: .center,
                context: arguments.context,
                linkExecutor: linkExecutor
            )
        ))
        index += 1
    }

   

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    
    return entries
}

public func StarGift_NftValue_Controller(context: (any AccountContextProtocol), gift: StarGift.Gift, uniqueGift: StarGift.UniqueGift, valueInfo: StarGift.UniqueGift.ValueInfo) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(gift: gift, uniqueGift: uniqueGift, valueInfo: valueInfo)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, openMarket: {
        closeAllModals(window: window)
        showModal(with: StarGift_MarketplaceController(context: context, peerId: context.peerId, gift: gift), for: window)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .giftsValue
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

//    let modalInteractions = ModalInteractions(acceptTitle: "PAY", accept: { [weak controller] in
//        _ = controller?.returnKeyAction()
//    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: nil)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}




