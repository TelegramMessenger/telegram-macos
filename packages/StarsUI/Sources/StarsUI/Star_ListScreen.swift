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
public enum Star_TransactionType : Equatable {
    public enum Source : Equatable {
        case peer
        case appstore
        case fragment
        case playmarket
        case premiumbot
        case unknown
        case ads
        case apiLimitExtension
    }
    case incoming(Source)
    case outgoing(Source)
    
    public var source: Source {
        switch self {
        case .incoming(let source):
            return source
        case .outgoing(let source):
            return source
        }
    }
    
}
public struct Star_Transaction : Equatable {
    public let id: String
    public let currency: CurrencyAmount.Currency
    public let amount: StarsAmount
    public let date: Int32
    public let name: String
    public let peer: EnginePeer?
    public let type: Star_TransactionType
    public let native: StarsContext.State.Transaction
    public init(id: String, currency: CurrencyAmount.Currency, amount: StarsAmount, date: Int32, name: String, peer: EnginePeer?, type: Star_TransactionType, native: StarsContext.State.Transaction) {
        self.id = id
        self.currency = currency
        self.amount = amount
        self.date = date
        self.name = name
        self.peer = peer
        self.type = type
        self.native = native
    }
}

public struct Star_Subscription : Equatable {
    public enum State : Equatable {
        case active(refulfil: Bool)
        case cancelled(refulfil: Bool)
        case expired
    }
    public let id: String
    public let peer: EnginePeer
    public let amount: StarsAmount
    public let date: Int32
    public let renewDate: Int32
    public let state: State
    public let native: StarsContext.State.Subscription
    public init(id: String, peer: EnginePeer, amount: StarsAmount, date: Int32, renewDate: Int32, state: State, native: StarsContext.State.Subscription) {
        self.id = id
        self.peer = peer
        self.amount = amount
        self.date = date
        self.renewDate = renewDate
        self.state = state
        self.native = native
    }
}


private func transactionSegments(_ transactionMode: State.TransactionMode) -> [ScrollableSegmentItem] {
    let theme = ScrollableSegmentTheme.standard(theme.colors)
    var items: [ScrollableSegmentItem] = []
    items.append(.init(title: strings().starListTransactionsAll, index: 0, uniqueId: 0, selected: transactionMode == .all, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: theme, equatable: UIEquatable(transactionMode)))
    items.append(.init(title: strings().starListTransactionsIncoming, index: 1, uniqueId: 1, selected: transactionMode == .incoming, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: theme, equatable: UIEquatable(transactionMode)))
    items.append(.init(title: strings().starListTransactionsOutgoing, index: 2, uniqueId: 2, selected: transactionMode == .outgoing, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: theme, equatable: UIEquatable(transactionMode)))
    return items
}

private final class FloatingHeaderView : Control {
    private let blurView = EdgeEffectView()
    private let textView = TextView()
    private let balanceView = InteractiveTextView()
    fileprivate let dismiss = ImageButton()
    private let currency: CurrencyAmount.Currency
    public required init(frame frameRect: NSRect, currency: CurrencyAmount.Currency, source: Star_ListScreenSource, myBalance: StarsAmount) {
        self.currency = currency
        super.init(frame: frameRect)
        addSubview(blurView)
        addSubview(textView)
        addSubview(dismiss)
        addSubview(balanceView)
        
        blurView.isEventLess = true
        blurView.layer?.opacity = 0
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.layer?.opacity = 0
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.layer?.masksToBounds = false
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true

        let text: String
        switch source {
        case let .buy(_, amount):
            if let amount {
                let need = Int(amount - myBalance.value)
                text = strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator)
            } else {
                text = strings().starListGetStars
            }
            balanceView.isHidden = false
        case let .purchase(_, requested):
            let need = Int(requested - myBalance.value)
            text = strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator)
            balanceView.isHidden = false
        case let .purchaseSubscribe(_, requested):
            let need = Int(requested - myBalance.value)
            text = strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator)
            balanceView.isHidden = false
        case .account:
            switch currency {
            case .stars:
                text = strings().starListTelegramStars
            case .ton:
                text = strings().starListTon
            }
            balanceView.isHidden = true
        case .reactions:
            text = strings().starListTelegramStars
            balanceView.isHidden = false
        case let .prolongSubscription(_, requested):
            let need = Int(requested - myBalance.value)
            text = strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator)
            balanceView.isHidden = false
        case .gift:
            text = strings().starsGiftTitle
            balanceView.isHidden = true
        }
        
        let layout = TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .medium(.text)))
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
    }
    
    public func update(myBalance: StarsAmount, context: (any AccountContextProtocol)) {
        
        let balance = NSMutableAttributedString()
        balance.append(string: strings().starListMyBalance(clown + TINY_SPACE, myBalance.value.formattedWithSeparator), color: theme.colors.text, font: .normal(.text))
        balance.detectBoldColorInString(with: .medium(.text))
        switch currency {
        case .ton:
            balance.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.accent, playPolicy: .onceEnd), for: clown)
        case .stars:
            balance.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file, playPolicy: .onceEnd), for: clown)
        }
        
        let balanceLayout: TextViewLayout = .init(balance, alignment: .right)
        balanceLayout.measure(width: .greatestFiniteMagnitude)

        self.balanceView.set(text: balanceLayout, context: context)
        
    }
    
    public func updateScrolled(_ scrolled: Bool, animated: Bool) {
        blurView.change(opacity: scrolled ? 1 : 0, animated: animated)
        textView.change(opacity: scrolled ? 1 : 0, animated: animated)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        blurView.frame = bounds
        let fadeSize = max(1, bounds.height * 0.6)
        let blur = System.blurEnabled ? EdgeEffectView.Blur(rect: bounds, edgeSize: fadeSize) : nil
        blurView.update(color: theme.colors.listBackground, blur: blur, alpha: 0.6, edge: .bottom, edgeSize: fadeSize, rect: bounds, transition: .immediate)
        textView.center()
        dismiss.centerY(x: 13)
        balanceView.centerY(x: frame.width - balanceView.frame.width - 13)
    }
}

