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



private final class HeaderTextRowItem : GeneralRowItem {
    public enum HeaderTextType : Equatable {
        case premium
        case stars(selfGift: Bool, filter: State.StarGiftFilter)
        
        public var headerText: String {
            switch self {
            case .premium:
                return strings().giftingPremiumTitle
            case let .stars(selfGift, _):
                return selfGift
                    ? strings().giftingStarGiftTitleBuy
                    : strings().giftingStarGiftTitleSend
            }
        }

        public func infoText(_ peer: EnginePeer) -> String {
            switch self {
            case .premium:
                return strings().giftingPremiumInfo(peer._asPeer().displayTitle)
            case let .stars(selfGift, filter):
                if filter == .resale || filter == .myGifts {
                    return strings().giftingStarGiftInfoCollectibles
                } else {
                    return selfGift
                        ? strings().giftOptionsGiftSelfText
                        : strings().giftingStarGiftInfo(peer._asPeer().displayTitle)
                }
            }
        }

    }
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, peer: EnginePeer, type: HeaderTextType, context: (any AccountContextProtocol), openPromo: @escaping(String)->Void) {
        self.context = context
        
        self.headerLayout = .init(.initialize(string: type.headerText, color: theme.colors.text, font: .medium(.header)), maximumNumberOfLines: 1, alignment: .center)
        let info = parseMarkdownIntoAttributedString(type.infoText(peer), attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.accentIcon), linkAttribute: { contents in
            return (NSAttributedString.Key.link.rawValue, contents)
        }))
        
        self.infoLayout = .init(info, alignment: .center)
        
        let interactions = LinkHooks.shared.globalLinkExecutor()
        interactions.processURL = { url in
            if let url = url as? String {
                openPromo(url)
            }
        }
        self.infoLayout.interactions = interactions
        
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.headerLayout.measure(width: width - 40)
        self.infoLayout.measure(width: width - 40)
        
        return true
    }
    
    public override var height: CGFloat {
        return headerLayout.layoutSize.height + 2 + infoLayout.layoutSize.height
    }
    
    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return infoLayout.attributedString.string
    }

    public override func viewClass() -> AnyClass {
        return HeaderTextRowView.self
    }
}

private final class HeaderTextRowView : GeneralRowView {
    private let headerView = TextView()
    private let infoView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerView)
        addSubview(infoView)
        
        headerView.isSelectable = false
        infoView.isSelectable = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        headerView.centerX(y: 0)
        infoView.centerX(y: headerView.frame.maxY + 2)
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderTextRowItem else {
            return
        }
        let infoChanged = infoView.textLayout?.attributedString.string != item.infoLayout.attributedString.string
        headerView.update(item.headerLayout)
        infoView.update(item.infoLayout)
        if animated, infoChanged {
            infoView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        }
        needsLayout = true
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
}


private final class HeaderRowItem : GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peers: [EnginePeer]
    public init(_ initialSize: NSSize, stableId: AnyHashable, peers: [EnginePeer], context: (any AccountContextProtocol)) {
        self.context = context
        
        self.peers = Array(peers.prefix(3))
        super.init(initialSize, stableId: stableId)
    }
    
    public override var height: CGFloat {
        return 70
    }
    
    public override var accessibilityLabel: String? {
        return peers.map { $0._asPeer().displayTitle }.joined(separator: ", ")
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return HeaderRowView.self
    }
}

private final class HeaderRowView : TableRowView {
    private let scene: GoldenStarSceneView = GoldenStarSceneView(frame: NSMakeRect(0, 0, 340, 180))
    private let avatars = View()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scene)
        addSubview(avatars)
        avatars.frame = NSMakeRect(0, 20, 100, 100)
        scene.updateLayout(size: scene.frame.size, transition: .immediate)
        
        self.layer?.masksToBounds = false
        self.layer?.zPosition = -1
    }
    
    public override func layout() {
        super.layout()
        scene.center()
        avatars.centerX(y: -30)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? HeaderRowItem else {
            return
        }
        
        self.scene.hideStar()
        self.scene.sceneBackground = theme.colors.listBackground
        
        self.avatars.change(opacity: 1, animated: animated)

        while avatars.subviews.count > item.peers.count {
            avatars.subviews.last?.removeFromSuperview()
        }
        while avatars.subviews.count < item.peers.count {
            avatars.addSubview(AvatarControl(font: .avatar(18)))
        }
        
        var x: CGFloat = 0
        for (i, peer) in item.peers.enumerated() {
            let control = avatars.subviews[i] as! AvatarControl
            control.setFrameSize(NSMakeSize(100, 100))
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
        
    }
}

