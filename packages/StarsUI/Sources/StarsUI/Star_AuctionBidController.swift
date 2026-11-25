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


private final class TitleRowItem : GeneralRowItem {
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let balanceLayout: TextViewLayout
    
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let arguments: Arguments
    
   
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, context: (any AccountContextProtocol), arguments: Arguments) {
        
        self.context = context
        self.arguments = arguments
        
        let balanceAttr = NSMutableAttributedString()
        balanceAttr.append(string: strings().starPurchaseBalance("\(clown_space)\(state.myBalance)"), color: theme.colors.text, font: .normal(.text))
        balanceAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file, playPolicy: .onceEnd), for: clown)
        
        self.balanceLayout = .init(balanceAttr, alignment: .right)

        self.headerLayout = .init(.initialize(string: state.early ? strings().starAuctionBidPlaceEarlyBid : strings().starAuctionPlaceBid, color: theme.colors.text, font: .normal(.title)))
        self.infoLayout = .init(.initialize(string: strings().starAuctionBidSubTitleBiddersOther(Int(state.perks?.dropSize ?? 0)), color: theme.colors.grayText, font: .normal(.small)))
        

        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.balanceLayout.measure(width: .greatestFiniteMagnitude)
        
        self.headerLayout.measure(width: width - 40 - balanceLayout.layoutSize.width)
        self.infoLayout.measure(width: width - 40 - balanceLayout.layoutSize.width)
        
        return true
    }
    
    
    public override var height: CGFloat {
        return 50
    }
    
    override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        let balance = balanceLayout.attributedString.string.replacingOccurrences(of: clown, with: "")
        return [infoLayout.attributedString.string, balance].joined(separator: ", ")
    }
    
    public override func viewClass() -> AnyClass {
        return TitleRowView.self
    }
}

private class TitleRowView: GeneralRowView {
    private let top_Container = View()
    private let headerView = TextView()
    private let statusView = TextView()
    private let balanceView = InteractiveTextView()
    private let dismiss = ImageButton()
    
    
    private let separatorView = View()
    
    
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(top_Container)
        
        
        top_Container.addSubview(dismiss)
        
        dismiss.scaleOnClick = true
        dismiss.autohighlight = false
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        
        statusView.userInteractionEnabled = false
        statusView.isSelectable = false
        
        top_Container.addSubview(headerView)
        top_Container.addSubview(statusView)
        top_Container.addSubview(balanceView)
        
        //addSubview(separatorView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? TitleRowItem else {
            return
        }

        headerView.update(item.headerLayout)
        statusView.update(item.infoLayout)
        balanceView.set(text: item.balanceLayout, context: item.context)
        
        separatorView.backgroundColor = theme.colors.border
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.arguments.dismiss()
        }, for: .Click)
        
        needsLayout = true
        
    }
    
    public func updateBorder(visible: Bool) {
        separatorView.change(opacity: visible ? 1 : 0)
    }
    
    
    public override func layout() {
        super.layout()
        
        top_Container.frame = NSMakeRect(0, 0, frame.width, 50)
        
        headerView.centerX(y: 9)
        statusView.centerX(y: top_Container.frame.height - 9 - statusView.frame.height)
        
        balanceView.centerY(x: top_Container.frame.width - balanceView.frame.width - 10)
        
        dismiss.setFrameOrigin(NSMakePoint(10, 10))

        separatorView.frame = NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize)
    }
}



private final class HeaderItem : GeneralRowItem {
    
    public struct ActionInfo {
        public let title: TextViewLayout
        public let info: TextViewLayout
        
        public init(title: TextViewLayout, info: TextViewLayout) {
            self.title = title
            self.info = info
        }
    }
    
    fileprivate let state: State
    fileprivate let arguments: Arguments
    fileprivate let maxValue: Int64
        
    fileprivate let actions: [ActionInfo]
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments) {
        self.state = state
        self.arguments = arguments
        self.maxValue = Int64(state.maxSliderValue)
        
        let colors = arguments.presentation.colors
        
        
        if let perks = state.perks {
            
            let minimumAttr = NSMutableAttributedString()
            minimumAttr.append(string: clown_space + "\(perks.minBid)", color: colors.text, font: .avatar(.header))
            minimumAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            
            
            let leftAttr = NSMutableAttributedString()
            leftAttr.append(string: clown_space + "\(perks.dropSize * (perks.dropsTotal - (perks.currentRound - 1)))", color: colors.text, font: .avatar(.header))
            leftAttr.insertEmbedded(.embeddedAnimated(state.gift.file), for: clown)
            
            var actions: [ActionInfo] = []
            
            actions.append(.init(
                title: .init(minimumAttr),
                info: .init(.initialize(string: strings().starAuctionActiveListMinimum, color: colors.text, font: .normal(.small)))
            ))
            
            
            if let auctionStartDate = state.gift.auctionStartDate, auctionStartDate > state.currentDate {
                actions.append(.init(
                    title: .init(.initialize(string: "\(timerText(Int(auctionStartDate - state.currentDate)))", color: colors.text, font: .avatar(.header))),
                    info: .init(.initialize(string: "before start", color: colors.text, font: .normal(.small)))
                ))
            } else {
                actions.append(.init(
                    title: .init(.initialize(string: "\(timerText(Int(perks.nextDropTimeout)))", color: colors.text, font: .avatar(.header))),
                    info: .init(.initialize(string: strings().starAuctionActiveListUntilNextDrop, color: colors.text, font: .normal(.small)))
                ))
            }
            
            
            actions.append(.init(
                title: .init(leftAttr),
                info: .init(.initialize(string: strings().starAuctionActiveListLeft, color: colors.text, font: .normal(.small)))
            ))
            
                self.actions = actions

        } else {
            self.actions = []
        }
        

        for action in actions {
            action.title.measure(width: .greatestFiniteMagnitude)
            action.info.measure(width: .greatestFiniteMagnitude)
        }
        
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
                
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }
    
    override var accessibilityLabel: String? {
        if actions.isEmpty {
            return strings().starAuctionPlaceBid
        }
        return actions.map { action in
            let title = action.title.attributedString.string.replacingOccurrences(of: clown, with: "").trimmingCharacters(in: .whitespaces)
            return title + " " + action.info.attributedString.string
        }.joined(separator: ", ")
    }
    
    public override var height: CGFloat {
        return 110 + 15 + 40
    }
}