private final class BalanceItem : GeneralRowItem {
    fileprivate let myBalance: StarsAmount
    fileprivate let myBalanceLayout: TextViewLayout
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let infoLayout: TextViewLayout
    fileprivate let buyMore: ()->Void
    fileprivate let giftStars: ()->Void
    fileprivate let stats: ()->Void
    fileprivate let giftPremiumLayout: TextViewLayout?
    fileprivate let canWithdraw: Bool
    fileprivate let currency: CurrencyAmount.Currency
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), currency: CurrencyAmount.Currency, myBalance: StarsAmount, viewType: GeneralViewType, canWithdraw: Bool, buyMore: @escaping()->Void, giftStars: @escaping()->Void, stats: @escaping()->Void) {
        self.myBalance = myBalance
        self.currency = currency
        self.context = context
        self.buyMore = buyMore
        self.giftStars = giftStars
        self.stats = stats
        self.canWithdraw = canWithdraw
        let attr = NSMutableAttributedString()
        switch currency {
        case .stars:
            attr.append(string: myBalance.value.formattedWithSeparator, color: theme.colors.text, font: .medium(40))
        case .ton:
            attr.append(string: formatCurrencyAmount(myBalance.value, currency: TON).prettyCurrencyNumberUsd, color: theme.colors.text, font: .medium(40))
        }
        self.myBalanceLayout = .init(attr)
        self.myBalanceLayout.measure(width: .greatestFiniteMagnitude)
        
        let infoString: String
        switch currency {
        case .stars:
            infoString = strings().starListYourBalance
        case .ton:
            let usd_rate = context.appConfiguration.getGeneralValueDouble("ton_usd_rate", orElse: 3)
            let value = Double(formatCurrencyAmount(myBalance.value, currency: TON)) ?? 0
            infoString = "~\("\(value * usd_rate)".prettyCurrencyNumberUsd)$"
        }
        
        self.infoLayout = .init(.initialize(string: infoString, color: theme.colors.grayText, font: .normal(.header)))
        self.infoLayout.measure(width: .greatestFiniteMagnitude)
        
        
        switch currency {
        case .stars:
            let giftAttr = NSMutableAttributedString()
            giftAttr.append(string: strings().starsGiftToFriends(clown_space), color: theme.colors.accent, font: .normal(.title))
            giftAttr.insertEmbedded(.embedded(name: "Icon_Gift_Stars", color: theme.colors.accent, resize: false), for: clown)
            self.giftPremiumLayout = TextViewLayout(giftAttr)
        case .ton:
            self.giftPremiumLayout = nil
        }
        
        
        
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.giftPremiumLayout?.measure(width: blockWidth - 40)
        return true
    }
    
    public override var height: CGFloat {
        
        var height: CGFloat = 10 + myBalanceLayout.layoutSize.height + infoLayout.layoutSize.height + 10
        
        if !actionIsHidden {
            height += 40 + 20
        }
        
        if let giftPremiumLayout {
            height += (giftPremiumLayout.layoutSize.height + 10)
        }
        return  height
    }
    
    override var accessibilityLabel: String? {
        return strings().starListYourBalance
    }
    
    override var accessibilityValue: String? {
        switch currency {
        case .stars:
            return "\(myBalanceLayout.attributedString.string) \(strings().voiceOverCommonStars)"
        case .ton:
            return "\(myBalanceLayout.attributedString.string) TON, \(infoLayout.attributedString.string)"
        }
    }
    
    public override func viewClass() -> AnyClass {
        return BalanceView.self
    }
    
    public var actionText: String {
        switch currency {
        case .ton:
            return strings().starListTopUp
        default:
            return self.canWithdraw ? strings().starListTopUp : strings().starListBuyMoreStars
        }
    }
    
    public var actionIsHidden: Bool {
        switch currency {
        case .ton:
            #if DEBUG || STABLE || BETA
            return false
            #endif
            return true
        case .stars:
            return false
        }
    }
    
    public var currencyFile: TelegramMediaFile {
        switch currency {
        case .stars:
            return LocalAnimatedSticker.star_currency_new.file
        case .ton:
            return LocalAnimatedSticker.ton_logo.file
        }
    }
}

private final class BalanceView: GeneralContainableRowView {
    private let balance = InteractiveTextView()
    private let info = TextView()
    private let action = TextButton()
    private var withdrawAction: TextButton?
    private var star: InlineStickerView?
    private let container = View()
    private var giftStars: InteractiveTextView?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.addSubview(balance)
        addSubview(container)
        addSubview(info)
        addSubview(action)
        action.autohighlight = false
        action.scaleOnClick = true
        action.layer?.cornerRadius = 20
        
        balance.userInteractionEnabled = false
        info.userInteractionEnabled = false
        info.isSelectable = false
        
       
        
        action.set(handler: { [weak self] _ in
            if let item = self?.item as? BalanceItem {
                item.buyMore()
            }
        }, for: .Click)
        
       
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? BalanceItem else {
            return
        }
        
        if let giftStars = item.giftPremiumLayout {
            let current: InteractiveTextView
            if let view = self.giftStars {
                current = view
            } else {
                current = InteractiveTextView(frame: giftStars.layoutSize.bounds)
                current.userInteractionEnabled = true
                current.scaleOnClick = true
                self.giftStars = current
                addSubview(current)
            }
            current.set(text: giftStars, context: item.context)
            
            current.setSingle(handler: { [weak self] _ in
                if let item = self?.item as? BalanceItem {
                    item.giftStars()
                }
            }, for: .Click)
            current.set(text: item.giftPremiumLayout, context: item.context)
            
        } else if let view = giftStars {
            performSubviewRemoval(view, animated: animated)
            self.giftStars = nil
        }
        
        
        
        if self.star == nil {
            let view = InlineStickerView(account: item.context.account, file: item.currencyFile, size: NSMakeSize(item.myBalanceLayout.layoutSize.height - 4, item.myBalanceLayout.layoutSize.height - 4))
            self.star = view
            container.addSubview(view)
        }
        
        self.balance.set(text: item.myBalanceLayout, context: item.context)
        self.info.update(item.infoLayout)
        
        container.setFrameSize(container.subviewsWidthSize)
        
        action.set(font: .medium(.text), for: .Normal)
        action.set(color: theme.colors.underSelectedColor, for: .Normal)
        action.set(background: theme.colors.accent, for: .Normal)
        action.set(text: item.actionText, for: .Normal)
        
        action.isHidden = item.actionIsHidden
        
        
        if item.canWithdraw {
            let current: TextButton
            if let view = self.withdrawAction {
                current = view
            } else {
                current = TextButton()
                addSubview(current)
                self.withdrawAction = current
            }
            
            current.set(font: .medium(.text), for: .Normal)
            current.set(color: theme.colors.underSelectedColor, for: .Normal)
            current.set(background: theme.colors.accent, for: .Normal)
            switch item.currency {
            case .stars:
                current.set(text: strings().starListWithdraw, for: .Normal)
            case .ton:
                current.set(text: strings().fragmentStarWithdraw, for: .Normal)
            }
            current.autohighlight = false
            current.scaleOnClick = true
            current.layer?.cornerRadius = 20
            
            current.setSingle(handler: { [weak item] _ in
                item?.stats()
            }, for: .Click)

        } else if let view = self.withdrawAction {
            performSubviewRemoval(view, animated: animated)
            self.withdrawAction = nil
        }
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        
        container.centerX(y: 10)
        if let star {
            star.centerY(x: 0, addition: -3)
            balance.centerY(x: star.frame.maxX)
        }
        info.centerX(y: container.frame.maxY)
        
        var inset: CGFloat = 0
        if let giftStars {
            inset = giftStars.frame.height + 10
        }
        
        if let withdrawAction {
            let itemWidth = (containerView.frame.width - 40 - 10) / 2
            action.frame = NSMakeRect(20, containerView.frame.height - 20 - 40 - inset, itemWidth, 40)
            withdrawAction.frame = NSMakeRect(action.frame.maxX + 10, containerView.frame.height - 20 - 40 - inset, itemWidth, 40)
        } else {
            action.frame = NSMakeRect(20, containerView.frame.height - 20 - 40 - inset, containerView.frame.width - 40, 40)
        }
        
        
        if let giftStars {
            giftStars.centerX(y: containerView.frame.height - giftStars.frame.height - 15)
        }
    }
}