private final class FilterRowItem : GeneralRowItem {
    fileprivate let item: StarGiftFilterRowItem.Item
    fileprivate let layout: TextViewLayout
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let arguments: Arguments
    public init(_ initialSize: NSSize, stableId: AnyHashable, item: StarGiftFilterRowItem.Item, arguments: Arguments) {
        self.item = item
        self.layout = .init(item.text, maximumNumberOfLines: 1)
        self.layout.measure(width: .greatestFiniteMagnitude)
        self.context = arguments.context
        self.arguments = arguments
        super.init(initialSize)
    }
    public override var accessibilityLabel: String? {
        switch item.value {
        case let .stars(amount):
            return strings().starListItemCountOther(Int(amount))
        default:
            return layout.attributedString.string.replacingOccurrences(of: clown, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .radioButton
    }

    public override var accessibilityToggleState: Bool? {
        return item.selected
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        arguments.selectFilter(item.value)
        return true
    }

    public override func viewClass() -> AnyClass {
        return FilterRowView.self
    }
    
    public override var height: CGFloat {
        return self.layout.layoutSize.width + 24
    }
    public override var width: CGFloat {
        return 40
    }
}

private final class FilterRowView : HorizontalRowView {
    private let textView: InteractiveTextView = InteractiveTextView()
    private var selectedView: View?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.scaleOnClick = true
        textView.userInteractionEnabled = true
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? FilterRowItem else {
            return
        }
        
        self.textView.set(text: item.layout, context: item.context)
        self.textView.center()
        
        self.textView.setSingle(handler: { [weak item] _ in
            if let item = item {
                item.arguments.selectFilter(item.item.value)
            }
        }, for: .Click)
        
        if item.item.selected {
            let current: View
            let isNew: Bool
            if let view = self.selectedView {
                current = view
                isNew = false
            } else {
                current = View()
                addSubview(current, positioned: .below, relativeTo: textView)
                self.selectedView = current
                isNew = true
            }
            current.backgroundColor = theme.colors.listGrayText.withAlphaComponent(0.2)
            current.frame = textView.frame.insetBy(dx: -10, dy: -5)
            current.layer?.cornerRadius = current.frame.height / 2
            if isNew, animated {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
            }
        } else if let selectedView {
            performSubviewRemoval(selectedView, animated: animated)
            self.selectedView = nil
        }
    }
    
    public override func layout() {
        super.layout()
        self.textView.center()
    }
}

private final class StarGiftFilterRowItem : GeneralRowItem {
    
    public struct Item : Comparable, Identifiable {
        public let value: State.StarGiftFilter
        public let index: Int
        public let selected: Bool
        
        public var stableId: AnyHashable {
            return value
        }
        public static func < (lhs: Item, rhs: Item) -> Bool {
            return lhs.index < rhs.index
        }
        
        public func makeItem(_ size: NSSize, arguments: Arguments) -> TableRowItem {
            switch self.value {
            case .emptyLeft, .emptyRight:
                return GeneralRowItem(size, height: 15, stableId: stableId, backgroundColor: .clear)
            default:
                return FilterRowItem(size, stableId: stableId, item: self, arguments: arguments)
            }
        }
        
        public var text: NSAttributedString {
            let attr = NSMutableAttributedString()
            switch self.value {
            case .all:
                attr.append(string: strings().giftingStarGiftAll, color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText, font: .normal(.text))
            case .myGifts:
                attr.append(string: strings().giftingMyGifts, color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText, font: .normal(.text))
            case .limited:
                attr.append(string: strings().giftingStarGiftLimited, color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText, font: .normal(.text))
            case .available:
                attr.append(string: strings().giftingStarGiftInStock, color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText, font: .normal(.text))
            case .stars(let int64):
                attr.append(string: "\(clown_space)\(int64)", color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText, font: .normal(.text))
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            case .resale:
                attr.append(
                    string: strings().giftingStarGiftLabelCollectibles,
                    color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText,
                    font: .normal(.text)
                )
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            default:
                break
            }
            return attr
        }
        public init(value: State.StarGiftFilter, index: Int, selected: Bool) {
            self.value = value
            self.index = index
            self.selected = selected
        }
    }
    