private final class HeaderView: GeneralRowView {
    public let badgeView = Star_BadgeView(frame: NSMakeRect(0, 0, 100, 48))
    public let sliderView = Star_SliderView(frame: NSMakeRect(0, 0, 100, 30))
    
    public let actionsView: ActionInfoView
    
    public class ActionInfoView : View {
        
        public class ActionView : View {
            
            public let titleView = InteractiveTextView()
            public let infoView = InteractiveTextView()
            
            public required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(titleView)
                addSubview(infoView)
                
                
                
            }
            
            public required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            public func update(_ item: HeaderItem.ActionInfo, context: (any AccountContextProtocol)) {
                titleView.set(text: item.title, context: context)
                infoView.set(text: item.info, context: context)
            }
            
            
            public override func layout() {
                super.layout()
                titleView.centerX(y: 8)
                infoView.centerX(y: frame.height - infoView.frame.height - 8)
            }
            
        }
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func update(items: [HeaderItem.ActionInfo], item tableItem: HeaderItem) {
            while subviews.count > items.count {
                subviews.last?.removeFromSuperview()
            }
            while subviews.count < items.count {
                addSubview(ActionView(frame: NSMakeRect(0, 0, 100, frame.height)))
            }
            
            let itemWidth: CGFloat = (frame.width - CGFloat(items.count + 1) * 10) / CGFloat(items.count)
            
            var x: CGFloat = 10
            
            for (i, item) in items.enumerated() {
                let view = self.subviews[i] as! ActionView
                view.update(item, context: tableItem.arguments.context)
                view.backgroundColor = tableItem.arguments.presentation.colors.listBackground
                view.layer?.cornerRadius = 10
                view.frame = CGRect(origin: CGPoint(x: x, y: 0), size: NSMakeSize(itemWidth, 50))
                x += view.frame.width + 10
            }
            
            needsLayout = true
        }
        
        public override func layout() {
            super.layout()
        }
    }
    

    
    public required init(frame frameRect: NSRect) {
        actionsView = ActionInfoView(frame: NSMakeRect(0, 0, frameRect.width - 20, 50))
        super.init(frame: frameRect)
        
        addSubview(badgeView)
        addSubview(sliderView)
        
        addSubview(actionsView)
        
        
        sliderView.updateProgress = { [weak self] progress, maybeToBalance in
            if let item = self?.item as? HeaderItem {
                
                var value = progress * CGFloat(item.maxValue)
                let myBalance = CGFloat(item.state.myBalance)
                if maybeToBalance, item.state.amount.realValue < item.state.myBalance, value > myBalance {
                    value = Double(item.state.amount.withRealValue(Int(myBalance + 1)).sliderValue)
                }
                item.arguments.updateValue(Int64(ceil(value)))
            }
        }

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        let color = getStarAmountColorMapping(value: Int64(item.state.amount.realValue))
        
        sliderView.updateColors([color, color], effect: .white)
        badgeView.updateColors([color, color], effect: .white)

        actionsView.update(items: item.actions, item: item)
        
        let transition: ContainedViewLayoutTransition = .immediate
        
        let size = badgeView.update(sliderValue: Int64(item.state.amount.sliderValue), realValue: Int64(item.state.amount.realValue), max: item.maxValue, context: item.arguments.context, maxString: strings().starAuctionBidCustom)
        
        sliderView.dotLayer.backgroundColor = item.arguments.presentation.colors.background
        sliderView.emptyLayer.backgroundColor = item.arguments.presentation.colors.listBackground.cgColor

        
        transition.updateFrame(view: self.badgeView, frame: self.focus(size))
        badgeView.updateLayout(size: size, transition: transition)

        sliderView.update(count: Int64(item.state.amount.sliderValue), minValue: 1, maxValue: item.maxValue, addCustom: item.arguments.setCustom)
        
        
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? HeaderItem else {
            return theme.colors.background
        }
        return item.arguments.presentation.colors.background
    }
    
    public override func layout() {
        super.layout()
        sliderView.frame = NSMakeRect(20, badgeView.frame.height + 20, frame.width - 40, 30)
        sliderView.layout()
        
        badgeView.centerX(y: 50)
        
        badgeView.setFrameOrigin(NSMakePoint(20 + sliderView.dotLayer.frame.midX - badgeView.frame.width * badgeView.tailPosition, 10))
        
        actionsView.centerX(y: sliderView.frame.maxY + 15)
                
    }
}