private final class HeaderItem : GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let header: TextViewLayout
    fileprivate let headerText: TextViewLayout
    fileprivate let source: Star_ListScreenSource
    fileprivate let arguments: Arguments
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), currency: CurrencyAmount.Currency, myBalance: StarsAmount, source: Star_ListScreenSource, viewType: GeneralViewType, openRecommendedApps: @escaping()->Void, arguments: Arguments) {
        self.context = context
        self.source = source
        self.arguments = arguments
        
        let headerAttr = NSMutableAttributedString()
        var headerInfo = NSMutableAttributedString()
        
        switch source {
        case let .buy(suffix, amount):
            if let amount {
                let need = Int(amount - myBalance.value)
                headerAttr.append(string: strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator), color: theme.colors.text, font: .medium(.header))
            } else {
                headerAttr.append(string: strings().starListGetStars, color: theme.colors.text, font: .medium(.header))
            }
            if let suffix {
                let suffixKey = "Star.Buy.Custom_\(suffix)"
                let text: String = _NSLocalizedString(suffixKey)
                if text == suffixKey {
                    headerInfo.append(string: strings().starListHowMany, color: theme.colors.text, font: .normal(.text))
                } else {
                    headerInfo.append(string: _NSLocalizedString("Star.Buy.Custom_\(suffix)"), color: theme.colors.text, font: .normal(.text))
                }
            } else {
                headerInfo.append(string: strings().starListHowMany, color: theme.colors.text, font: .normal(.text))
            }
        case let .purchase(peer, requested):
            let need = Int(requested - myBalance.value)
            headerAttr.append(string: strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator), color: theme.colors.text, font: .medium(.header))
            headerInfo.append(string: strings().starListBuyAndUse(peer._asPeer().displayTitle), color: theme.colors.text, font: .normal(.text))
        case .account:
            switch currency {
            case .stars:
                headerAttr.append(string: strings().starListTelegramStars, color: theme.colors.text, font: .medium(.header))
                headerInfo.append(string: strings().starListBuyAndUserNobot, color: theme.colors.text, font: .normal(.text))
            case .ton:
                headerAttr.append(string: strings().starListTon, color: theme.colors.text, font: .medium(.header))
                headerInfo.append(string: strings().starListTonInfo, color: theme.colors.text, font: .normal(.text))
            }
        case let .reactions(_, requested):
            let need = Int(requested - myBalance.value)
            headerAttr.append(string: strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator), color: theme.colors.text, font: .medium(.header))
            headerInfo.append(string: strings().starListBuyAndUserNobot, color: theme.colors.text, font: .normal(.text))
        case let .prolongSubscription(peer, requested):
            let need = Int(requested - myBalance.value)
            headerAttr.append(string: strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator), color: theme.colors.text, font: .medium(.header))
            headerInfo.append(string: strings().starBuyScreenProlongSubs(peer._asPeer().displayTitle), color: theme.colors.text, font: .normal(.text))
        case let .purchaseSubscribe(peer, requested):
            let need = Int(requested - myBalance.value)
            headerAttr.append(string: strings().starListStarsNeededOther(need).replacingOccurrences(of: "\(need)", with: need.formattedWithSeparator), color: theme.colors.text, font: .medium(.header))
            headerInfo.append(string: strings().starBuyScreenPurschaseSub(peer._asPeer().displayTitle), color: theme.colors.text, font: .normal(.text))

        case let .gift(peer):
            headerAttr.append(string: strings().starsGiftTitle, color: theme.colors.text, font: .medium(.header))
            
            let text = strings().starBuyScreenGift(peer._asPeer().displayTitle)
            
            headerInfo = parseMarkdownIntoAttributedString(text, attributes: .init(body: .init(font: .normal(.text), textColor: theme.colors.text), link: .init(font: .normal(.text), textColor: theme.colors.accent), linkAttribute: { contents in
                return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { value in
                    openRecommendedApps()
                }))
            })).mutableCopy() as! NSMutableAttributedString
            
        }
        headerAttr.detectBoldColorInString(with: .medium(.header))
        headerInfo.detectBoldColorInString(with: .medium(.text))

        self.header = .init(headerAttr, alignment: .center)
        self.headerText = .init(headerInfo, alignment: .center)
        
        self.headerText.interactions = LinkHooks.shared.globalLinkExecutor()
        
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: NSEdgeInsets())
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        header.measure(width: width - 40)
        headerText.measure(width: width - 40)
        return true
    }
    
    public override var height: CGFloat {
        return 150 + header.layoutSize.height + 10 + headerText.layoutSize.height
    }
    
    override var accessibilityLabel: String? {
        return header.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let value = headerText.attributedString.string
        return value.isEmpty ? nil : value
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
}

private final class HeaderView : GeneralContainableRowView {
    private var sceneView: (NSView & PremiumSceneView)!
    private let header = TextView()
    private let headerInfo = TextView()
    
    private var avatarView: AvatarControl?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(header)
        addSubview(headerInfo)
        
        header.userInteractionEnabled = false
        header.isSelectable = false
        headerInfo.isSelectable = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        switch item.arguments.currency {
        case .ton:
            if self.sceneView == nil {
                self.sceneView = PremiumDiamondSceneView(frame: NSMakeRect(0, 0, frame.width, 150))
                addSubview(sceneView, positioned: .below, relativeTo: header)
                self.sceneView.sceneBackground = theme.colors.listBackground
            }
            (sceneView as? PremiumDiamondSceneView)?.initFallbackView(context: item.context)

        case .stars:
            if sceneView == nil {
                self.sceneView = GoldenStarSceneView(frame: NSMakeRect(0, 0, frame.width, 150))
                addSubview(sceneView, positioned: .below, relativeTo: header)
                self.sceneView.sceneBackground = theme.colors.listBackground
            }

        }
        

        
        switch item.source {
        case let .gift(peer):
            (sceneView as? GoldenStarSceneView)?.hideStar()
            let current: AvatarControl
            if let view = self.avatarView {
                current = view
            } else {
                current = AvatarControl(font: .avatar(20))
                current.setFrameSize(NSMakeSize(80, 80))
                self.avatarView = current
                addSubview(current)
            }
            current.setPeer(account: item.context.account, peer: peer._asPeer())
            
        default:
            (sceneView as? GoldenStarSceneView)?.showStar()
            if let avatarView {
                performSubviewRemoval(avatarView, animated: animated)
                self.avatarView = nil
            }
        }
        
        header.update(item.header)
        headerInfo.update(item.headerText)
        
        
        needsLayout = true
    }
    
    
    public override func layout() {
        super.layout()
        sceneView.centerX(y: 0)
        header.centerX(y: sceneView.frame.maxY - 20)
        headerInfo.centerX(y: header.frame.maxY + 10)
        
        avatarView?.centerX(y: 30)
    }
}