    fileprivate let items: [Item]
    fileprivate let selected: State.StarGiftFilter
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let arguments: Arguments
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), filters: [State.StarGiftFilter], selected: State.StarGiftFilter, arguments: Arguments) {
        var items: [Item] = []
        for (i, filter) in filters.enumerated() {
            items.append(.init(value: filter, index: i, selected: filter == selected))
        }
        self.items = items
        self.context = context
        self.selected = selected
        self.arguments = arguments
        super.init(initialSize, stableId: stableId)
    }
    
    public override var height: CGFloat {
        return 40
    }
    
    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonFilter
    }

    public override func viewClass() -> AnyClass {
        return StarGiftFilterRowView.self
    }
}

private final class StarGiftFilterRowView : GeneralRowView {
    private let tableView = HorizontalTableView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(tableView)
        tableView.getBackgroundColor = {
            .clear
        }
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var items: [StarGiftFilterRowItem.Item] = []
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StarGiftFilterRowItem else {
            return
        }
        _ = item.context
        let items = item.items
        let arguments = item.arguments
        
        applyMergedRows(tableView, current: &self.items, items: items, animated: animated, makeItem: { item in
            return item.makeItem(bounds.size, arguments: arguments)
        })
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        tableView.frame = focus(NSMakeSize(tableView.listHeight, bounds.height))
    }
}


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let selectFilter:(State.StarGiftFilter)->Void
    public let executeLink:(String)->Void
    public let openGift:(PeerStarGift)->Void
    public let giftPremium:(PremiumPaymentOption)->Void
    public let close:()->Void
    public let openPromo:(String)->Void
    public let transfer:(ProfileGiftsContext.State.StarGift)->Void
    public init(context: (any AccountContextProtocol), selectFilter:@escaping(State.StarGiftFilter)->Void, executeLink:@escaping(String)->Void, openGift:@escaping(PeerStarGift)->Void, giftPremium:@escaping(PremiumPaymentOption)->Void, close:@escaping()->Void, openPromo:@escaping(String)->Void, transfer:@escaping(ProfileGiftsContext.State.StarGift)->Void) {
        self.context = context
        self.selectFilter = selectFilter
        self.executeLink = executeLink
        self.openGift = openGift
        self.giftPremium = giftPremium
        self.close = close
        self.openPromo = openPromo
        self.transfer = transfer
    }
}



private struct State : Equatable {
    
    public enum StarGiftFilter : Hashable {
        case emptyLeft
        case emptyRight
        case all
        case myGifts
        case limited
        case available
        case resale
        case stars(Int64)
    }
    
    public var products: [PremiumGiftProduct] = []
    public var defaultPrice: DefaultPrice = .init(intergal: 1, decimal: 1)
    public var premiumConfiguration: PremiumPromoConfiguration = .defaultValue
    public var peer: EnginePeer?
    
    public var starFilters: [StarGiftFilter] = [.emptyLeft, .all, .myGifts, .limited, .available, .emptyRight]
    public var selectedStarFilter: StarGiftFilter = .all
    
    public var starGifts: [PeerStarGift] = []
    
    public var starsState: StarsContext.State?
    
    public var collectibles: [ProfileGiftsContext.State.StarGift] = []
    
    public var disallowedGifts: TelegramDisallowedGifts
    
}