private final class AuctionPeerRowItem : GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peer: State.TopPeer
    fileprivate let nameLayout: TextViewLayout
    fileprivate let amountLayout: TextViewLayout
    fileprivate let placeImage: CGImage
    fileprivate let _hasBorder: Bool
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), peer: State.TopPeer, hasBorder: Bool = true, winning: Bool = false) {
        self.context = context
        self.peer = peer
        self._hasBorder = hasBorder
        self.nameLayout = .init(.initialize(string: peer.peer._asPeer().displayTitle, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        
        let amountAttr = NSMutableAttributedString()
        amountAttr.append(string: clown_space + peer.amount.formattedWithSeparator, color: theme.colors.grayText, font: .normal(.small))
        amountAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)

        self.amountLayout = .init(amountAttr)
        self.amountLayout.measure(width: .greatestFiniteMagnitude)
        
        
        let textNode = TextNode.layoutText(.initialize(string: "\(peer.place)", color: winning ? theme.colors.greenUI : hasBorder ? .white : peer.outbid ? theme.colors.redUI : theme.colors.darkGrayText, font: .avatar(13)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
        
        
        var color: [NSColor]
        if !hasBorder {
            color = [.clear, .clear]
        } else if peer.place == 1 {
            color = [NSColor(0xFFAC04), NSColor(0xFFCA35)]
        } else if peer.place == 2 {
            color = [NSColor(0xABABAB), NSColor(0xAFAFAF)]
        } else if peer.place == 3 {
            color = [NSColor(0xD17C3F), NSColor(0xD88E4F)]
        } else {
            color = [.clear, .clear]
        }
        
        placeImage = generateImage(NSMakeSize(max(textNode.0.size.width + 7, 24), 24), rotatedContext: { size, ctx in
            ctx.clear(size.bounds)
            ctx.round(size, size.height / 2)
            
            let gradient = CGGradient.evenlySpaced(color.map { $0.cgColor }, colorSpace: DeviceGraphicsContextSettings.shared.colorSpace)!
            
            ctx.drawLinearGradient(gradient, start: CGPoint(), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())

            
            textNode.1.draw(size.bounds.focus(textNode.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
            
        })!
        
        super.init(initialSize, height: 46, stableId: stableId)
    }
    
    public override var hasBorder: Bool {
        return _hasBorder
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        nameLayout.measure(width: width - amountLayout.layoutSize.width - 130)
        return true
    }
    
    override var accessibilityLabel: String? {
        return nameLayout.attributedString.string
    }
    
    override var accessibilityValue: String? {
        return "#\(peer.place), \(peer.amount.formattedWithSeparator) \(strings().voiceOverCommonStars)"
    }
    
    override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return AuctionPeerRowView.self
    }
}

private final class AuctionPeerRowView: GeneralRowView {
    private let avatarView = AvatarControl(font: .avatar(13))
    private let nameView = TextView()
    private let amountView = InteractiveTextView()
    private let placeView = ImageView()
    private let borderView = View()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        avatarView.setFrameSize(NSMakeSize(36, 36))
        addSubview(avatarView)
        addSubview(nameView)
        addSubview(amountView)
        addSubview(placeView)
        addSubview(borderView)
        placeView.isAccessibilityDecorative = true
        
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? AuctionPeerRowItem else {
            return
        }
        
        borderView.backgroundColor = theme.colors.border
        borderView.isHidden = !item.hasBorder
        self.placeView.image = item.placeImage
        self.placeView.sizeToFit()
        
        avatarView.setPeer(account: item.context.account, peer: item.peer.peer._asPeer())
        nameView.update(item.nameLayout)
        amountView.set(text: item.amountLayout, context: item.context)
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        
        self.placeView.centerY(x: 20)
        avatarView.centerY(x: self.placeView.frame.maxX + 15)
        nameView.centerY(x: avatarView.frame.maxX + 15)
        amountView.centerY(x: frame.width - amountView.frame.width - 20)
        borderView.frame = NSMakeRect(nameView.frame.minX, frame.height - .borderSize, frame.width - nameView.frame.minX - 20, .borderSize)
    }
}


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let presentation: TelegramPresentationTheme
    public let updateValue:(Int64)->Void
    public let setCustom:()->Void
    public let openAcquiredItems:()->Void
    public let dismiss: ()->Void
    public init(context: (any AccountContextProtocol), presentation: TelegramPresentationTheme, updateValue:@escaping(Int64)->Void, setCustom:@escaping()->Void, openAcquiredItems:@escaping()->Void, dismiss: @escaping()->Void) {
        self.context = context
        self.presentation = presentation
        self.updateValue = updateValue
        self.setCustom = setCustom
        self.openAcquiredItems = openAcquiredItems
        self.dismiss = dismiss
    }
}

private struct State : Equatable {
    public struct TopPeer: Equatable {
        public var peer: EnginePeer
        public var amount: Int64
        public var place: Int32
        public var outbid: Bool
        public var stableId: Int64 {
            return peer.id.toInt64()
        }
        public init(peer: EnginePeer, amount: Int64, place: Int32, outbid: Bool) {
            self.peer = peer
            self.amount = amount
            self.place = place
            self.outbid = outbid
        }
    }
    
    public var early: Bool {
        if let startDate = auctionState?.startDate {
            return startDate > currentDate
        } else {
            return false
        }
    }
    
    public var gift: StarGift.Gift
    
    public var amount: Star_SliderAmount = Star_SliderAmount(realValue: 1, maxRealValue: 10000, maxSliderValue: 10000, isLogarithmic: false, minValue: 2)
    
    public var myBalance: Int64 = 1000
    public var auctionState: GiftAuctionContext.State?
    public var topPeers: [TopPeer]
    public var myPlace: TopPeer?
    public var myFakePlace: TopPeer?
    
    public var maxSliderValue: Int {
        if let topPeer = topPeers.first {
            //max(50000, 1.5 * <top1 bid>)
            return max(50_000, Int(Double(topPeer.amount) * 1.5))
        } else {
            return 10000
        }
    }

    
    public var currentDate: Int32
    
    public var perks: (nextDropTimeout: Int32, minBid: Int64, currentRound: Int32, dropSize: Int32, dropsTotal: Int32, startDate: Int32, endDate: Int32, bidLevels: [GiftAuctionContext.State.BidLevel], lastGiftNumber: Int32)? {
        if let auctionState, let dropSize = gift.auctionGiftsPerRound {
            switch auctionState.auctionState {
            case let .ongoing(_, startDate, endDate, minBidAmount, bidLevels, _, nextDropDate, _, currentRound, dropsTotal, _, lastGiftNumber):
                let dropTimeout = max(0, nextDropDate - currentDate)
                return (nextDropTimeout: dropTimeout, minBid: minBidAmount, currentRound: currentRound, dropSize: dropSize, dropsTotal: dropsTotal, startDate: startDate, endDate: endDate, bidLevels: bidLevels, lastGiftNumber: lastGiftNumber)
            default:
                return nil
            }
        }
        return nil
    }
    
}

private let _id_header = InputDataIdentifier("_id_header")
private func _id_item(_ value: State.TopPeer, my: Bool = false) -> InputDataIdentifier {
    return .init("_id_item_\(value.stableId)_\(my)")
}
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h1"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: arguments.presentation.colors.background)
    }))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, state: state, arguments: arguments)
    }))
    
    if let acquired = state.auctionState?.myState.acquiredCount, acquired > 0 {
        let text = "[\(clown_space)\(strings().starAuctionItemsBoughtOther(Int(acquired))) >](acq)"

        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes.init(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.accent), bold: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accent), link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accent), linkAttribute: { link in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { value in
                arguments.openAcquiredItems()
            }))
        })).mutableCopy() as! NSMutableAttributedString
        parsed.insertEmbedded(.embeddedAnimated(state.gift.file), for: clown)
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .attributed(parsed), data: .init(color: theme.colors.accent, detectBold: false, viewType: .singleItem, centerViewAlignment: true, alignment: .center, linkColor: theme.colors.accent, context: arguments.context, linkExecutor: TextViewInteractions(processURL: { value in
            arguments.openAcquiredItems()
        }))))
        index += 1
    } else {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
    
    if let peer = state.myFakePlace ?? state.myPlace {
        let text: String
        let color: NSColor
        var winning = false

        var rightItem = InputDataGeneralTextRightData.init(isLoading: false, text: nil)
        if let myFakePlace = state.myFakePlace {
            text = strings().starAuctionBidYourBidWillBe
            color = myFakePlace.outbid ? theme.colors.redUI : theme.colors.listGrayText
        } else if peer.outbid {
            text = strings().starAuctionBidYouHaveBeenOutbid
            color = theme.colors.redUI
        } else {
            text = strings().starAuctionBidYouAreWinning
            color = theme.colors.greenUI.darker()
            winning = true
            let giftTitle = state.gift.title ?? ""
            let lastGift = state.perks?.lastGiftNumber ?? 0
            let number = lastGift + peer.place
            rightItem = .init(isLoading: false, text: .initialize(string: giftTitle + " #\(number.formattedWithSeparator)", color: color, font: .normal(.small)), alignToText: true, wrap: color.withAlphaComponent(0.2))
        }

        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: .init(color: color, viewType: .textTopItem, rightItem: rightItem, inset: .init(left: -7, right: 20, top:4, bottom:2))))
        index += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_item(peer, my: true), equatable: .init(state.myFakePlace ?? peer), comparable: nil, item: { initialSize, stableId in
            return AuctionPeerRowItem(initialSize, stableId: stableId, context: arguments.context, peer: state.myFakePlace ?? peer, hasBorder: false, winning: winning)
        }))
        
        
        entries.append(.sectionId(sectionId, type: .customModern(state.topPeers.isEmpty ? 20 : 10)))
        sectionId += 1

    }
    
    var topPeers = state.topPeers
    if let myFakePlace = state.myFakePlace {
        if let pos = topPeers.firstIndex(where: { $0.peer.id == myFakePlace.peer.id }), myFakePlace.place <= topPeers.count {
            topPeers.move(at: pos, to: Int(myFakePlace.place) - 1)
            topPeers[Int(myFakePlace.place) - 1] = myFakePlace
        } else {
            if myFakePlace.place == 3 {
                topPeers[Int(myFakePlace.place) - 1] = myFakePlace
            } else if myFakePlace.place < 3 {
                topPeers.insert(myFakePlace, at: Int(myFakePlace.place) - 1)
            }
        }
       
    }
    
    if !topPeers.isEmpty {
        entries.append(
            .desc(
                sectionId: sectionId,
                index: index,
                text: .plain(strings().starAuctionBidTop3Winners),
                data: .init(
                    color: theme.colors.listGrayText,
                    viewType: .textTopItem,
                    inset: .init(left: -7, right: 20, top: 4, bottom: 2)
                )
            )
        )
        index += 1

        for peer in topPeers.prefix(3) {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_item(peer), equatable: .init(peer), comparable: nil, item: { initialSize, stableId in
                return AuctionPeerRowItem(initialSize, stableId: stableId, context: arguments.context, peer: peer)
            }))
        }
        
        if let bidLevels = state.perks?.bidLevels, let level = bidLevels.first(where: { $0.position == state.gift.auctionGiftsPerRound }), let myPlace = state.myPlace, myPlace.outbid {
            let amount = strings()
                .starListItemCountOther(Int(level.amount))
                .replacingOccurrences(of: "\(level.amount)", with: level.amount.formattedWithSeparator)
            
            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown( strings().starAuctionAcquiredBidAtLeast(amount), linkHandler: { _ in
                
            }), data: .init(color: theme.colors.grayText, detectBold: false, viewType: .singleItem, centerViewAlignment: true, alignment: .center, linkColor: theme.colors.accent, context: arguments.context, linkExecutor: TextViewInteractions(processURL: { value in
                arguments.openAcquiredItems()
            }))))
            index += 1
            
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1

        } else {
            entries.append(.sectionId(sectionId, type: .customModern(20)))
            sectionId += 1
        }
        

    }
    

    
    return entries
}