private final class Star_Item : GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let option: State.Option
    
    fileprivate let price: TextViewLayout
    fileprivate let textLayout: TextViewLayout
    
    fileprivate let starsCount: Int64
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), option: State.Option, viewType: GeneralViewType, action:@escaping()->Void) {
        self.context = context
        self.option = option
        self.price = .init(.initialize(string: option.formattedPrice, color: theme.colors.grayText, font: .normal(.text)))
        self.textLayout = .init(.initialize(string: strings().starListItemCountOther(Int(option.amount)).replacingOccurrences(of: "\(option.amount)", with: option.amount.formattedWithSeparator), color: theme.colors.text, font: .medium(.text)))
        
        self.starsCount = min(5, (Int64(option.id) ?? 0) + 1)
        
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action)
        
        price.measure(width: .greatestFiniteMagnitude)
        textLayout.measure(width: .greatestFiniteMagnitude)
    }
    
    public override var height: CGFloat {
        return 40
    }
    
    override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        return price.attributedString.string
    }
    
    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
    
    override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return Star_ItemView.self
    }
}

private final class Star_ItemView : GeneralContainableRowView {
    private let stars = View()
    private let textView = TextView()
    private let price = TextView()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(stars)
        addSubview(textView)
        addSubview(price)
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        price.userInteractionEnabled = false
        price.isSelectable = false
        
        containerView.setStateChangeHandler { [weak self] in
            self?.updateColors()
        }
        
        containerView.scaleOnClick = true
        
        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)

        stars.layer?.masksToBounds = false
        
    }
    
    public override func updateColors() {
        super.updateColors()
        updateHighlightColors()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? Star_Item else {
            return
        }
        
        textView.update(item.textLayout)
        price.update(item.price)
        
        while stars.subviews.count > item.starsCount {
            stars.subviews.last?.removeFromSuperview()
        }
        
        for i in Int64(stars.subviews.count) ..< item.starsCount {
            if i == 0 {
                let view = InlineStickerView(account: item.context.account, file: LocalAnimatedSticker.star_currency_new.file, size: NSMakeSize(20, 20))
                stars.addSubview(view)
            } else {
                let view = InlineStickerView(account: item.context.account, file: LocalAnimatedSticker.star_currency_part_new.file, size: NSMakeSize(20, 20))
                stars.addSubview(view)
            }
        }
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        price.centerY(x: containerView.frame.width - price.frame.width - 10)
        stars.frame = NSMakeRect(10, 0, 20, containerView.frame.height)
        
        for (i, star) in stars.subviews.enumerated() {
            if i == 0 {
                star.centerY(x: 0)
            } else {
                star.centerY(x: CGFloat(i) * 3)
            }
        }
        
        textView.centerY(x: 10 + 20 + CGFloat(stars.subviews.count * 3) + 5)
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let currency: CurrencyAmount.Currency
    public let source: Star_ListScreenSource
    public let reveal: ()->Void
    public let openLink:(String)->Void
    public let buyMore:()->Void
    public let giftStars:()->Void
    public let toggleFilterMode:(State.TransactionMode)->Void
    public let buy:(State.Option)->Void
    public let loadMoreTransactions:()->Void
    public let loadMoreSubscriptions:()->Void
    public let openTransaction:(Star_Transaction)->Void
    public let openSubscription:(Star_Subscription)->Void
    public let openRecommendedApps:()->Void
    public let openAffiliate:()->Void
    public let stats:()->Void
    public init(context: (any AccountContextProtocol), currency: CurrencyAmount.Currency, source: Star_ListScreenSource, reveal: @escaping()->Void, openLink:@escaping(String)->Void, buyMore:@escaping()->Void, giftStars:@escaping()->Void, toggleFilterMode:@escaping(State.TransactionMode)->Void, buy:@escaping(State.Option)->Void, loadMoreTransactions:@escaping()->Void, loadMoreSubscriptions:@escaping()->Void, openTransaction:@escaping(Star_Transaction)->Void, openSubscription:@escaping(Star_Subscription)->Void, openRecommendedApps:@escaping()->Void, openAffiliate:@escaping()->Void, stats:@escaping()->Void) {
        self.context = context
        self.currency = currency
        self.source = source
        self.reveal = reveal
        self.openLink = openLink
        self.buyMore = buyMore
        self.giftStars = giftStars
        self.toggleFilterMode = toggleFilterMode
        self.buy = buy
        self.loadMoreTransactions = loadMoreTransactions
        self.loadMoreSubscriptions = loadMoreSubscriptions
        self.openTransaction = openTransaction
        self.openSubscription = openSubscription
        self.openRecommendedApps = openRecommendedApps
        self.openAffiliate = openAffiliate
        self.stats = stats
    }
}

private struct State : Equatable {
    public struct Balance : Equatable {
        public var ton: Int64
        public var usdRate: Double
        
        public var fractional: Double {
            return currencyToFractionalAmount(value: Double(ton), currency: "TON") ?? 0
        }
        
        public var usd: String {
            return "$" + "\(self.fractional * self.usdRate)".prettyCurrencyNumberUsd
        }
        public init(ton: Int64, usdRate: Double) {
            self.ton = ton
            self.usdRate = usdRate
        }
    }
    public struct Overview : Equatable {
        public var balance: Balance
        public var last: Balance
        public var all: Balance
        public init(balance: Balance, last: Balance, all: Balance) {
            self.balance = balance
            self.last = last
            self.all = all
        }
    }
    public enum TransactionMode : Equatable {
        case all
        case incoming
        case outgoing
    }
    public struct Option : Equatable {
        public let amount: Int64
        public let price: Int64
        public let currency: String
        public let id: String
        
        public let storeProduct: InAppPurchaseManager.Product?
        
        public var native: StarsTopUpOption {
            return .init(count: amount, storeProductId: storeProduct?.id, currency: currency, amount: price, isExtended: false)
        }
        
        
        public var formattedPrice: String {
            if let storeProduct {
                return formatCurrencyAmount(storeProduct.priceCurrencyAndAmount.amount, currency: storeProduct.priceCurrencyAndAmount.currency)
            } else {
                return formatCurrencyAmount(price, currency: currency)
            }
        }
        public init(amount: Int64, price: Int64, currency: String, id: String, storeProduct: InAppPurchaseManager.Product?) {
            self.amount = amount
            self.price = price
            self.currency = currency
            self.id = id
            self.storeProduct = storeProduct
        }
    }
    public var currency: CurrencyAmount.Currency
    public var myBalance: StarsAmount? = nil
    public var options: [Option]? = nil
    public var transactions: [Star_Transaction]? = nil
    public var revealed: Bool = false
    public var transactionMode: TransactionMode = .all
    
    public var premiumProducts: [InAppPurchaseManager.Product] = []
    public var canMakePayment: Bool
    
    public var starsState: StarsContext.State?
    
    public var subscriptions: [Star_Subscription] = []
    public var revenueStats: StarsRevenueStats?
    
    public var overview: Overview = .init(balance: .init(ton: 0, usdRate: 0), last: .init(ton: 0, usdRate: 0), all: .init(ton: 0, usdRate: 0))

    public var withdrawError: RequestStarsRevenueWithdrawalError? = nil
    
    public var canWithdraw: Bool {
        if let revenueStats {
            return revenueStats.balances.withdrawEnabled == true
        } else {
            return false
        }
    }

}

