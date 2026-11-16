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

private final class BoostText : GeneralRowItem {
    fileprivate let textLayout: TextViewLayout
    fileprivate let context: (any AccountContextProtocol)
    public init(_ initialSize: NSSize, stableId: AnyHashable, count: Int, context: (any AccountContextProtocol)) {
        let attr = NSMutableAttributedString()
        
        let perSentGift = context.appConfiguration.getGeneralValue("boosts_per_sent_gift", orElse: 4)
        _ = attr.append(string: strings().premiumGiftReceiveBoost("\(clown)\(Int32(count) * perSentGift)"), color: theme.colors.text, font: .normal(.text))

        let range = attr.string.nsstring.range(of: clown)
        attr.replaceCharacters(in: range, with: NSAttributedString.embedded(name: "Icon_Boost_Lighting_Small", color: theme.colors.accent, resize: false))
        attr.addAttribute(.font, value: NSFont.medium(.text), range: NSMakeRange(range.max, attr.length - range.max))
        //attr.detectBoldColorInString(with: .medium(.text))

        self.context = context
        self.textLayout = .init(attr, maximumNumberOfLines: 1, alignment: .center)
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: .greatestFiniteMagnitude)
        return true
    }
    
    public override var height: CGFloat {
        return 30
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return BoostTextView.self
    }
}

private final class BoostTextView: GeneralRowView {
    private let textView = TextView()
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineStickerItemLayer] = [:]

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? BoostText else {
            return
        }
        textView.update(item.textLayout)
        updateInlineStickers(context: item.context, view: textView, textLayout: item.textLayout)
    }
    
    public func updateInlineStickers(context: (any AccountContextProtocol), view textView: TextView, textLayout: TextViewLayout) {
        var validIds: [InlineStickerItemLayer.Key] = []
        var index: Int = textView.hashValue

        
        for item in textLayout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem, case let .attribute(emoji) = stickerItem.source {
                
                let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index)
                validIds.append(id)
                
                
                var rect: NSRect
                if textLayout.isBigEmoji {
                    rect = item.rect
                } else {
                    rect = item.rect.insetBy(dx: -2, dy: -2)
                }
                if StarsHooks.shared.isBubbledServiceItem(self.item) {
                    rect = rect.offsetBy(dx: 9, dy: 2)
                }
                
                let view: InlineStickerItemLayer
                if let current = self.inlineStickerItemViews[id], current.frame.size == rect.size {
                    view = current
                } else {
                    self.inlineStickerItemViews[id]?.removeFromSuperlayer()
                    view = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, textColor: theme.colors.accent)
                    self.inlineStickerItemViews[id] = view
                    view.superview = textView
                    textView.addEmbeddedLayer(view)
                }
                index += 1
                view.isPlayable = true
                view.frame = rect
            }
        }
        
        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
        }
    }
    
    public override func layout() {
        super.layout()
        textView.centerX(y: frame.height - textView.frame.height)
    }
    
}

private final class HeaderStarRowItem : GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peers: [EnginePeer]
    fileprivate let badge: BadgeNode?
    fileprivate let isGifted: Bool
    fileprivate let extraCount: Int
    public init(_ initialSize: NSSize, stableId: AnyHashable, peers: [EnginePeer], context: (any AccountContextProtocol), isGifted: Bool) {
        self.context = context
        self.isGifted = isGifted
        self.extraCount = peers.count - 3
        if peers.count > 3, !isGifted {
            let under = theme.colors.underSelectedColor
            self.badge = .init(.initialize(string: "+\(peers.count - 3)", color: under, font: .avatar(.small)), theme.colors.accent, aroundFill: theme.colors.listBackground, additionSize: NSMakeSize(16, 7))
        } else {
            self.badge = nil
        }
        //assert(!peers.isEmpty)
        self.peers = Array(peers.prefix(3))
        super.init(initialSize, height: 80, stableId: stableId)
    }

    public override var accessibilityLabel: String? {
        if isGifted || peers.isEmpty {
            return strings().voiceOverCommonPremium
        }
        return peers.map { $0._asPeer().displayTitle }.joined(separator: ", ")
    }

    public override var accessibilityValue: String? {
        return badge != nil ? "+\(extraCount)" : nil
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return HeaderStarRowItemView.self
    }
}