public func Star_AuctionBidController(context: (any AccountContextProtocol), peerId: EnginePeer.Id, gift: StarGift.Gift, auctionContext: GiftAuctionContext, hideName: Bool = true, text: String = "", entities: [MessageTextEntity] = []) -> InputDataModalController {
    
    context.starsContext.load(force: true)
    
    
    let actionsDisposable = DisposableSet()

    let initialState = State(gift: gift, topPeers: [], currentDate: context.timestamp)
    
    
    
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
    
    let starsContext = context.starsContext

    starsContext.load(force: true)
    
    
    let timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: true, completion: {
        updateState { current in
            var current = current
            current.currentDate = context.timestamp
            return current
        }
    }, queue: .mainQueue())
    
    timer.start()
    
    actionsDisposable.add(combineLatest(starsContext.state, auctionContext.state).startStrict(next: { starsState, auctionState in
        
        let previousState = stateValue.with { $0 }
        
        updateState { current in
            var current = current
            current.myBalance = starsState?.balance.value ?? 0
            let myPreviousState = current.auctionState?.myState
            current.auctionState = auctionState
            
            let minBidAmount = auctionState?.myState.bidAmount ?? auctionState?.myState.minBidAmount
            
            if myPreviousState?.bidDate != auctionState?.myState.bidDate, let minBidAmount {
                current.amount = .init(realValue: max(current.amount.realValue, Int(minBidAmount)), maxRealValue: current.maxSliderValue, maxSliderValue: current.maxSliderValue, isLogarithmic: false, minValue: Int(minBidAmount + 1))
            }
            
            return current
        }
        
        let roundDidUpdate = stateValue.with { $0.perks?.currentRound != previousState.perks?.currentRound }
        
        if roundDidUpdate {
            context.starsContext.load(force: true)
        }
        
        if let auctionState {
            
            switch auctionState.auctionState {
            case let .ongoing(_, _, _, minBidAmount, bidLevels, topBidders, _, _, _, _, _, _):
               
                
                updateState { current in
                    var current = current
                    var top: [State.TopPeer] = []
                    
                    var i: Int32 = 1
                    for bidder in topBidders {
                        var bid: Int64 = 0
                        for level in bidLevels {
                            if level.position == i {
                                bid = level.amount
                                break
                            }
                        }
                        if bidder.id == context.peerId, let myBid = auctionState.myState.bidAmount {
                            bid = max(myBid, bid)
                        }
                        top.append(State.TopPeer(peer: bidder, amount: bid, place: i, outbid: false))
                        i += 1
                    }
                    
                    
                    let place = auctionState.getPlace(myBid: auctionState.myState.bidAmount, myBidDate: auctionState.myState.bidDate)
                    if let myBid = auctionState.myState.bidAmount, let _ = auctionState.myState.bidDate, let place {
                        current.myPlace = .init(peer: .init(context.myPeer!), amount: myBid, place: place.place, outbid: place.place > gift.auctionGiftsPerRound ?? 0)
                    } else {
                        current.myPlace = nil
                    }
                    
                    
                    if let myPlace = current.myPlace, top.count < 3, !top.contains(where: { $0.peer.id == context.peerId }) {
                        top.append(myPlace)
                    }
                    
                    current.topPeers = top
                    
                    let minBidAmount = auctionState.myState.bidAmount ?? minBidAmount
                    
                    current.amount = .init(realValue: roundDidUpdate ? Int(minBidAmount) : max(current.amount.realValue, Int(minBidAmount)), maxRealValue: current.maxSliderValue, maxSliderValue: current.maxSliderValue, isLogarithmic: false, minValue: Int(minBidAmount + 1))


                    return current
                }
                
            case .finished:
                close?()
                break
            }
        }
        
    }))
    
    
    let placeBid:(Int64)->Signal<SendBotPaymentResult, SendBotPaymentFormError> = { value in
        let state = stateValue.with { $0 }
        
  
        if let myMinBidAmount = state.auctionState?.myState.minBidAmount, value < myMinBidAmount {
            return .fail(.serverProvided(strings().starAuctionBidAddStars(strings().starListItemCountOther(Int(myMinBidAmount - value)))))
        }
        
        let myBid = state.auctionState?.myState.bidAmount ?? 0
        
        if myBid + state.myBalance < value {
            showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: value)), for: window)
            return .never()
        }
        
        let source: BotPaymentInvoiceSource
        source = .starGiftAuctionBid(
            update: state.auctionState?.myState.bidAmount != nil,
            hideName: hideName,
            peerId: peerId,
            giftId: gift.id,
            bidAmount: value,
            text: text,
            entities: entities
        )
        
        let formAndMaybeValidatedInfo = context.engine.payments.fetchBotPaymentForm(source: source, themeParams: nil)

        let bidSignal = formAndMaybeValidatedInfo |> `catch` { error -> Signal<BotPaymentForm, SendBotPaymentFormError> in
            switch error {
            case .disallowedStarGift:
                return .fail(.disallowedStarGift)
            case .starGiftUserLimit:
                return .fail(.starGiftUserLimit)
            default:
                return .fail(.generic)
            }
        } |> mapToSignal { inputData -> Signal<SendBotPaymentResult, SendBotPaymentFormError> in
            return context.engine.payments.sendStarsPaymentForm(formId: inputData.id, source: source)
        }
        
        return bidSignal |> deliverOnMainQueue |> afterCompleted {
            context.starsContext.load(force: true)
        }
                      
    }

    let arguments = Arguments(context: context, presentation: theme, updateValue: { value in
        updateState { current in
            var current = current
            current.amount = current.amount.withSliderValue(Int(value))
            
            if current.perks?.bidLevels != nil {
                let place = current.auctionState?.getPlace(myBid: value, myBidDate: current.currentDate)
                
                if Int64(current.amount.realValue) == current.myPlace?.amount {
                    current.myFakePlace = nil
                } else if let place {
                    current.myFakePlace = .init(peer: .init(context.myPeer!), amount: Int64(current.amount.realValue), place: place.place, outbid: place.place > gift.auctionGiftsPerRound ?? 0)
                } else {
                    current.myFakePlace = nil
                }
            } else {
                
            }
            return current
        }
        let current = stateValue.with { $0.amount.realValue }
        let myBalance = stateValue.with { $0.myBalance }
        if current == myBalance {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    }, setCustom: {
        
        let state = stateValue.with { $0 }
        
        guard let minBid = state.perks?.minBid, let dropSize = state.perks?.dropSize else {
            return
        }
        let value: Int64
        var maxBid = state.myBalance
        
        if let myBid = state.auctionState?.myState.bidAmount {
            maxBid += myBid
        }
        
        if let minBidAmount = state.auctionState?.myState.minBidAmount {
            value = minBidAmount
        } else {
            value = minBid
        }
        
        
        showModal(
            with: InputCustomController(
                context: context,
                currentValue: value,
                title: strings().starAuctionBidPlaceCustomBid,
                desc: strings().starAuctionBidCustomDescription(Int(dropSize)),
                maxBid: maxBid,
                checker: { value in
                    
                    if let value = Int64(value) {
                        return placeBid(value)
                        |> mapError { error in
                            let text: String
                            switch error {
                            case .alreadyPaid:
                                text = strings().checkoutErrorInvoiceAlreadyPaid
                            case .generic:
                                text = strings().unknownError
                            case .paymentFailed:
                                text = strings().checkoutErrorPaymentFailed
                            case .precheckoutFailed:
                                text = strings().checkoutErrorPrecheckoutFailed
                            case .starGiftOutOfStock:
                                text = strings().giftSoldOutError
                            case .disallowedStarGift:
                                text = strings().giftSendDisallowError
                            case .starGiftUserLimit:
                                text = strings().giftOptionsGiftBuyLimitReached
                            case let .serverProvided(value):
                                text = value
                            }
                            return .text(text)
                        }
                        |> afterNext { _ in
                            showModalText(
                                for: window,
                                text: strings().starAuctionBidCustomDescription(Int(dropSize)),
                                title: strings().starAuctionBidPlacedTitle
                            )
                            updateState { current in
                                var current = current
                                current.myFakePlace = nil
                                return current
                            }
                        }
                        |> ignoreValues
                    } else {
                        return .fail(.generic)
                    }
                }
            ),
            for: window
        )

    }, openAcquiredItems: {
        let signal = context.engine.payments.getGiftAuctionAcquiredGifts(giftId: gift.id) |> deliverOnMainQueue
        
        _ = showModalProgress(signal: signal, for: window).startStandalone(next: { gifts in
            showModal(with: Star_AuctionAcquiredController(context: context, gift: gift, gifts: gifts), for: window)
        })
    }, dismiss: {
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(
        dataSignal: signal,
        title: ""
    )
    controller.analyticsScreen = .giftsAuctionBid

   
    
    controller.validateData = { _ in
        
        let state = stateValue.with { $0 }
        
        let value = Int64(state.amount.realValue)
        
        guard let dropSize = state.perks?.dropSize else {
            return .none
        }
        

        _ = placeBid(value).startStandalone(next: { result in
            showModalText(
                for: window,
                text: strings().starAuctionBidBelowTop(Int(dropSize)),
                title: strings().starAuctionBidPlacedTitle
            )
            updateState { current in
                var current = current
                current.myFakePlace = nil
                return current
            }
        }, error: { error in
            let text: String
            switch error {
            case .alreadyPaid:
                text = strings().checkoutErrorInvoiceAlreadyPaid
            case .generic:
                text = strings().unknownError
            case .paymentFailed:
                text = strings().checkoutErrorPaymentFailed
            case .precheckoutFailed:
                text = strings().checkoutErrorPrecheckoutFailed
            case .starGiftOutOfStock:
                text = strings().giftSoldOutError
            case .disallowedStarGift:
                text = strings().giftSendDisallowError
            case .starGiftUserLimit:
                text = strings().giftOptionsGiftBuyLimitReached
            case let .serverProvided(value):
                text = value
            }
            showModalText(for: window, text: text)
        })
        
        return .none
    }
    
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.contextObject = (auctionContext, timer)
    
    controller.getBackgroundColor = {
        presentation.colors.background
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().starAuctionPlaceBid, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true, customTheme: {
        .init(text: presentation.colors.text, background: presentation.colors.background, grayForeground: presentation.colors.background, activeBackground: presentation.colors.background, listBackground: presentation.colors.background)
    })
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 300))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    
    
    let link: String = context.meUrlPrefix + "auction/\(auctionContext.gift.generic?.auctionSlug ?? "")"
    
    controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActions, handler: {
    }, contextMenu: {
        var items: [ContextMenuItem] = []
        items.append(ContextMenuItem(strings().starAuctionContextMenuAbout, handler: {
            showModal(with: Star_AuctionInfoController(context: context, gift: gift), for: window)
        }, itemImage: MenuAnimation.menu_show_info.value))
        
        items.append(ContextMenuItem(strings().modalShare, handler: {
            StarsHooks.shared.shareLink(context, link, window)
        }, itemImage: MenuAnimation.menu_share.value))
        
        items.append(ContextMenuItem(strings().modalCopyLink, handler: {
            copyToClipboard(link)
            showModalText(for: window, text: strings().shareLinkCopied)

        }, itemImage: MenuAnimation.menu_copy_link.value))
        
        return items
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    let view = TitleRowView(frame: NSMakeRect(0, 0, 368, 50))

    controller.contextObject_second = view
    
    controller.afterTransaction = { [weak modalInteractions, weak modalController] controller in
        let view = controller.contextObject_second as? TitleRowView
        let item = TitleRowItem(controller.frame.size, stableId: InputDataEntryId.custom(_id_header), state: stateValue.with { $0 }, context: context, arguments: arguments)
        view?.set(item: item, animated: false)
        
        let realValue: Int = stateValue.with { $0.amount.realValue }
        modalInteractions?.updateDone { button in
            button.set(
                text: strings().starAuctionPlace(
                    strings()
                        .starListItemCountOther(realValue)
                        .replacingOccurrences(of: "\(realValue)", with: realValue.formattedWithSeparator)
                ),
                for: .Normal
            )
        }
        modalController?.updateLocalizationAndTheme(theme: theme)
    }
    
    
    controller.didLoad = { [view] controller, _ in
        controller.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak view, weak controller] scroll in
            guard let view, let controller else {
                return
            }
            let visible = scroll.rect.minY >= (controller.tableView.frame.height)
            view.updateBorder(visible: visible)
        }))
    }
    
    controller.afterViewDidLoad = {
        guard let controller = getController?() else {
            return
        }
        let view = controller.contextObject_second as? TitleRowView
        controller.genericView.set(view)
    }
    
    return modalController
    
}