private let _id_header = InputDataIdentifier("_id_header")
private func _id_option(_ option: State.Option) -> InputDataIdentifier {
    return .init("_id_\(option.id)")
}
private func _id_transaction(_ transaction: Star_Transaction) -> InputDataIdentifier {
    return .init("_id_\(transaction.id)_\(transaction.type)")
}
private func _id_subscription(_ subscription: Star_Subscription) -> InputDataIdentifier {
    return .init("_id_\(subscription.peer.id.toInt64())_\(subscription.id)")
}


private let _id_show_more = InputDataIdentifier("_id_show_more")
private let _id_balance = InputDataIdentifier("_id_balance")

private let _id_transaction_mode = InputDataIdentifier("_id_transaction_mode")
private let _id_empty_transactions = InputDataIdentifier("_id_empty_transactions")

private let _id_load_more = InputDataIdentifier("_id_load_more")
private let _id_loading = InputDataIdentifier("_id_loading")

private let _id_loading_subs = InputDataIdentifier("_id_loading_subs")
private let _id_load_more_subs = InputDataIdentifier("_id_load_more_subs")

private func _id_overview(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_overview_\(index)")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    if let balance = state.myBalance {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return HeaderItem(initialSize, stableId: stableId, context: arguments.context, currency: arguments.currency, myBalance: balance, source: arguments.source, viewType: .legacy, openRecommendedApps: arguments.openRecommendedApps, arguments: arguments)
        }))
        
        switch arguments.source {
        case .buy, .purchase, .prolongSubscription, .gift, .reactions, .purchaseSubscribe:
            
            struct Tuple : Equatable {
                let option: State.Option
                let viewType: GeneralViewType
            }
            
            var tuples: [Tuple] = []

            let alwaysShow: [Int64] = [15, 75, 250, 500, 1000, 2500]


            if var options = state.options {
                
                switch arguments.source {
                case let .purchase(_, amount):
                    let minumum = max(0, amount - (state.myBalance?.value ?? 0))
                    options.removeAll(where: {
                        $0.amount < minumum
                    })
                default:
                    break
                }
                
                let revealed = options.count < alwaysShow.count || state.revealed

                
                for option in options {
                    if revealed || alwaysShow.contains(option.amount) {
                        tuples.append(.init(option: option, viewType: .singleItem))
                    }
                }
                
                for tuple in tuples {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_option(tuple.option), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                        return Star_Item(initialSize, stableId: stableId, context: arguments.context, option: tuple.option, viewType: tuple.viewType, action: {
                            arguments.buy(tuple.option)
                        })
                    }))
                    if tuple != tuples.last {
                        entries.append(.sectionId(sectionId, type: .normal))
                        sectionId += 1
                    }
                }
              
                if !revealed {
                    entries.append(.sectionId(sectionId, type: .normal))
                    sectionId += 1
                    
                    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_show_more, data: .init(name: strings().starListItemShowMore, color: theme.colors.accent, type: .image(TelegramThemeHooks.shared.image(.iconHorizontalChevron).precomposed(theme.colors.accent)), viewType: .singleItem, action: arguments.reveal)))
                }
            } else {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                    return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .singleItem)
                }))
            }
            
            
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
            
            let text = strings().starListTos
            
            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { link in
                arguments.openLink(link)
            }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem, centerViewAlignment: true, alignment: .center)))
            index += 1
        case .account:
            
            
            if let _ = state.revenueStats, state.currency == .ton {
                
                struct Tuple : Equatable {
                    let overview: Fragment_OverviewRowItem.Overview
                    let viewType: GeneralViewType
                }
                
                let tuples: [Tuple] = [
                    .init(overview: .init(amount: state.overview.balance.ton, usdAmount: state.overview.balance.usd, info: strings().monetizationOverviewAvailable, stars: nil), viewType: .firstItem),
                    .init(overview: .init(amount: state.overview.all.ton, usdAmount: state.overview.all.usd, info: strings().monetizationOverviewTotal, stars: nil), viewType: .lastItem)
                ]
                
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().monetizationOverviewTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
                index += 1
                
                for (i, tuple) in tuples.enumerated() {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_overview(i), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                        return Fragment_OverviewRowItem(initialSize, stableId: stableId, context: arguments.context, overview: tuple.overview, currency: .ton, viewType: tuple.viewType)
                    }))
                }
                                                
                entries.append(.sectionId(sectionId, type: .normal))
                sectionId += 1
            }
            
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_balance, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return BalanceItem(initialSize, stableId: stableId, context: arguments.context, currency: arguments.currency, myBalance: state.myBalance ?? .init(value: 0, nanos: 0), viewType: .singleItem, canWithdraw: state.canWithdraw, buyMore: arguments.buyMore, giftStars: arguments.giftStars, stats: arguments.stats)
            }))
            
            if state.canWithdraw, arguments.currency == .ton {
                entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().starListTonWithdrawInfo, linkHandler: { link in
                    LinkHooks.shared.openExternalLink(link, false)
                }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
                index += 1
            }
            
            
            let affiliateEnabled = arguments.context.appConfiguration.getBoolValue("starref_connect_allowed", orElse: false)
            
            if affiliateEnabled, arguments.currency == .stars {
                entries.append(.sectionId(sectionId, type: .normal))
                sectionId += 1
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("affiliate"), data: .init(name: strings().affilateProgramEarn, color: theme.colors.text, icon: TelegramThemeHooks.shared.image(.iconAffiliateEarnStars).precomposed(flipVertical: true), type: .next, viewType: .singleItem, description: strings().affilateProgramEarnInfo, descTextColor: theme.colors.grayText, action: arguments.openAffiliate, afterNameImage: generateTextIcon_NewBadge_Flipped(bgColor: theme.colors.accent, textColor: theme.colors.underSelectedColor))))
            }
            
            
            if !state.subscriptions.isEmpty, arguments.currency == .stars {
                
                entries.append(.sectionId(sectionId, type: .normal))
                sectionId += 1
                
                struct Tuple : Equatable {
                    let subscription: Star_Subscription
                    let viewType: GeneralViewType
                }
                var tuples: [Tuple] = []
                for (i, subscription) in state.subscriptions.enumerated() {
                    var viewType: GeneralViewType = bestGeneralViewType(state.subscriptions, for: i)
                    if i == state.subscriptions.count - 1, state.starsState?.canLoadMoreSubscriptions == true || state.starsState?.isLoading == true {
                        viewType = .innerItem
                    }
                    tuples.append(.init(subscription: subscription, viewType: viewType))
                }
                
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starBuyScreenMySubs), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
                index += 1

                
                for tuple in tuples {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_subscription(tuple.subscription), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                        return Star_SubscriptionRowItem(initialSize, stableId: stableId, context: arguments.context, viewType: tuple.viewType, subscription: tuple.subscription, callback: arguments.openSubscription)
                    }))
                }
                
                if state.starsState?.isLoading == true {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading_subs, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                        return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .lastItem)
                    }))
                } else if state.starsState?.canLoadMoreSubscriptions == true {
                    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_load_more_subs, data: .init(name: strings().starListTransactionsShowMore, color: theme.colors.accent, icon: theme.icons.chatSearchUp, viewType: .lastItem, action: arguments.loadMoreSubscriptions, iconTextInset: 42)))
                }
            }
            
            if let transactions = state.transactions, !transactions.isEmpty {
                entries.append(.sectionId(sectionId, type: .normal))
                sectionId += 1
                
                struct Tuple : Equatable {
                    let transaction: Star_Transaction
                    let viewType: GeneralViewType
                }
                
                let transactions = transactions.filter { transaction in
                    switch state.transactionMode {
                    case .all:
                        return true
                    case .incoming:
                        if case .incoming = transaction.type {
                            return true
                        } else {
                            return false
                        }
                    case .outgoing:
                        if case .outgoing = transaction.type {
                            return true
                        } else {
                            return false
                        }
                    }
                }
                
                var tuples: [Tuple] = []
                for (i, transaction) in transactions.enumerated() {
                    var viewType = bestGeneralViewTypeAfterFirst(transactions, for: i)
                    if i == transactions.count - 1, state.starsState?.canLoadMoreTransactions == true || state.starsState?.isLoading == true {
                        viewType = .innerItem
                    }
                    tuples.append(.init(transaction: transaction, viewType: viewType))
                }
                
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starListTransactionsHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
                index += 1
                
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_transaction_mode, equatable: .init(state.transactionMode), comparable: nil, item: { initialSize, stableId in
                    return StarTransactionTabsRowItem(initialSize, stableId: stableId, items: transactionSegments(state.transactionMode), viewType: .firstItem, callback: { uniqueId in
                        switch uniqueId {
                        case 0:
                            arguments.toggleFilterMode(.all)
                        case 1:
                            arguments.toggleFilterMode(.incoming)
                        case 2:
                            arguments.toggleFilterMode(.outgoing)
                        default:
                            break
                        }
                    })
                }))
                
                if !transactions.isEmpty {
                    for tuple in tuples {
                        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_transaction(tuple.transaction), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                            return Star_TransactionItem(initialSize, stableId: stableId, context: arguments.context, viewType: tuple.viewType, transaction: tuple.transaction, callback: arguments.openTransaction)
                        }))
                    }
                    if state.starsState?.isLoading == true {
                        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                            return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .lastItem)
                        }))
                    } else if state.starsState?.canLoadMoreTransactions == true {
                        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_load_more, data: .init(name: strings().starListTransactionsShowMore, color: theme.colors.accent, icon: theme.icons.chatSearchUp, viewType: .lastItem, action: arguments.loadMoreTransactions, iconTextInset: 42)))
                    }
                } else {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_empty_transactions, equatable: .init(state.transactionMode), comparable: nil, item: { initialSize, stableId in
                        let text: String
                        switch state.transactionMode {
                        case .all:
                            text = strings().starListTransactionsEmptyAll
                        case .incoming:
                            text = strings().starListTransactionsEmptyIncoming
                        case .outgoing:
                            text = strings().starListTransactionsEmptyOutgoing
                        }
                        return GeneralBlockTextRowItem(initialSize, stableId: stableId, viewType: .lastItem, text: text, font: .normal(.text))
                    }))
                }
            }
        }
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    } else {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("loading"), equatable: nil, comparable: nil, item: { initialSize, stableId in
            return LoadingTableItem(initialSize, height: 200, stableId: stableId, backgroundColor: theme.colors.listBackground)
        }))
    }
    
    
    return entries
}