private let _id_header = InputDataIdentifier("_id_header")
private let _id_premium_header = InputDataIdentifier("_id_premium_header")
private let _id_star_header = InputDataIdentifier("_id_star_header")
private let _id_premium_gifts = InputDataIdentifier("_id_premium_gifts")
private let _id_star_filters = InputDataIdentifier("_id_star_filters")
private func _id_stars_gifts(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_stars_gifts_\(index)")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    if let peer = state.peer {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return HeaderRowItem(initialSize, stableId: stableId, peers: [peer], context: arguments.context)
        }))
        
        if arguments.context.peerId != peer.id, peer._asPeer().isUser, !state.disallowedGifts.contains(.premium) {
            
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            var paymentOptions: [PremiumPaymentOption] = []
            
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
            
            for product in products.reversed() {
                
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
                let subtitle = "\(product.price)"
                let label = product.multipliedPrice(count: 1)
                
                let option = PremiumPaymentOption(title: giftTitle, desc: subtitle, total: label, discount: discount, months: product.months, product: product, starProduct: state.products.first(where: { $0.giftOption.currency == XTR && $0.months == product.months}))
                paymentOptions.append(option)
            }
            
            if !paymentOptions.isEmpty {
                
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_premium_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                    return HeaderTextRowItem(initialSize, stableId: stableId, peer: peer, type: .premium, context: arguments.context, openPromo: arguments.openPromo)
                }))
                
                entries.append(.sectionId(sectionId, type: .normal))
                sectionId += 1
                
                
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_premium_gifts, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                    return GiftOptionsRowItem(initialSize, stableId: stableId, context: arguments.context, options: paymentOptions.map { .initialize($0) }, insets: .init(left: 10, right: 10), callback: { option, _ in
                        if let option = option.nativePayment {
                            arguments.giftPremium(option)
                        }
                    })
                }))
            }
        }
        
      
        
      

        let filtered:([PeerStarGift], State.StarGiftFilter) -> ([PeerStarGift]) = { list, filter in
            switch filter {
            case .all:
                return list
            case .myGifts:
                return []
            case .limited:
                return list.filter(\.limited)
            case let .stars(stars):
                return list.filter { $0.stars == stars }
            case .available:
                return list.filter({ !$0.limited || $0.native.generic?.soldOut == nil })
            case .resale:
                return list.filter({ $0.native.generic?.hasResaleAvailability == true })
            default:
                return list
            }
        }
        let chunks = filtered(state.starGifts, state.selectedStarFilter).chunks(3)
        
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_star_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return HeaderTextRowItem(initialSize, stableId: stableId, peer: peer, type: .stars(selfGift: arguments.context.peerId == peer.id, filter: state.selectedStarFilter), context: arguments.context, openPromo: arguments.openPromo)
        }))
        
        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_star_filters, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return StarGiftFilterRowItem(initialSize, stableId: stableId, context: arguments.context, filters: state.starFilters, selected: state.selectedStarFilter, arguments: arguments)
        }))
        
        
        if !chunks.isEmpty {
            
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
            
            for (i, chunk) in chunks.enumerated() {
                if !chunk.isEmpty {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_stars_gifts(i), equatable: .init(chunk), comparable: nil, item: { initialSize, stableId in
                        return GiftOptionsRowItem(initialSize, stableId: stableId, context: arguments.context, options: chunk.map { .initialize($0) }, insets: .init(left: 10, right: 10), callback: { option, _ in
                            if let option = option.nativeStarGift {
                                arguments.openGift(option)
                            }
                        })
                    }))
                    
                    entries.append(.sectionId(sectionId, type: .customModern(10)))
                    sectionId += 1
                }
            }
        } else if !state.collectibles.isEmpty, state.selectedStarFilter == .myGifts {
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
            
            let chunks = state.collectibles.chunks(3)
            
            for (i, chunk) in chunks.enumerated() {
                if !chunk.isEmpty {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_stars_gifts(i), equatable: .init(chunk), comparable: nil, item: { initialSize, stableId in
                        return GiftOptionsRowItem(initialSize, stableId: stableId, context: arguments.context, options: chunk.map { .initialize($0, context: arguments.context, transfrarable: true) }, insets: .init(left: 10, right: 10), callback: { option, _ in
                            if let gift = option.nativeProfileGift {
                                arguments.transfer(gift)
                            }
                        })
                    }))
                    
                    entries.append(.sectionId(sectionId, type: .customModern(10)))
                    sectionId += 1
                }
            }
        }
        
        
    }
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
//

//  
//    // entries
//    

    
    return entries
}