private struct InputCustomState : Equatable {
    public let error: InputDataValueError?
    public let value: InputDataValue
    public let isLoading: Bool
    public let maxBid: Int64
    public init(value: InputDataValue, error: InputDataValueError?, isLoading: Bool, maxBid: Int64) {
        self.value = value
        self.error = error
        self.isLoading = isLoading
        self.maxBid = maxBid
    }
    
    public func withUpdatedError(_ error: InputDataValueError?) -> InputCustomState {
        return InputCustomState(value: self.value, error: error, isLoading: self.isLoading, maxBid: self.maxBid)
    }
    public func withUpdatedValue(_ value: InputDataValue) -> InputCustomState {
        return InputCustomState(value: value, error: self.error, isLoading: self.isLoading, maxBid: self.maxBid)
    }
    public func withUpdatedLoading(_ isLoading: Bool) -> InputCustomState {
        return InputCustomState(value: self.value, error: self.error, isLoading: isLoading, maxBid: self.maxBid)
    }
}

private let _id_input:InputDataIdentifier = InputDataIdentifier("_id_input_pwd")
private enum BidError {
    case generic
    case text(String)
}
private func inputEntries(state: InputCustomState, desc:String, setMax:@escaping()->Void) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    var sectionId:Int32 = 0
    var index:Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    entries.append(
        .input(
            sectionId: sectionId,
            index: index,
            value: state.value,
            error: state.error,
            identifier: _id_input,
            mode: .plain,
            data: InputDataRowData(viewType: .singleItem, rightItem: state.maxBid > 0 ?  .action(generateTextIcon(.initialize(string: strings().starAuctionBidMax, color: theme.colors.accent, font: .normal(.text))), .custom({ _, _ in
                setMax()
            })) : nil),
            placeholder: .init(
                nil,
                icon: TelegramThemeHooks.shared.image(.iconStarCurrency).precomposed(),
                drawBorderAfterPlaceholder: false,
                hasLimitationText: false
            ),
            inputPlaceholder: strings().starAuctionBidEnterBid,
            filter: { String($0.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }) },
            limit: 10
        )
    )
    index += 1

    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(desc), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