public enum Star_ListScreenSource : Equatable {
    case buy(suffix: String?, amount: Int64?)
    case purchase(EnginePeer, Int64)
    case purchaseSubscribe(EnginePeer, Int64)
    case account
    case prolongSubscription(EnginePeer, Int64)
    case gift(EnginePeer)
    case reactions(EnginePeer, Int64)

    public var spendPurposePeerId: PeerId? {
        switch self {
        case let .purchase(peer, _), let .purchaseSubscribe(peer, _), let .prolongSubscription(peer, _), let .reactions(peer, _):
            return peer.id
        default:
            return nil
        }
    }
}

public func starsSpendTopupInvoiceDisabled(context: (any AccountContextProtocol), source: Star_ListScreenSource) -> Bool {
    return source.spendPurposePeerId != nil && context.appConfiguration.getBoolValue("stars_spend_topup_invoice_disabled", orElse: false)
}

public func showStarsTopup(context: (any AccountContextProtocol), currency: CurrencyAmount.Currency = .stars, source: Star_ListScreenSource, for window: Window) {
    #if !APP_STORE
    if starsSpendTopupInvoiceDisabled(context: context, source: source) {
        alert(for: window, info: strings().starListSpendTopupUnavailable)
        return
    }
    #endif
    showModal(with: Star_ListScreen(context: context, currency: currency, source: source), for: window)
}