public func GiftingController(context: (any AccountContextProtocol), peerId: PeerId, isBirthday: Bool, starGiftsContext: ProfileGiftsContext? = nil) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let paymentDisposable = MetaDisposable()
    actionsDisposable.add(paymentDisposable)
    
    let initialState = State(products: context.premiumProductsAndPrice.0, defaultPrice: .init(intergal: context.premiumProductsAndPrice.1.0, decimal: context.premiumProductsAndPrice.1.1), disallowedGifts: [])
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->InputDataController?)? = nil
    var close:(()->Void)? = nil
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }
    
    
    
    let premiumPromo = context.engine.data.get(TelegramEngine.EngineData.Item.Configuration.PremiumPromo())
    |> deliverOnMainQueue
    

    let peer = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    
    let birtday = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Birthday(id: peerId))
    
    let giftsContext = ProfileGiftsContext(account: context.account, peerId: context.peerId, filter: [.unique, .displayed, .hidden])
        
    let disallowedGifts: Signal<TelegramDisallowedGifts?, NoError> = context.account.viewTracker.peerView(peerId, updateData: true) |> map { view in
        if peerId == context.peerId {
            return nil
        } else {
            return (view.cachedData as? CachedUserData)?.disallowedGifts
        }
    }
    
    
    let checkAvailability:()->Void = {
        let state = stateValue.with { $0 }
        if state.disallowedGifts == .All, let peer = state.peer {
            close?()
            showModalText(for: window, text: strings().giftNotAccepting(peer._asPeer().displayTitle))
        }
    }
    
    actionsDisposable.add(combineLatest(peer, premiumPromo, context.engine.payments.cachedStarGifts(), birtday, context.starsContext.state, giftsContext.state, disallowedGifts).start(next: { peer, premiumPromo, gifts, birthday, starsState, myGifts, disallowedGifts in
        updateState { current in
            var current = current
            current.peer = peer
            current.premiumConfiguration = premiumPromo
            current.starsState = starsState
            current.disallowedGifts = disallowedGifts ?? []
            current.collectibles = myGifts.filteredGifts

            
            if let gifts {
                current.starGifts = gifts.compactMap { $0.generic }.map {
                    .init(media: $0.file, stars: $0.price, limited: $0.availability != nil, native: .generic($0))
                }
                if birthday?.isEligble == true || isBirthday {
                    current.starGifts = current.starGifts.sorted { gift1, gift2 in
                        switch (gift1.native.generic!.flags.contains(.isBirthdayGift), gift2.native.generic!.flags.contains(.isBirthdayGift)) {
                        case (true, false): return true
                        case (false, true): return false
                        default: return false
                        }
                    }
                }
                
                if let disallowedGifts {
                    current.starGifts = current.starGifts.filter({ gift in
                        if gift.limited && disallowedGifts.contains(.limited) {
                            if gift.native.generic?.hasResaleAvailability != true {
                                return false
                            }
                        }
                        if !gift.limited && disallowedGifts.contains(.unlimited) {
                            if gift.native.generic?.hasResaleAvailability != true {
                                return false
                            }
                        }
                        if gift.native.unique != nil && disallowedGifts.contains(.unique) {
                            return false
                        }
                        return true
                    })
                }
                
                
                let hasResale = current.starGifts.contains(where: {
                    $0.native.generic?.hasResaleAvailability == true
                })
                
                var filters: [State.StarGiftFilter] = [.all] + (current.collectibles.isEmpty ? [] : [.myGifts])
                if hasResale {
                    filters.append(.resale)
                }
                
                current.starFilters = filters
                
                if let disallowedGifts {
                    if disallowedGifts.contains(.limited) {
                        current.starFilters.removeAll(where: { $0 == .limited})
                    }
                    if disallowedGifts.contains(.unique) {
                        current.starFilters.removeAll(where: { $0 == .myGifts })
                    }
                    
                   
                }
            }
            return current
        }
        
        checkAvailability()
    }))
    
    
    actionsDisposable.add(context.engine.payments.keepStarGiftsUpdated().startStrict())
    

    let arguments = Arguments(context: context, selectFilter: { filter in
        updateState { current in
            var current = current
            current.selectedStarFilter = filter
            return current
        }
    }, executeLink: { link in
        
    }, openGift: { option in
        
        let open:()->Void = {
            let state = stateValue.with { $0 }
            if let peer = state.peer {
                guard let gift = option.native.generic else {
                    return
                }
                let hasResale = gift.hasResaleAvailability

                if let limit = gift.perUserLimit, limit.remains == 0, !hasResale {
                    showModalText(
                        for: window,
                        text: strings().giftSendErrorLimitReachedOther(Int(limit.total))
                    )
                } else if gift.flags.contains(.requiresPremium), !context.isPremium, !hasResale {
                    prem(with: PremiumBoardingController(context: context, source: .limitedGift(gift)), for: context.window)
                } else if gift.isAuction, !hasResale {
                        let signal = context.giftAuctionsManager.auctionContext(for: .giftId(gift.id)) |> deliverOnMainQueue
                
                        _ = showModalProgress(signal: signal, for: window).startStandalone(next: { auctionContext in
                            if let auctionContext {
                                if auctionContext.isActive {
                                    if let currentBidPeerId = auctionContext.currentBidPeerId, currentBidPeerId != peerId {
                                        
                                        let peers = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: currentBidPeerId)) |> deliverOnMainQueue
                                        
                                        _ = peers.startStandalone(next: { currentBidPeer in
                                            if let currentBidPeer {                                                
                                                let alertData = ModalAlertData(
                                                    title: strings().starAuctionChangePeerTitle,
                                                    info: strings().starAuctionChangePeerInfo(
                                                        currentBidPeer._asPeer().displayTitle,
                                                        peer._asPeer().displayTitle
                                                    ),
                                                    description: nil,
                                                    ok: strings().starAuctionChangePeerOk,
                                                    options: [],
                                                    mode: .confirm(text: strings().modalCancel, isThird: false),
                                                    header: .init(id: "header", value: { initialSize, stableId, presentation in
                                                        return ChangePeerRowItem(
                                                            initialSize,
                                                            stableId: stableId,
                                                            context: context,
                                                            fromPeer: currentBidPeer,
                                                            toPeer: peer
                                                        )
                                                    })
                                                )
                                                
                                                
                                                showModalAlert(for: window, data: alertData, completion: { action in
                                                    
                                                    if auctionContext.gift.generic?.upgradeVariantsCount != nil, peer.id == context.peerId {
                                                        _ = showModalProgress(signal: context.engine.payments.getStarGiftUpgradeAttributes(giftId: auctionContext.gift.giftId), for: window).startStandalone(next: { attributes in
                                                            if let attributes {
                                                                showModal(with: StarGift_SelfAuction_Controller(context: context, gift: auctionContext.gift, attributes: attributes, giftAuctionContext: auctionContext), for: window)
                                                            }
                                                        })
                                                    } else {
                                                        showModal(with: PreviewStarGiftController(context: context, option: .starGift(option: option), peer: peer, disallowedGifts: state.disallowedGifts, starGiftsProfile: starGiftsContext), for: window)
                                                    }
                                                    
                                                })
                                            }
                                        })
                                        
                                       
                                    } else {
                                        showModal(with: Star_AuctionBidController(context: context, peerId: peerId, gift: auctionContext.gift.generic!, auctionContext: auctionContext), for: window)
                                    }
                                } else {
                                    showModal(with: Star_AuctionPreviewController(context: context, auctionContext: auctionContext, peerId: peerId, callback: {
                                        
                                        if auctionContext.gift.generic?.upgradeVariantsCount != nil, peer.id == context.peerId {
                                            _ = showModalProgress(signal: context.engine.payments.getStarGiftUpgradeAttributes(giftId: auctionContext.gift.giftId), for: window).startStandalone(next: { attributes in
                                                if let attributes {
                                                    showModal(with: StarGift_SelfAuction_Controller(context: context, gift: auctionContext.gift, attributes: attributes, giftAuctionContext: auctionContext), for: window)
                                                }
                                            })
                                        } else {
                                            showModal(with: PreviewStarGiftController(context: context, option: .starGift(option: option), peer: peer, disallowedGifts: state.disallowedGifts, starGiftsProfile: starGiftsContext), for: window)
                                        }
                                        
                                    }), for: window)
                                }
                            } else {
                                showModalText(for: window, text: strings().auctionErrorNotExists)
                            }
                        })
                } else if let availability = gift.availability,
                          availability.remains == 0 || gift.perUserLimit?.remains == 0 || peerId.namespace == Namespaces.Peer.CloudChannel {
                    if hasResale {
                        showModal(with: StarGift_MarketplaceController(context: context, peerId: peer.id, gift: gift), for: window)
                    } else {
                        showModal(with: Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: nil, transaction: .init(flags: [.isGift], id: "", count: .init(amount: .init(value: 0, nanos: 0), currency: .stars), date: 0, peer: .unsupported, title: "", description: "", photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: option.native, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil), purpose: .unavailableGift), for: context.window)
                    }
                } else {
                    showModal(with: PreviewStarGiftController(context: context, option: .starGift(option: option), peer: peer, disallowedGifts: state.disallowedGifts, starGiftsProfile: starGiftsContext), for: window)
                }
            }
        }
        
        if let gift = option.native.generic,
           let lockedUntilDate = gift.lockedUntilDate,
           Int32(Date().timeIntervalSince1970) < lockedUntilDate {
            _ = showModalProgress(signal: context.engine.payments.checkCanSendStarGift(giftId: gift.id), for: window).start(next: { result in
                switch result {
                case .available:
                    open()
                case .failed:
                    alert(for: window, info: strings().unknownError)
                case let .unavailable(text, _):
                    alert(for: window, info: text)
                }
            })
        } else {
            open()
        }
    }, giftPremium: { option in
        let state = stateValue.with { $0 }
        if let peer = state.peer {
            if let product = state.products.first(where: { $0.months == option.months }) {
                let starGift = state.products.first(where: { $0.months == option.months && $0.giftOption.currency == XTR })
                showModal(with: PreviewStarGiftController(context: context, option: .premium(option: product, starOption: starGift), peer: peer, disallowedGifts: state.disallowedGifts, starGiftsProfile: starGiftsContext), for: window)
            }
        }

    }, close: {
        close?()
    }, openPromo: { value in
        if value == "stars" {
            showModal(with: StarUsePromoController(context: context), for: window)
        } else {
            prem(with: PremiumBoardingController(context: context), for: window)
        }
    }, transfer: { gift in
        
        let unique = gift.gift.unique
        let state = stateValue.with { $0 }
        let peer = state.peer
        
        
        let convertStars: Int64? = gift.transferStars
        let reference: StarGiftReference? = gift.reference ?? .peer(peerId: context.peerId, id: unique!.id)
        
        let info: String
        let ok: String
        
        guard let reference = reference, let unique = unique, let peer = peer else {
            return
        }
        
        if let convertStars = convertStars, let starsState = state.starsState, starsState.balance.value < convertStars {
            showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: convertStars)), for: window)
            return
        }
        
        if let stars = convertStars, stars > 0 {
            info = strings().giftTransferConfirmationText("\(unique.title) #\(unique.number)", peer._asPeer().displayTitle, strings().starListItemCountOther(Int(stars)))
            ok = strings().giftTransferConfirmationTransfer + " " + strings().starListItemCountOther(Int(stars))
        } else {
            info = strings().giftTransferConfirmationTextFree("\(unique.title) #\(unique.number)", peer._asPeer().displayTitle)
            ok = strings().giftTransferConfirmationTransferFree
        }
        
        let data = ModalAlertData(title: nil, info: info, description: nil, ok: ok, options: [], mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
            return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: unique, toPeer: peer, context: context)
        }), footer: ModalAlertData.Footer.init(id: "footer", value: { initialSize, stableId, presentation, action in
            return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: unique), context: context)
        }), width: 340, showCloseButton: true)
        
        showModalAlert(for: window, data: data, completion: { result in
            _ = giftsContext.transferStarGift(prepaid: convertStars == nil, reference: reference, peerId: peerId).startStandalone()
            _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5).start()
            close?()
        })
        
    })
    
    let signal = statePromise.get() |> filter { $0.peer != nil } |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    let controller = InputDataController(dataSignal: signal, title: context.peerId == peerId ? strings().giftOptionsGiftSelfTitle : strings().giftingTitle)
    controller.analyticsScreen = .giftsCatalog
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.didLoad = { controller, _ in
        controller.genericView.layer?.masksToBounds = false
        controller.tableView.layer?.masksToBounds = false
        controller.tableView.documentView?.layer?.masksToBounds = false
        controller.tableView.clipView.layer?.masksToBounds = false
    }

    let modalController = InputDataModalController(controller, size: NSMakeSize(380, 0))
    modalController.fullSizeList = true
    
    
    modalController.getModalTheme = {
        return .init(text: theme.colors.text, grayText: theme.colors.grayText, background: .clear, border: .clear, accent: theme.colors.accent, grayForeground: .clear, activeBackground: theme.colors.background, activeBorder: theme.colors.border, hideUnactiveText: true)
    }
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.contextObject = giftsContext
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}


/*

 */