private func InputCustomController(context: (any AccountContextProtocol), currentValue: Int64, title: String, desc: String, maxBid: Int64, checker:@escaping(String)->Signal<Never, BidError>) -> InputDataModalController {

    let initialState: InputCustomState = InputCustomState(value: .string(currentValue > 0 ? "\(currentValue)" : nil), error: nil, isLoading: false, maxBid: maxBid)
    let stateValue: Atomic<InputCustomState> = Atomic(value: initialState)
    let statePromise:ValuePromise<InputCustomState> = ValuePromise(initialState, ignoreRepeated: true)
    
    
    let updateState:(_ f:(InputCustomState)->InputCustomState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let dataSignal = statePromise.get() |> map { state in
        return inputEntries(state: state, desc: desc, setMax: {
            updateState {
                return $0.withUpdatedValue(.string("\(maxBid)")).withUpdatedError(nil)
            }
        })
    } |> map { entries in
        return InputDataSignalValue(entries: entries)
    }
    
    let bidDisposable = MetaDisposable()
    
    var dismiss:(()->Void)?
    
    let controller = InputDataController(dataSignal: dataSignal, title: title, validateData: { data in
        return .fail(.doSomething { f in
            if let bid = data[_id_input]?.stringValue, !stateValue.with({$0.isLoading}) {
                updateState {
                    return $0.withUpdatedLoading(true)
                }
                bidDisposable.set(showModalProgress(signal: checker(bid), for: context.window).start(error: { error in
                    let text: String
                    switch error {
                    case .generic:
                        text = strings().unknownError
                    case let .text(t):
                        text = t
                    }
                    updateState {
                        return $0.withUpdatedLoading(false).withUpdatedError(InputDataValueError(description: text, target: .data))
                    }
                    f(.fail(.fields([_id_input : .shake])))
                }, completed: {
                    updateState {
                        return $0.withUpdatedLoading(false)
                    }
                    dismiss?()
                }))
            }
        })
    }, updateDatas: { data in
        updateState {
            return $0.withUpdatedValue(data[_id_input]!).withUpdatedError(nil)
        }
        return .fail(.none)
    }, afterDisappear: {
        bidDisposable.dispose()
    }, hasDone: true)
    controller.analyticsScreen = .giftsAuctionCustomBid
    
    controller.autoInputAction = true
    
    let interactions = ModalInteractions(
        acceptTitle: strings().starAuctionPlaceBid,
        accept: { [weak controller] in
            controller?.validateInputValues()
        },
        singleButton: true
    )


    
    let modalController = InputDataModalController(controller, modalInteractions: interactions, size: NSMakeSize(300, 300))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    dismiss = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
}