public func Star_ListScreen(context: (any AccountContextProtocol), currency: CurrencyAmount.Currency = .stars, source: Star_ListScreenSource) -> InputDataModalController {

    let screen = StarsScreenContext(context: context, source: source)
    let actionsDisposable = screen.disposables
    let paymentDisposable = MetaDisposable()
    actionsDisposable.add(paymentDisposable)
    let inAppPurchaseManager = context.inAppPurchaseManager
    
    let starsContext: StarsContext = context.currencyContext(currency)
    
    let starsSubscriptionsContext = context.starsSubscriptionsContext
    
    
    let transactions = context.engine.payments.peerStarsTransactionsContext(subject: .starsContext(starsContext), mode: .all)

    starsContext.load(force: true)
    starsSubscriptionsContext.load(force: true)
    
    var canMakePayment: Bool = true
    #if APP_STORE || DEBUG
    canMakePayment = inAppPurchaseManager.canMakePayments
    #endif
    
    
    
    let initialState = State(currency: currency, options: nil, transactions: nil, canMakePayment: canMakePayment, subscriptions: [])
    
    
    
    let products: Signal<[InAppPurchaseManager.Product], NoError>
    #if APP_STORE || DEBUG
    products = inAppPurchaseManager.availableProducts |> map {
        $0.filter { !$0.isSubscription }
    }
    #else
        products = .single([])
    #endif
    
    var close:(()->Void)? = nil
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        guard screen.isOpen else { return }
        statePromise.set(stateValue.modify (f))
    }
    
    switch source {
    case let .gift(peer):
        actionsDisposable.add(screen.preserving(combineLatest(context.engine.payments.starsGiftOptions(peerId: peer.id), products) |> deliverOnMainQueue).start(next: { value, products in
            let options:[State.Option] = value.compactMap { value in
                let product = products.first(where: { $0.id == value.storeProductId })
                return .init(amount: value.count, price: value.amount, currency: value.currency, id: "\(value.count)", storeProduct: product)
            }
            updateState { current in
                var current = current
                current.premiumProducts = products
                current.options = options
                return current
            }
        }))
    default:
        actionsDisposable.add(screen.preserving(combineLatest(context.engine.payments.starsTopUpOptions(), products) |> deliverOnMainQueue).start(next: { value, products in
            
            let options:[State.Option] = value.compactMap { value in
                let product = products.first(where: { $0.id == value.storeProductId })
                return .init(amount: value.count, price: value.amount, currency: value.currency, id: "\(value.count)", storeProduct: product)
            }
            updateState { current in
                var current = current
                current.premiumProducts = products
                current.options = options
                return current
            }
        }))
    }
    
    
    let starsRevenue = context.engine.payments.peerStarsRevenueContext(peerId: context.peerId, ton: currency == .ton)
    
    actionsDisposable.add(screen.preserving(combineLatest(starsContext.state, starsSubscriptionsContext.state, transactions.state, starsRevenue.state) |> deliverOnMainQueue).start(next: { state, subscriptionState, transactions, starsRevenue in
        updateState { current in
            var current = current
            current.myBalance = state?.balance
            current.revenueStats = starsRevenue.stats
            current.subscriptions = subscriptionState.subscriptions.map { value in
                let state: Star_Subscription.State
                if value.untilDate < context.timestamp, !value.flags.contains(.isCancelled) {
                    state = .expired
                } else {
                    if value.flags.contains(.isCancelled) {
                        state = .cancelled(refulfil: value.flags.contains(.canRefulfill))
                    } else {
                        state = .active(refulfil: value.flags.contains(.canRefulfill))
                    }
                }
                return .init(id: value.id, peer: value.peer, amount: value.pricing.amount, date: value.untilDate - value.pricing.period, renewDate: value.untilDate, state: state, native: value)
            }
            
            if let revenueStats = current.revenueStats {
                current.overview.balance = .init(ton: revenueStats.balances.availableBalance.amount.value, usdRate: revenueStats.usdRate)
                current.overview.all = .init(ton: revenueStats.balances.overallRevenue.amount.value, usdRate: revenueStats.usdRate)
                current.overview.last = .init(ton: revenueStats.balances.currentBalance.amount.value, usdRate: revenueStats.usdRate)
            }

            
            current.transactions = transactions.transactions.map { value in
                let type: Star_TransactionType
                var botPeer: EnginePeer?
                let incoming: Bool = value.count.amount.value > 0
                let source: Star_TransactionType.Source
                switch value.peer {
                case let .peer(peer):
                    source = .peer
                    botPeer = peer
                case .appStore:
                    source = .appstore
                case .fragment:
                    source = .fragment
                case .playMarket:
                    source = .playmarket
                case .premiumBot:
                    source = .premiumbot
                case .ads:
                    source = .ads
                case .unsupported:
                    source = .unknown
                case .apiLimitExtension:
                    source = .apiLimitExtension
                }
                if incoming {
                    type = .incoming(source)
                } else {
                    type = .outgoing(source)
                }
                return Star_Transaction(id: value.id, currency: value.count.currency, amount: value.count.amount, date: value.date, name: "", peer: botPeer, type: type, native: value)
            }
            current.starsState = state
            return current
        }
    }))
    
    actionsDisposable.add(screen.preserving(context.engine.peers.checkStarsRevenueWithdrawalAvailability() |> deliverOnMainQueue).start(error: { error in
        updateState { current in
            var current = current
            current.withdrawError = error
            return current
        }
    }))
    
    
    // The "spend purpose" peer for a Stars top-up — the commercial peer where the stars are actually spent
    // (a bot/channel purchase, subscription, or reaction), NOT the buyer. Matches iOS's `commercialPeerId`;
    // a plain top-up (`.buy`/`.account`) or a gift carries no spend-purpose peer. (Was `context.peerId` —
    // i.e. self — which mis-tagged every top-up's server-side spend purpose as the buyer.)
    let commercialPeerId: PeerId? = source.spendPurposePeerId

    let invoiceTopupDisabled = starsSpendTopupInvoiceDisabled(context: context, source: source)

    let buyNonStore:(State.Option)->Void = { option in
        guard screen.isOpen else { return }

        if invoiceTopupDisabled {
            showModalText(for: window, text: strings().starListSpendTopupUnavailable)
            return
        }

        guard let attempt = screen.purchase.begin() else { return }
        let invoiceSource: BotPaymentInvoiceSource
        switch source {
        case let .gift(peer):
            invoiceSource = .starsGift(peerId: peer.id, count: option.native.count, currency: option.native.currency, amount: option.native.amount)
        default:
            invoiceSource = .stars(option: option.native, peerId: commercialPeerId)
        }
        
        let request = MetaDisposable()
        paymentDisposable.set(request)
        let signal = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: invoiceSource), for: window)

        var receivedInvoice = false
        request.set(screen.preserving(signal |> take(1) |> deliverOnMainQueue).start(next: { invoice in
            receivedInvoice = true
            guard screen.purchase.isCurrent(attempt) else { return }
            if let controller = FeatureNavigationHooks.shared.makePaymentsCheckoutObserved(context, invoiceSource, invoice, completion: { status in
                guard screen.purchase.isCurrent(attempt) else { return }
                switch status {
                case .paid:
                    guard screen.purchase.finish(attempt, paid: true) else { return }
                    PlayConfetti(for: window, stars: true)
                    showModalText(for: window, text: strings().starListBuySuccessOther(Int(option.amount)).replacingOccurrences(of: "\(option.amount)", with: option.amount.formattedWithSeparator))
                    close?()
                case .cancelled:
                    break
                case .failed:
                    break
                }
            }) {
                let onDeinit = controller.onDeinit
                controller.onDeinit = {
                    onDeinit?()
                    screen.purchase.finish(attempt)
                }
                guard screen.purchase.isCurrent(attempt) else { return }
                showModal(with: controller, for: window)
            } else {
                screen.purchase.finish(attempt)
            }
        }, error: { error in
            guard screen.purchase.finish(attempt) else { return }
            showModalText(for: window, text: strings().paymentsInvoiceNotExists)
        }, completed: {
            if !receivedInvoice { screen.purchase.finish(attempt) }
        }))
    }
    
    let buyAppStore:(State.Option)->Void = { option in
        guard screen.isOpen else { return }
        
        let storeProduct = option.storeProduct

        guard let storeProduct = storeProduct else {
            buyNonStore(option)
            return
        }
        
        guard let attempt = screen.purchase.begin() else { return }
        let attemptDisposable = DisposableSet()
        paymentDisposable.set(attemptDisposable)
        let lockModal = PremiumLockModalController()
        attemptDisposable.add(ActionDisposable { lockModal.close() })
        
        var needToShow = true
        delay(0.2, closure: {
            if needToShow && screen.isOpen {
                showModal(with: lockModal, for: window)
            }
        })
        
        let purpose: AppStoreTransactionPurpose
        switch source {
        case let .gift(peer):
            purpose = .starsGift(peerId: peer.id, count: option.native.count, currency: storeProduct.priceCurrencyAndAmount.currency, amount: storeProduct.priceCurrencyAndAmount.amount)
        default:
            purpose = .stars(count: option.amount, currency: storeProduct.priceCurrencyAndAmount.currency, amount: storeProduct.priceCurrencyAndAmount.amount, peerId: commercialPeerId)
        }
        
        var checkedEligibility = false
        attemptDisposable.add(screen.preserving(context.engine.payments.canPurchasePremium(purpose: purpose)
                 |> take(1) |> deliverOnMainQueue).start(next: { [weak lockModal] available in
            checkedEligibility = true
            guard screen.purchase.isCurrent(attempt) else { return }
            if available {
                let request = MetaDisposable()
                attemptDisposable.add(request)
                let signal = inAppPurchaseManager.buyProduct(storeProduct, purpose: purpose) |> take(1) |> deliverOnMainQueue
                guard screen.purchase.isCurrent(attempt) else { return }
                request.set(screen.preserving(signal).start(next: { [weak lockModal] status in
                    guard screen.purchase.finish(attempt, paid: true) else { return }
                    lockModal?.close()
                    needToShow = false
                    inAppPurchaseManager.finishAllTransactions()
                    close?()
                    
                    
                    delay(0.2, closure: {
                        PlayConfetti(for: window, stars: true)
                        showModalText(for: window, text: strings().starListBuySuccessOther(Int(option.amount)).replacingOccurrences(of: "\(option.amount)", with: option.amount.formattedWithSeparator))
                    })
                    
                }, error: { [weak lockModal] error in
                    guard screen.purchase.finish(attempt) else { return }
                    needToShow = false
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
                    inAppPurchaseManager.finishAllTransactions()
                    showModalText(for: window, text: errorText)
                }, completed: {
                    if screen.purchase.finish(attempt) {
                        needToShow = false
                        lockModal?.close()
                    }
                }))
            } else {
                screen.purchase.finish(attempt)
                lockModal?.close()
                needToShow = false
            }
        }, completed: {
            if !checkedEligibility {
                screen.purchase.finish(attempt)
                needToShow = false
                lockModal.close()
            }
        }))
        
    }
    
    let tonWithdrawal:()->Void = {
//        let starsState = stateValue.with { $0.starsState }
//        let revenueStats = stateValue.with { $0.revenueStats }
//
//        if let revenueStats {
            
            let invoke:(Int64?)->Void = { amount in
                let error = stateValue.with { $0.withdrawError }
                if let error {
                    switch error {
                    case .authSessionTooFresh, .twoStepAuthTooFresh, .twoStepAuthMissing:
                        alert(for: context.window, info: strings().monetizationWithdrawErrorText)
                    case .requestPassword:
                        showModal(with: InputPasswordController(context: context, title: strings().monetizationWithdrawEnterPasswordTitle, desc: strings().monetizationWithdrawEnterPasswordText, checker: { value in
                            return context.engine.peers.requestStarsRevenueWithdrawalUrl(peerId: context.peerId, ton: true, amount: amount, password: value)
                            |> deliverOnMainQueue
                            |> afterNext { url in
                                LinkHooks.shared.openExternalLink(url, false)
                            }
                            |> ignoreValues
                            |> mapError { error in
                                switch error {
                                case .invalidPassword:
                                    return .wrong
                                case .limitExceeded:
                                    return .custom(strings().loginFloodWait)
                                case .amountTooSmall:
                                    return .custom(strings().starListScreenWithdrawMinimumGrams)
                                case .generic:
                                    return .generic
                                default:
                                    return .custom(strings().monetizationWithdrawErrorText)
                                }
                            }
                        }), for: context.window)
                    default:
                        alert(for: context.window, info: strings().unknownError)
                    }
                }
            }
            invoke(nil)

//            if revenueStats.balances.availableBalance.amount.value < 1_000_000_000 {
//                invoke(nil)
//            } else {
//                let starsState = StarsContext.State(flags: [], balance: revenueStats.balances.availableBalance.amount, subscriptions: [], canLoadMoreSubscriptions: false, transactions: [], canLoadMoreTransactions: false, isLoading: false)
//                showModal(with: withdrawStarBalance(context: context, stars: starsContext, state: starsState, ton: true, callback: { amount in
//                    invoke(amount)
//                }), for: window)
//            }
            
//        }

    }


    let arguments = Arguments(context: context, currency: currency, source: source, reveal: screen.action({
        updateState { current in
            var current = current
            current.revealed = !current.revealed
            return current
        }
    }), openLink: screen.action({ link in
        LinkHooks.shared.openExternalLink(link, false)
    }), buyMore: screen.action({
        switch currency {
        case .stars:
            showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: nil)), for: window)
        case .ton:
            LinkHooks.shared.openExternalLink(strings().fragmentTonAddFundsLink, false)
        }
    }), giftStars: screen.action({
        StarsHooks.shared.openMultigift(context, true)
    }), toggleFilterMode: screen.action({ mode in
        updateState { current in
            var current = current
            current.transactionMode = mode
            return current
        }
    }), buy: screen.action({ option in
        #if APP_STORE
        buyAppStore(option)
        #else
        buyNonStore(option)
        #endif
    }), loadMoreTransactions: screen.action({
        transactions.loadMore()
    }), loadMoreSubscriptions: screen.action({
        starsSubscriptionsContext.loadMore()
    }), openTransaction: screen.action({ transaction in
        screen.showChild({ Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: transaction.peer, transaction: transaction.native, currency: transaction.currency) }, show: { child in
            showModal(with: child, for: window, morphSource: {
                ((getController?() as? InputDataController)?.tableView.item(stableId: InputDataEntryId.custom(_id_transaction(transaction)))?.view as? GeneralContainableRowView)?.containerView
            })
        })
    }), openSubscription: screen.action({ subscription in
        screen.showChild({ Star_SubscriptionScreen(context: context, subscription: subscription) }, show: { child in
            showModal(with: child, for: window, morphSource: {
                ((getController?() as? InputDataController)?.tableView.item(stableId: InputDataEntryId.custom(_id_subscription(subscription)))?.view as? GeneralContainableRowView)?.containerView
            })
        })
    }), openRecommendedApps: screen.action({
        screen.showChild({ Star_AppExamples(context: context) }, show: { showModal(with: $0, for: window) })
    }), openAffiliate: screen.action({
        close?()
        StarsHooks.shared.openAffiliatePeer(context, context.peerId, false)
    }), stats: screen.action({ [weak starsRevenue] in
        switch currency {
        case .stars:
            StarsHooks.shared.openStarMonetization(context, context.peerId, starsRevenue)
            close?()
        case .ton:
            tonWithdrawal()
        }
    }))
    
    let signal = screen.preserving(statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = { screen.close() }
    
    
    controller.contextObject_second = (starsContext, starsRevenue)

    
    let modalController = InputDataModalController(controller, modalInteractions: nil, closeHandler: { close in
        screen.close()
        close()
    }, size: NSMakeSize(360, 300))
    
    
    close = { [weak modalController] in
        screen.close()
        modalController?.modal?.close()
    }
    
    controller.afterTransaction = { controller in
        let view = controller.contextObject as? FloatingHeaderView
        let myBalance = stateValue.with { $0.myBalance }
        if let myBalance {
            view?.update(myBalance: myBalance, context: context)
        }
    }
    
    
    controller.didLoad = { controller, _ in
        let myBalance = stateValue.with { $0.myBalance ?? .init(value: 0, nanos: 0) }
        let view = FloatingHeaderView(frame: NSMakeRect(0, 0, controller.frame.width, 50), currency: currency, source: source, myBalance: myBalance)
        controller.genericView.addSubview(view)
        controller.contextObject = view
        view.dismiss.set(handler: { _ in
            close?()
        }, for: .Click)
        
        view.update(myBalance: myBalance, context: context)
        
        controller.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak view] position in
            let height = view?.superview?.frame.height ?? 0
            view?.updateScrolled(position.rect.minY > height, animated: true)
        }))
        
    }
    
    return modalController
}