private final class HeaderStarRowItemView : TableRowView {
    
    private let scene: PremiumStarSceneView = PremiumStarSceneView(frame: NSMakeRect(0, 0, 340, 180))
    private let avatars = View()
    private var badgeView: View?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scene)
        addSubview(avatars)
        avatars.frame = NSMakeRect(0, 0, 100, 65)
        scene.updateLayout(size: scene.frame.size, transition: .immediate)
        
        self.layer?.masksToBounds = false
    }
    
    public override func layout() {
        super.layout()
        scene.center()
        avatars.center()
        badgeView?.setFrameOrigin(avatars.frame.maxX - 22, avatars.frame.maxY - 18)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? HeaderStarRowItem else {
            return
        }
        
        if item.isGifted {
            self.scene.showStar()
            self.avatars.change(opacity: 0, animated: animated)
        } else {
            self.scene.hideStar()
            self.avatars.change(opacity: 1, animated: animated)
        }
        
        while avatars.subviews.count > item.peers.count {
            avatars.subviews.last?.removeFromSuperview()
        }
        while avatars.subviews.count < item.peers.count {
            avatars.addSubview(AvatarControl(font: .avatar(15)))
        }
        
        var x: CGFloat = 0
        for (i, peer) in item.peers.enumerated() {
            let control = avatars.subviews[i] as! AvatarControl
            control.setFrameSize(NSMakeSize(65, 65))
            control.setPeer(account: item.context.account, peer: peer._asPeer())
            control.layer?.zPosition = CGFloat(1000 - i)
            control.setFrameOrigin(x, 0)
            control.layer?.cornerRadius = control.frame.height / 2
            control.layer?.borderWidth = 2
            control.layer?.borderColor = theme.colors.listBackground.cgColor
            x += control.frame.width / 2
        }
        avatars.setFrameSize(NSMakeSize(avatars.frame.height + (CGFloat(item.peers.count - 1) * avatars.frame.height / 2), avatars.frame.height))
        needsLayout = true
        
        if let badge = item.badge {
            let current: View
            if let view = self.badgeView {
                current = view
            } else {
                current = View()
                addSubview(current)
                self.badgeView = current
            }
            badge.view = current
            current.setFrameSize(badge.size)
            badge.setNeedDisplay()
        } else if let view = self.badgeView {
            performSubviewRemoval(view, animated: animated)
            self.badgeView = nil
        }
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let execute:(String)->Void
    public let toggleOption:(PaymentOption)->Void
    public let openFeature:(PremiumValue)->Void
    public init(context: (any AccountContextProtocol), execute:@escaping(String)->Void, toggleOption:@escaping(PaymentOption)->Void, openFeature:@escaping(PremiumValue)->Void) {
        self.context = context
        self.execute = execute
        self.openFeature = openFeature
        self.toggleOption = toggleOption
    }
}

private struct State : Equatable {
    public var peers: [EnginePeer] = []
    public var products: [PremiumGiftProduct] = []
    public var defaultPrice: DefaultPrice = .init(intergal: 1, decimal: 1)
    public var selectedMonths: Int32 = 12
    public var newPerks: [String] = []
    public var premiumConfiguration: PremiumPromoConfiguration = .defaultValue
    public var stickers: [TelegramMediaFile] = []
    
    public var isGifted: Bool = false
    
    public var values:[PremiumValue] = [.double_limits, .stories, .more_upload, .faster_download, .voice_to_text, .no_ads, .infinite_reactions, .emoji_status, .premium_stickers, .animated_emoji, .advanced_chat_management, .profile_badge, .animated_userpics, .translations]

}


private let _id_header: InputDataIdentifier = .init("_id_header")
private let _id_boost: InputDataIdentifier = .init("_id_boost")

private func _id_option(_ id: String) -> InputDataIdentifier {
    return .init("_id_duration_\(id)")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state.isGifted), comparable: nil, item: { initialSize, stableId in
        return HeaderStarRowItem(initialSize, stableId: stableId, peers: state.peers, context: arguments.context, isGifted: state.isGifted)
    }))
    index += 1
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    let names: String
    
    if state.isGifted {
        if state.peers.count == 1 {
            names = strings().premiumGiftSentOneText(state.peers[0]._asPeer().compactDisplayTitle)
        } else if state.peers.count > 3 {
            let displayNames = state.peers.prefix(3).map { $0._asPeer().compactDisplayTitle }.joined(separator: ", ")
            names = strings().premiumGiftSentMultipleMoreThanThree(displayNames, "\(state.peers.count - 3)")
        } else {
            let displayNames = state.peers.map { $0._asPeer().compactDisplayTitle }.joined(separator: ", ")
            names = strings().premiumGiftSentMultipleOneToThree(displayNames)
        }
    } else {
        if state.peers.count > 3 {
            let displayNames = state.peers.prefix(3).map { $0._asPeer().compactDisplayTitle }.joined(separator: ", ")
            names = strings().premiumGiftGetAccessMoreThanThree(displayNames, "\(state.peers.count - 3)")
        } else {
            let displayNames = state.peers.map { $0._asPeer().compactDisplayTitle }.joined(separator: ", ")
            names = strings().premiumGiftGetAccessOneToThree(displayNames)
        }
    }
    
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(names), data: .init(color: theme.colors.text, detectBold: true, viewType: .modern(position: .inner, insets: .init()), fontSize: 13, centerViewAlignment: true, alignment: .center)))
    index += 1
    
    if !state.isGifted {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_boost, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return BoostText(initialSize, stableId: stableId, count: state.peers.count, context: arguments.context)
        }))
    }
   
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    struct PaymentTuple : Equatable {
        var option: PaymentOption
        var selected: Bool
        var viewType: GeneralViewType
    }
    var paymentOptions: [PaymentTuple] = []
    
    var _: Int32 = 0
    var existingMonths = Set<Int32>()
    
    var products:[PremiumGiftProduct] = []
    
    for product in state.products {
        if existingMonths.contains(product.months) {
            continue
        }
        existingMonths.insert(product.months)
        products.append(product)
    }
    
    let recipientCount = state.peers.count
    
    for (i, product) in products.enumerated() {
        
        let giftTitle: String
        if product.months == 12 {
            giftTitle = strings().giveawayPaymentOptionsYear
        } else {
            giftTitle = strings().giveawayPaymentOptionsMonths(Int(product.months))
        }
        
        let productAmount: Float = Float(product.priceCurrencyAndAmount.amount)
        let productMonths: Float = Float(product.months)
        let defaultPriceValue: Float = Float(state.defaultPrice.intergal)
        let discountRatio: Float = productAmount / productMonths / defaultPriceValue
        let discountValue: Int = Int((1.0 - discountRatio) * 100.0)
        let discount: String?
        if discountValue > 0 {
            discount = "-\(discountValue)%"
        } else {
            discount = nil
        }
        let subtitle = "\(product.price) x \(recipientCount)"
        let label = product.multipliedPrice(count: recipientCount)
        
        let selectedMonths = state.selectedMonths
        let isSelected = product.months == selectedMonths
        let option = PaymentOption(title: giftTitle, desc: subtitle, total: label, discount: discount, months: product.months)
        
        paymentOptions.append(.init(option: option, selected: isSelected, viewType: bestGeneralViewType(products, for: i)))

    }
    
    if !state.isGifted {
        for option in paymentOptions {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_option(option.option.title), equatable: .init(option), comparable: nil, item: { initialSize, stableId in
                return DurationOptionItem(initialSize, stableId: stableId, option: option.option, selected: option.selected, viewType: option.viewType, toggleOption: arguments.toggleOption)
            }))
        }
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().premiumWhatsIncluded), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    
    for (i, value) in state.values.enumerated() {
        let viewType = bestGeneralViewType(state.values, for: i)
        
        struct Tuple : Equatable {
            let value: PremiumValue
            let isNew: Bool
            let viewType: GeneralViewType
            let index: Int
        }
        let tuple = Tuple(value: value, isNew: state.newPerks.contains(value.rawValue), viewType: viewType, index: i)
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init(value.rawValue), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
            return PremiumBoardingRowItem(initialSize, stableId: stableId, viewType: tuple.viewType, presentation: theme, index: tuple.index, value: value, limits: arguments.context.premiumLimits, isLast: false, isNew: tuple.isNew, callback: arguments.openFeature)
        }))
    }
    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().premiumGiftTerms, linkHandler: { link in
        arguments.execute(link)
    }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    //
          
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func PremiumGiftingController(context: (any AccountContextProtocol), peerIds: [PeerId]) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    var initialState = State(values: context.premiumOrder.premiumValues.uniqueElements.filter({ !$0.isBusiness }))
    
    initialState.values.insert(.business, at: 0)
    
    let paymentDisposable = MetaDisposable()
    actionsDisposable.add(paymentDisposable)
    
    var close:(()->Void)? = nil
    var openFeature:((PremiumValue)->Void)? = nil
    
    let statePromise = ValuePromise<State>(ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let peers: Signal<[EnginePeer], NoError> = context.account.postbox.transaction { transaction in
        var peers:[EnginePeer] = []
        for peerId in peerIds {
            if let peer = transaction.getPeer(peerId) {
                peers.append(.init(peer))
            }
        }
        return peers
    }
    
    let inAppPurchaseManager = context.inAppPurchaseManager

    
    let products: Signal<[InAppPurchaseManager.Product], NoError>
    #if APP_STORE //|| DEBUG
    products = inAppPurchaseManager.availableProducts |> map {
        $0
    }
    #else
    products = .single([])
    #endif
    
    let productsAndDefaultPrice: Signal<([PremiumGiftProduct], (Int64, NSDecimalNumber)), NoError> = combineLatest(
        context.engine.payments.premiumGiftCodeOptions(peerId: nil),
        products
    )
    |> map { options, products in
        var gifts: [PremiumGiftProduct] = []
        for option in options {
            let product = products.first(where: { $0.id == option.storeProductId })
            gifts.append(PremiumGiftProduct(giftOption: option, storeProduct: product))
        }
        let defaultPrice: (Int64, NSDecimalNumber)
        if let defaultProduct = products.first(where: { $0.id == "org.telegram.telegramPremium.monthly" }) {
            defaultPrice = (defaultProduct.priceCurrencyAndAmount.amount, defaultProduct.priceValue)
        } else if let defaultProduct = options.first(where: { $0.storeProductId == "org.telegram.telegramPremium.threeMonths.code_x1" }) {
            defaultPrice = (defaultProduct.amount / Int64(defaultProduct.months), NSDecimalNumber(value: 1))
        } else {
            defaultPrice = (1, NSDecimalNumber(value: 1))
        }
        return (gifts, defaultPrice)
    }
    
    let premiumPromo = context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.PremiumPromo())
    |> deliverOnMainQueue
    
    let stickersKey: PostboxViewKey = .orderedItemList(id: Namespaces.OrderedItemList.CloudPremiumStickers)

    let stickers: Signal<[TelegramMediaFile], NoError> = context.account.postbox.combinedView(keys: [stickersKey])
    |> map { views -> [OrderedItemListEntry] in
        if let view = views.views[stickersKey] as? OrderedItemListView, !view.items.isEmpty {
            return view.items
        } else {
            return []
        }
    }
    |> map { items in
        var result: [TelegramMediaFile] = []
        for item in items {
            if let mediaItem = item.contents.get(RecentMediaItem.self) {
                result.append(mediaItem.media._parse())
            }
        }
        return result
    }
    |> take(1)
    |> deliverOnMainQueue

    
    actionsDisposable.add(combineLatest(productsAndDefaultPrice, peers, premiumPromo, stickers).start(next: { products, peers, premiumPromo, stickers in
            updateState { current in
                var current = current
                current.products = products.0
                current.defaultPrice = .init(intergal: products.1.0, decimal: products.1.1)
                current.peers = peers
                current.premiumConfiguration = premiumPromo
                current.stickers = stickers
                return current
            }
    }))
    
    

    let arguments = Arguments(context: context, execute: { link in
        LinkHooks.shared.openExternalLink("https://telegram.org/tos", false)
    }, toggleOption: { value in
        updateState { current in
            var current = current
            current.selectedMonths = value.months
            return current
        }
    }, openFeature: { value in
        openFeature?(value)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().premiumGiftTitle)
    controller.analyticsScreen = .premiumGift
    
    controller.didLoad = { controller, _ in
        controller.genericView.layer?.masksToBounds = false
        controller.tableView.layer?.masksToBounds = false
        controller.tableView.documentView?.layer?.masksToBounds = false
        controller.tableView.clipView.layer?.masksToBounds = false
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    let buyNonStore:()->Void = {
        let state = stateValue.with { $0 }
        
        var selectedProduct: PremiumGiftProduct?
        let selectedMonths = state.selectedMonths
        if let product = state.products.first(where: { $0.months == selectedMonths }) {
            selectedProduct = product
        }
        
        guard let premiumProduct = selectedProduct else {
            return
        }
        
        let source =  BotPaymentInvoiceSource.giftCode(users: state.peers.map { $0.id }, currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount, option: .init(users: Int32(state.peers.count), months: selectedMonths, storeProductId: nil, storeQuantity: 0, currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount), text: nil, entities: nil)
                        
        let invoice = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: source), for: context.window)

        actionsDisposable.add(invoice.start(next: { invoice in
            if let controller = FeatureNavigationHooks.shared.makePaymentsCheckoutController(context, source, invoice, { status in
            
                switch status {
                case .paid:
                    PlayConfetti(for: context.window)
                    updateState { current in
                        var current = current
                        current.isGifted = true
                        return current
                    }
                default:
                    break
                }
                
            }) { showModal(with: controller, for: context.window) }
        }, error: { error in
            showModalText(for: context.window, text: strings().paymentsInvoiceNotExists)
        }))
        
    }
    
    let buyAppStore = {
        
        let state = stateValue.with { $0 }
        
        var selectedProduct: PremiumGiftProduct?
        let selectedMonths = state.selectedMonths
        if let product = state.products.first(where: { $0.months == selectedMonths }) {
            selectedProduct = product
        }
        
        guard let premiumProduct = selectedProduct else {
            return
        }

        guard let storeProduct = premiumProduct.storeProduct else {
            buyNonStore()
            return
        }
        
        let lockModal = PremiumLockModalController()
        
        var needToShow = true
        delay(0.2, closure: {
            if needToShow {
                showModal(with: lockModal, for: context.window)
            }
        })
        let purpose: AppStoreTransactionPurpose = .giftCode(peerIds: state.peers.map { $0.id }, boostPeer: nil, currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount, text: nil, entities: nil)
        
                
        let _ = (context.engine.payments.canPurchasePremium(purpose: purpose)
        |> deliverOnMainQueue).start(next: { [weak lockModal] available in
            if available {
                paymentDisposable.set((inAppPurchaseManager.buyProduct(storeProduct, quantity: premiumProduct.giftOption.storeQuantity, purpose: purpose)
                |> deliverOnMainQueue).start(next: { [weak lockModal] status in
    
                    lockModal?.close()
                    needToShow = false
                    
                    inAppPurchaseManager.finishAllTransactions()
                    PlayConfetti(for: context.window)
                    updateState { current in
                        var current = current
                        current.isGifted = true
                        return current
                    }
                    
                }, error: { [weak lockModal] error in
                    let errorText: String
                    switch error {
                        case .generic:
                            errorText = strings().premiumPurchaseErrorUnknown
                        case .network:
                            errorText =  strings().premiumPurchaseErrorNetwork
                        case .notAllowed:
                            errorText =  strings().premiumPurchaseErrorNotAllowed
                        case .cantMakePayments:
                            errorText =  strings().premiumPurchaseErrorCantMakePayments
                        case .assignFailed:
                            errorText =  strings().premiumPurchaseErrorUnknown
                        case .cancelled:
                            errorText = strings().premiumBoardingAppStoreCancelled
                    }
                    lockModal?.close()
                    showModalText(for: context.window, text: errorText)
                    inAppPurchaseManager.finishAllTransactions()
                }))
            } else {
                lockModal?.close()
                needToShow = false
            }
        })
    }
    
    controller.validateData = { _ in
        let isGifted = stateValue.with { $0.isGifted }
        if isGifted {
            close?()
            return .none
        }
        #if APP_STORE
        buyAppStore()
        #else
        buyNonStore()
        #endif
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().premiumGiftTitle, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true, customTheme: {
        .init(text: theme.colors.text, grayText: theme.colors.grayText, background: .clear, border: .clear, accent: theme.colors.accent, grayForeground: .clear, activeBackground: .clear, activeBorder: theme.colors.border, listBackground: .clear)
    })
    
    /*
     
     */
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(380, 350))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.getTitle = {
        let isGifted = stateValue.with { $0.isGifted }
        let isMultiple = stateValue.with { $0.peers.count > 1 }
        
        if isGifted {
            return isMultiple ? strings().premiumGiftSentOneTitle : strings().premiumGiftSentMultipleTitle
        } else {
            return strings().premiumGiftTitle
        }
    }
    
    controller.afterTransaction = { [weak modalInteractions, weak modalController] controller in
        let isGifted = stateValue.with { $0.isGifted }
        let text: String = isGifted ? strings().premiumGiftSentClose : strings().premiumGiftTitle
        modalInteractions?.updateDone { button in
            button.set(text: text, for: .Normal)
        }
        modalInteractions?.acceptTitle = text
        modalController?.updateLocalizationAndTheme(theme: theme)
    }
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    var _features: ViewController?
    
    openFeature = { [weak controller] value in
        guard let controller = controller, controller.isLoaded() else {
            return
        }
        var closeFeatures:(()->Void)? = nil
        let features = PremiumBoardingFeaturesController(context, presentation: theme, value: value, stickers: [], configuration: stateValue.with { $0.premiumConfiguration }, back: {
            closeFeatures?()
        }, makeAcceptView: {
            return nil
        })
        features._frameRect = NSMakeRect(0, 100, controller.bounds.width, controller.bounds.height - 40)

        features.view.layer?.animatePosition(from: NSMakePoint(0, controller.bounds.maxY), to: NSMakePoint(0, features._frameRect.minY), duration: 0.2, timingFunction: .spring)
        features.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        
        let background: Control = Control(frame: controller.bounds.insetBy(dx: 0, dy: -50))
        background.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        background.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        background.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        
        background.set(handler: { _ in
            closeFeatures?()
        }, for: .Click)
        
        closeFeatures = { [weak features, weak background] in
            if let background = background {
                performSubviewRemoval(background, animated: true)
            }
            if let features = features {
                performSubviewPosRemoval(features.view, pos: NSMakePoint(0, features.view.frame.maxY), animated: true)
            }
            _features = nil
        }
        controller.view.addSubview(background)
        controller.view.addSubview(features.view)
        _features = features
    }
    
    modalController._hasBorder = false
    
    return modalController
}




