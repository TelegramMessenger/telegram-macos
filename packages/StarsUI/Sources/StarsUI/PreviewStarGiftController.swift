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

private final class LimitedRowItem : GeneralRowItem {
    fileprivate let availability: StarGift.Gift.Availability
    public init(_ initialSize: NSSize, stableId: AnyHashable, availability: StarGift.Gift.Availability) {
        self.availability = availability
        super.init(initialSize, height: 30 + 48, stableId: stableId)
    }

    public override var accessibilityLabel: String? {
        return strings().giftingStarGiftLimited
    }

    public override var accessibilityValue: String? {
        return strings().starTransactionAvailabilityOf(Int(availability.remains), Int(availability.total).prettyNumber)
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return LimitedRowView.self
    }
}

private final class LimitedRowView : GeneralRowView {
    
    
    private final class BadgeView : View {
        private let shapeLayer = SimpleShapeLayer()
        private let foregroundLayer = SimpleGradientLayer()
        private let textView = InteractiveTextView()
        private let container = View()
        
        public private(set) var tailPosition: CGFloat = 0.0
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            textView.userInteractionEnabled = false
            
            foregroundLayer.colors = [theme.colors.accent, theme.colors.accent].map { $0.cgColor }
            foregroundLayer.startPoint = NSMakePoint(0, 0.5)
            foregroundLayer.endPoint = NSMakePoint(1, 0.2)
            foregroundLayer.mask = shapeLayer
            
            
            self.layer?.masksToBounds = false
            self.foregroundLayer.masksToBounds = false
            
            
            self.layer?.addSublayer(foregroundLayer)


            self.layer?.masksToBounds = false
            
            shapeLayer.fillColor = NSColor.red.cgColor
            shapeLayer.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
            

            
            container.addSubview(textView)
            addSubview(container)
            container.layer?.masksToBounds = false
        }
        
        public func update(sliderValue: Int64, realValue: Int64, max maxValue: Int64) -> NSSize {
            
            
            let attr = NSMutableAttributedString()
            attr.append(string: "\(realValue.formattedWithSeparator)", color: theme.colors.underSelectedColor, font: .medium(16))
            let textLayout = TextViewLayout(attr)
            textLayout.measure(width: .greatestFiniteMagnitude)
            self.textView.set(text: textLayout, context: nil)

            
            container.setFrameSize(NSMakeSize(container.subviewsWidthSize.width + 2, container.subviewsWidthSize.height))
            
            self.tailPosition = max(0, min(1, CGFloat(sliderValue) / CGFloat(maxValue)))
                    
            let size = NSMakeSize(container.frame.width + 30, frame.height)
            
            
            foregroundLayer.frame = size.bounds.insetBy(dx: 0, dy: -10)
            shapeLayer.frame = foregroundLayer.frame.focus(size)
            
            shapeLayer.path = generateRoundedRectWithTailPath(rectSize: size, tailPosition: tailPosition)
            
            return size
            
        }
        
        public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: container, frame: container.centerFrameX(y: 1))

            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: -3))
            
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
         //   shapeLayer.frame = bounds
        }
    }

    private class LineView : View {
        private var availability: StarGift.Gift.Availability?
        private let limitedView = TextView()
        private let totalView = TextView()
        
        private let limitColorMask = SimpleLayer()
        private let totalColorMask = SimpleLayer()
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.layer?.cornerRadius = 10
            addSubview(limitedView)
            addSubview(totalView)
            
            self.layer?.addSublayer(self.limitColorMask)
            self.layer?.addSublayer(self.totalColorMask)
            
            limitedView.userInteractionEnabled = false
            limitedView.isSelectable = false
            
            totalView.userInteractionEnabled = false
            totalView.isSelectable = false
        }
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)
            
            guard let availability else {
                return
            }
            
            let percent = CGFloat(availability.remains) / CGFloat(availability.total)
            
            ctx.setFillColor(theme.colors.grayForeground.cgColor)
            ctx.fill(bounds)
            
            
            ctx.setFillColor(theme.colors.accent.cgColor)
            ctx.fill(NSMakeRect(0, 0, bounds.width * percent, bounds.height))
            
        }
        
        public func set(availability: StarGift.Gift.Availability) {
            self.availability = availability
            needsDisplay = true
            
            
            
            
            
            let limitedLayout = TextViewLayout(.initialize(string: strings().giftingStarGiftLimited, color: .white, font: .medium(.text)))
            limitedLayout.measure(width: .greatestFiniteMagnitude)
            self.limitedView.update(limitedLayout)
            
            
            let percent = CGFloat(availability.remains) / CGFloat(availability.total)

            let w = frame.width * percent

            limitColorMask.contents = generateImage(limitedLayout.layoutSize, contextGenerator: { size, ctx in
                let width = w - 10
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, width, size.height))
                
                ctx.setFillColor(theme.colors.grayIcon.cgColor)
                ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
            })
            
            limitColorMask.mask = self.limitedView.drawingLayer
            
                        
            let totalLayout = TextViewLayout(.initialize(string: availability.total.formattedWithSeparator, color: .white, font: .medium(.text)))
            totalLayout.measure(width: .greatestFiniteMagnitude)
            self.totalView.update(totalLayout)
            
            totalColorMask.contents = generateImage(totalLayout.layoutSize, contextGenerator: { size, ctx in
                let minx = frame.width - 10 - size.width
                
                let width = max(0,  w - minx)
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, width, size.height))
                
                ctx.setFillColor(theme.colors.grayIcon.cgColor)
                ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
                
            })
            
            totalColorMask.mask = self.totalView.drawingLayer

        }
        
        public override func layout() {
            super.layout()
            limitedView.centerY(x: 10)
            limitColorMask.frame = limitedView.frame
            self.totalView.centerY(x: frame.width - totalView.frame.width - 10)
            self.totalColorMask.frame = totalView.frame
        }
    }
    
    private let lineView = LineView(frame: .zero)
    private let badgeView = BadgeView(frame: NSMakeSize(100, 30).bounds)
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(lineView)
        addSubview(badgeView)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? LimitedRowItem else {
            return
        }
        
        let availability = item.availability

        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)

        lineView.set(availability: item.availability)
        let size = badgeView.update(sliderValue: Int64(availability.remains), realValue: Int64(availability.remains), max: Int64(availability.total))
        badgeView.setFrameSize(size)
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? LimitedRowItem else {
            return
        }
        
        let availability = item.availability
        let percent = CGFloat(availability.remains) / CGFloat(availability.total)
        
        let w = floorToScreenPixels(percent * (frame.width - 40))
        
        badgeView.setFrameOrigin(NSMakePoint(20 + w - badgeView.frame.width * badgeView.tailPosition, 10))

        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)
        
    }
    
}


public final class AuctionLimitRowItem : GeneralRowItem {
    fileprivate let availability: StarGift.Gift.Availability
    public init(_ initialSize: NSSize, stableId: AnyHashable, availability: StarGift.Gift.Availability) {
        self.availability = availability
        super.init(initialSize, height: 30, stableId: stableId)
    }

    public override var accessibilityLabel: String? {
        return strings().starAuctionSendPreviewLeftOther(Int(availability.remains))
    }

    public override var accessibilityValue: String? {
        let sold = Int(availability.total - availability.remains)
        return sold > 0 ? strings().starAuctionSendPreviewSoldOther(sold) : nil
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return AuctionLimitRowView.self
    }
}

private final class AuctionLimitRowView : GeneralRowView {
    
    
    private class LineView : View {
        private var availability: StarGift.Gift.Availability?
        private let limitedView = TextView()
        private let totalView = TextView()
        
        private let limitColorMask = SimpleLayer()
        private let totalColorMask = SimpleLayer()
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.layer?.cornerRadius = 10
            addSubview(limitedView)
            addSubview(totalView)
            
            self.layer?.addSublayer(self.limitColorMask)
            self.layer?.addSublayer(self.totalColorMask)
            
            limitedView.userInteractionEnabled = false
            limitedView.isSelectable = false
            
            totalView.userInteractionEnabled = false
            totalView.isSelectable = false
        }
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)
            
            guard let availability else {
                return
            }
            
            let percent = CGFloat(availability.remains) / CGFloat(availability.total)
            
            ctx.setFillColor(theme.colors.grayForeground.cgColor)
            ctx.fill(bounds)
            
            
            ctx.setFillColor(theme.colors.accent.cgColor)
            ctx.fill(NSMakeRect(0, 0, bounds.width * percent, bounds.height))
            
        }
        
        public func set(availability: StarGift.Gift.Availability) {
            self.availability = availability
            needsDisplay = true
            
            let limitedLayout = TextViewLayout(
                .initialize(
                    string: strings().starAuctionSendPreviewLeftOther(Int(availability.remains)),
                    color: .white,
                    font: .medium(.text)
                )
            )
            limitedLayout.measure(width: .greatestFiniteMagnitude)
            self.limitedView.update(limitedLayout)


            let percent = CGFloat(availability.remains) / CGFloat(availability.total)
            let w = frame.width * percent

            limitColorMask.contents = generateImage(limitedLayout.layoutSize, contextGenerator: { size, ctx in
                let width = w - 10
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, width, size.height))
                
                ctx.setFillColor(theme.colors.grayIcon.cgColor)
                ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
            })

            limitColorMask.mask = self.limitedView.drawingLayer

            let sold = Int(availability.total - availability.remains)
            let totalLayout: TextViewLayout?
            if sold > 0 {
                totalLayout = TextViewLayout(
                    .initialize(
                        string: strings().starAuctionSendPreviewSoldOther(sold),
                        color: .white,
                        font: .medium(.text)
                    )
                )
                totalLayout?.measure(width: .greatestFiniteMagnitude)
            } else {
                totalLayout = nil
            }
            self.totalView.update(totalLayout)

            
            totalColorMask.contents = generateImage(totalLayout?.layoutSize ?? .zero, contextGenerator: { size, ctx in
                let minx = frame.width - 10 - size.width
                
                let width = max(0,  w - minx)
                ctx.setFillColor(theme.colors.underSelectedColor.cgColor)
                ctx.fill(NSMakeRect(0, 0, width, size.height))
                
                ctx.setFillColor(theme.colors.grayIcon.cgColor)
                ctx.fill(NSMakeRect(width, 0, size.width - width, size.height))
                
            })
            
            totalColorMask.mask = self.totalView.drawingLayer

        }
        
        public override func layout() {
            super.layout()
            limitedView.centerY(x: 10)
            limitColorMask.frame = limitedView.frame
            self.totalView.centerY(x: frame.width - totalView.frame.width - 10)
            self.totalColorMask.frame = totalView.frame
        }
    }
    
    private let lineView = LineView(frame: .zero)
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(lineView)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? AuctionLimitRowItem else {
            return
        }
        
        _ = item.availability

        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)

        lineView.set(availability: item.availability)
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? AuctionLimitRowItem else {
            return
        }
        
        let availability = item.availability
        let percent = CGFloat(availability.remains) / CGFloat(availability.total)
        
        _ = floorToScreenPixels(percent * (frame.width - 40))
        
        lineView.frame = NSMakeRect(20, frame.height - 30, frame.width - 40, 30)
        
    }
    
}

private var wishMessagePlaceholder: String { strings().starGiftPreviewWishPlaceholder }

private final class PreviewRowItem : GeneralRowItem {
    public let context: (any AccountContextProtocol)
    public let peer: EnginePeer
    public let source: PreviewGiftSource
    public let includeUpgrade: Bool
    public let headerLayout: TextViewLayout
    
    public let presentation: TelegramPresentationTheme
    public let titleLayout: TextViewLayout
    public let infoLayout: TextViewLayout

    public let authorLayout: TextViewLayout?
    public let authorPeer: Peer?
    public let openPeerInfo:(PeerId)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, peer: EnginePeer, myPeer: EnginePeer, source: PreviewGiftSource, message: Updated_ChatTextInputState, context: (any AccountContextProtocol), viewType: GeneralViewType, includeUpgrade: Bool, payWithStars: Bool, openPeerInfo:@escaping(PeerId)->Void, author: Peer?) {
        self.context = context
        self.peer = peer
        self.source = source
        self.includeUpgrade = includeUpgrade
        self.presentation = theme.withUpdatedChatMode(true)
        self.openPeerInfo = openPeerInfo
        
        let titleAttr = NSMutableAttributedString()
        
        switch source {
        case .starGift:
            if peer.id == myPeer.id {
                titleAttr.append(string: strings().notificationStarGiftSelfTitle, color: presentation.chatServiceItemTextColor, font: .medium(.header))
            } else {
                titleAttr.append(string: strings().chatServiceStarGiftFrom(myPeer._asPeer().compactDisplayTitle), color: presentation.chatServiceItemTextColor, font: .medium(.header))
            }
        case .premium(let option, _):
            titleAttr.append(string: strings().giftPremiumHeader(timeIntervalString(Int(option.months) * 30 * 60 * 60 * 24)), color: presentation.chatServiceItemTextColor, font: .medium(.header))
        }
        
        
        self.titleLayout = TextViewLayout(titleAttr, alignment: .center)

        let infoText = NSMutableAttributedString()

        if !message.string.isEmpty {
            let textInputState = message.textInputState()
            let entities = textInputState.messageTextEntities()

            let attr = StarsHooks.shared.applyMessageEntities(entities, message.string, context, 13, { _, _, _, _ in }, presentation.chatServiceItemTextColor, theme.colors.isDark, true).mutableCopy() as! NSMutableAttributedString
            InlineStickerItem.apply(to: attr, associatedMedia: textInputState.inlineMedia, entities: entities, isPremium: context.isPremium)
            infoText.append(attr)
        } else {
            switch source {
            case .starGift(let option):
                if peer.id == myPeer.id {
                    infoText.append(string: strings().notificationStarsGiftSubtitleSelf, color: presentation.chatServiceItemTextColor, font: .normal(.text))
                } else {
                    if peer._asPeer().isChannel {
                        infoText.append(string: strings().starsGiftPreviewChannelDisplay(strings().starListItemCountOther(Int(option.native.generic!.convertStars))) , color: presentation.chatServiceItemTextColor, font: .normal(.text))
                    } else {
                        infoText.append(string: strings().starsGiftPreviewDisplay(strings().starListItemCountOther(Int(option.native.generic!.convertStars))) , color: presentation.chatServiceItemTextColor, font: .normal(.text))
                    }
                }
            case .premium:
                infoText.append(string: strings().giftPremiumText, color: presentation.chatServiceItemTextColor, font: .normal(.text))
            }
        }

        self.infoLayout = .init(infoText, alignment: .center)
        
        switch source {
        case .starGift(let option):
            if peer.id == myPeer.id {
                headerLayout = .init(.initialize(string: strings().notificationStarsGiftSelfBought(strings().starListItemCountOther(Int(option.stars))), color: presentation.chatServiceItemTextColor, font: .normal(.text)), alignment: .center)
            } else {
                let text: String
                if peer._asPeer().isChannel {
                    text = strings().chatServicePremiumGiftSentChannel(myPeer._asPeer().compactDisplayTitle, peer._asPeer().compactDisplayTitle, strings().starListItemCountOther(Int(option.stars)))
                } else {
                    text = strings().chatServicePremiumGiftSent(myPeer._asPeer().compactDisplayTitle, strings().starListItemCountOther(Int(option.stars)))
                }
                headerLayout = .init(.initialize(string: text, color: presentation.chatServiceItemTextColor, font: .normal(.text)), alignment: .center)
            }
        case let .premium(option, starOption):
            let text: String
            if payWithStars, let starOption {
                text = strings().chatServicePremiumGiftSent(myPeer._asPeer().compactDisplayTitle, strings().starListItemCountOther(Int(starOption.priceCurrencyAndAmount.amount)))
            } else {
                text = strings().chatServicePremiumGiftSent(myPeer._asPeer().compactDisplayTitle, option.price)
            }
            
            headerLayout = .init(.initialize(string: text, color: presentation.chatServiceItemTextColor, font: .normal(.text)), alignment: .center)
        }
        
        switch source {
        case .starGift:
            
            if let author {
                self.authorLayout = .init(
                    .initialize(
                        string: strings().starTransactionReleasedBy(author.addressName ?? ""),
                        color: presentation.chatServiceItemTextColor,
                        font: .normal(.text)
                    ),
                    maximumNumberOfLines: 1,
                    truncationType: .middle
                )
            } else {
                self.authorLayout = nil
            }
            self.authorPeer = author
        case .premium:
            self.authorLayout = nil
            self.authorPeer = nil
        }
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public var shouldBlurService: Bool {
        return true
    }
    
    public var isBubbled: Bool {
        return presentation.bubbled
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        headerLayout.measure(width: blockWidth - 40)
        titleLayout.measure(width: 200 - 20)
        infoLayout.measure(width: 200 - 20)
        
        authorLayout?.measure(width: 200 - 40)
        
        if shouldBlurService {
            headerLayout.generateAutoBlock(backgroundColor: NSColor.black.withAlphaComponent(0.15))
        } else {
            headerLayout.generateAutoBlock(backgroundColor: presentation.chatServiceItemColor)
        }
        
        if shouldBlurService {
            authorLayout?.generateAutoBlock(backgroundColor: NSColor.black.withAlphaComponent(0.15))
        } else {
            authorLayout?.generateAutoBlock(backgroundColor: presentation.chatServiceItemColor)
        }
//
        return true
    }
    
    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        var parts: [String] = [headerLayout.attributedString.string, infoLayout.attributedString.string.replacingOccurrences(of: "\u{FFFC}", with: "")]
        if case let .starGift(option) = source, let availability = option.native.generic?.availability {
            parts.append(strings().starTransactionAvailabilityOf(1, Int(availability.total).prettyNumber))
        }
        if let authorLayout {
            parts.append(authorLayout.attributedString.string)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public override func viewClass() -> AnyClass {
        return PreviewRowView.self
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        height += 20
        height += headerLayout.layoutSize.height
        height += blockHeight
        height += 20
        return height
    }
    
    public var blockHeight: CGFloat {
        var height: CGFloat = 0
        height += 100
        height += 15
        height += titleLayout.layoutSize.height
        height += 2
        height += infoLayout.layoutSize.height
        height += 10
        height += 40
        
        if let authorLayout {
            height += authorLayout.layoutSize.height
            height += 5
        }
        
        return height
    }
    
    public override var hasBorder: Bool {
        return false
    }
}

private final class PreviewRowView : GeneralContainableRowView {
    private let backgroundView = BackgroundView(frame: .zero)
    private let headerView = TextView()
    private let headerVisualEffect: VisualEffect = VisualEffect(frame: .zero)

    private final class BlockView : View {
        private let sticker = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 100, 100))
        private var authorView: TextView?
        private let headerView = InteractiveTextView()
        private let textView = InteractiveTextView()
        private var visualEffect: VisualEffect?
        private var imageView: ImageView?
        
        private let button = TextButton()
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(sticker)
            addSubview(headerView)
            addSubview(textView)
            addSubview(button)
            
            textView.userInteractionEnabled = false
            
            layer?.cornerRadius = 10
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        
        public func update(item: PreviewRowItem, animated: Bool) {
            headerView.set(text: item.titleLayout, context: item.context)
            textView.set(text: item.infoLayout, context: item.context)

            button.userInteractionEnabled = false
            button.set(font: .medium(.text), for: .Normal)
            button.set(color: item.presentation.chatServiceItemTextColor, for: .Normal)
            button.set(background: item.shouldBlurService ? item.presentation.blurServiceColor : item.presentation.chatServiceItemColor, for: .Normal)
            button.set(text: item.includeUpgrade ? strings().giftUpgradeUpgrade : strings().chatServiceGiftView, for: .Normal)
            button.sizeToFit(NSMakeSize(20, 14))
            button.layer?.cornerRadius = button.frame.height / 2
            switch item.source {
            case .starGift(let option):
                (sticker as? StarsStickerView)?.updateStarsSticker(file: option.media, size: sticker.frame.size, context: item.context, colors: [], playback: .onceEnd, animated: animated)
            case .premium(let option, _):
                let media: TelegramMediaFile
                switch option.months {
                case 3:
                    media = LocalAnimatedSticker.premium_gift_3.file
                case 6:
                    media = LocalAnimatedSticker.premium_gift_6.file
                default:
                    media = LocalAnimatedSticker.premium_gift_12.file
                }

                (sticker as? StarsStickerView)?.updateStarsSticker(file: media, size: sticker.frame.size, context: item.context, colors: [], playback: .onceEnd, animated: animated)
            }
            
            if let authorLayout = item.authorLayout, let author = item.authorPeer {
                let current: TextView
                if let view = self.authorView {
                    current = view
                } else {
                    current = TextView()
                    current.userInteractionEnabled = true
                    current.scaleOnClick = true
                    current.isSelectable = false
                    self.authorView = current
                    self.addSubview(current)
                }
                current.update(authorLayout)
                
                let context = item.context
                
                current.setSingle(handler: { [weak item] view in
                    if let event = NSApp.currentEvent {
                        let data = context.engine.data.subscribe(
                            TelegramEngine.EngineData.Item.Peer.Peer(id: author.id),
                            TelegramEngine.EngineData.Item.Peer.AboutText(id: author.id)
                        ) |> take(1) |> deliverOnMainQueue
                        
                        _ = data.start(next: { [weak view, weak item] data in
                            
                            guard let peer = data.0, let view = view else {
                                return
                            }
                            
                            var firstBlock:[ContextMenuItem] = []
                            let secondBlock:[ContextMenuItem] = []
                            let thirdBlock: [ContextMenuItem] = []
                            
                            if let avatarItem = StarsHooks.shared.makeAvatarMenuItem(context, peer._asPeer()) {
                                firstBlock.append(avatarItem)
                            }
                            
                            firstBlock.append(ContextMenuItem(peer._asPeer().displayTitle, handler: {
                                item?.openPeerInfo(peer.id)
                            }, itemImage: MenuAnimation.menu_open_profile.value))
                            
                            if let username = peer.addressName {
                                firstBlock.append(ContextMenuItem("\(username)", handler: {
                                    item?.openPeerInfo(peer.id)
                                }, itemImage: MenuAnimation.menu_atsign.value))
                            }
                            
                            switch data.1 {
                            case let .known(about):
                                if let about = about, !about.isEmpty {
                                    firstBlock.append(ContextMenuItem(about, handler: {
                                        item?.openPeerInfo(peer.id)
                                    }, itemImage: MenuAnimation.menu_bio.value, removeTail: false, overrideWidth: 200))
                                }
                            default:
                                break
                            }
                            
                            let blocks:[[ContextMenuItem]] = [firstBlock,
                                                              secondBlock,
                                                              thirdBlock].filter { !$0.isEmpty }
                            var items: [ContextMenuItem] = []

                            for (i, block) in blocks.enumerated() {
                                if i != 0 {
                                    items.append(ContextSeparatorItem())
                                }
                                items.append(contentsOf: block)
                            }
                            
                            let menu = ContextMenu()
                            
                            for item in items {
                                menu.addItem(item)
                            }
                            AppMenu.show(menu: menu, event: event, for: view)
                        })
                    }
                }, for: .Click)
            } else if let view = self.authorView {
                performSubviewRemoval(view, animated: animated)
                self.authorView = nil
            }
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            switch item.source {
            case .starGift(let option):
                if let availability = option.native.generic?.availability {
                    let current: ImageView
                    if let view = self.imageView {
                        current = view
                    } else {
                        current = ImageView()
                        current.isAccessibilityDecorative = true
                        addSubview(current)
                        self.imageView = current
                    }
                    
                    let text: String = strings().starTransactionAvailabilityOf(1, Int(availability.total).prettyNumber)
                    let color = item.presentation.chatServiceItemColor
                    
                    let ribbon = generateGradientTintedImage(image: TelegramThemeHooks.shared.image(.giftRibbon).precomposed(), colors: [color.withMultipliedBrightnessBy(1.1), color.withMultipliedBrightnessBy(0.9)], direction: .diagonal)!
                    
                    current.image = generateGiftBadgeBackground(background: ribbon, text: text)
                    current.sizeToFit()
                } else if let view = self.imageView {
                    performSubviewRemoval(view, animated: animated)
                    self.imageView = nil
                }
            case .premium:
                if let view = self.imageView {
                    performSubviewRemoval(view, animated: animated)
                    self.imageView = nil
                }
            }
            
            
            
            let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.1, curve: .easeOut) : .immediate
            updateLayout(size: NSMakeSize(frame.width, item.blockHeight), transition: transition)
        }

        public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: sticker, frame: sticker.centerFrameX(y: 5))
            if let visualEffect {
                transition.updateFrame(view: visualEffect, frame: size.bounds)
            }
            if let imageView {
                transition.updateFrame(view: imageView, frame: NSMakeRect(size.width - imageView.frame.width, 0, imageView.frame.width, imageView.frame.height))
            }

            transition.updateFrame(view: headerView, frame: headerView.centerFrameX(y: sticker.frame.maxY + 10))
            var offset: CGFloat = 0
            if let authorView {
                transition.updateFrame(view: authorView, frame: authorView.centerFrameX(y: headerView.frame.maxY + 5))
                offset += authorView.frame.height + 2
            }

            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: headerView.frame.maxY + 2 + offset))
            transition.updateFrame(view: button, frame: button.centerFrameX(y: textView.frame.maxY + 10))
        }

        public override func layout() {
            super.layout()
            updateLayout(size: frame.size, transition: .immediate)
        }
    }
    
    private let blockView = BlockView(frame: .zero)
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(headerVisualEffect)
        addSubview(headerView)
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        
        addSubview(blockView)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PreviewRowItem else {
            return
        }
        
        
        headerView.update(item.headerLayout)
        blockView.update(item: item, animated: animated)
        backgroundView.backgroundMode = item.presentation.backgroundMode
    }
  
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? PreviewRowItem else {
            return
        }
    
        transition.updateFrame(view: backgroundView, frame: containerView.bounds)
        transition.updateFrame(view: headerView, frame: headerView.centerFrameX(y: 15))

        
        let blockFrame = containerView.bounds.focusX(NSMakeSize(200, item.blockHeight), y: headerView.frame.maxY + 15)
        transition.updateFrame(view: blockView, frame: blockFrame)
        blockView.updateLayout(size: blockFrame.size, transition: transition)
        
    }
    
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let toggleAnonymous: ()->Void
    public let toggleUpgrade: ()->Void
    public let updateState:(Updated_ChatTextInputState)->Void
    public let previewUpgrade:(PeerStarGift)->Void
    public let buyStars:()->Void
    public let togglePayWithStars:()->Void
    public let openMarketplace:()->Void
    public let openPeerInfo:(PeerId)->Void
    public let showAuctionInfo:(StarGift.Gift)->Void
    public init(context: (any AccountContextProtocol), toggleAnonymous: @escaping()->Void, updateState:@escaping(Updated_ChatTextInputState)->Void, toggleUpgrade: @escaping()->Void, previewUpgrade:@escaping(PeerStarGift)->Void, buyStars:@escaping()->Void, togglePayWithStars:@escaping()->Void, openMarketplace:@escaping()->Void, openPeerInfo:@escaping(PeerId)->Void, showAuctionInfo: @escaping(StarGift.Gift)->Void) {
        self.context = context
        self.toggleAnonymous = toggleAnonymous
        self.updateState = updateState
        self.toggleUpgrade = toggleUpgrade
        self.previewUpgrade = previewUpgrade
        self.buyStars = buyStars
        self.togglePayWithStars = togglePayWithStars
        self.openMarketplace = openMarketplace
        self.openPeerInfo = openPeerInfo
        self.showAuctionInfo = showAuctionInfo
        
    }
}

private struct State : Equatable {
    public var peer: EnginePeer
    public var myPeer: EnginePeer
    public var option: PreviewGiftSource
    public var isAnonymous: Bool = false
    public var textState: Updated_ChatTextInputState
    public var starsState: StarsContext.State?
    public var includeUpgrade: Bool = false
    
    public var payWithStars: Bool = false
    
    
    public var sendMessaagePaid: StarsAmount?
    
    public var disallowedGifts: TelegramDisallowedGifts
    
    public var count: Int32 = 1
    
    public var authorPeer: EnginePeer?
    
    public var auctionState: GiftAuctionContext.State?
    
    public var currentDate: Int32 = Int32(Date().timeIntervalSince1970)
    
}

private let _id_preview = InputDataIdentifier("_id_preview")
private let _id_input = InputDataIdentifier("_id_input")
private let _id_anonymous = InputDataIdentifier("_id_anonymous")
private let _id_limit = InputDataIdentifier("_id_limit")
private let _id_upgrade = InputDataIdentifier("_id_upgrade")
private let _id_pay_stars = InputDataIdentifier("_id_pay_stars")
private let _id_resale = InputDataIdentifier("_id_resale")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    switch state.option {
    case .starGift(let option):
        if let generic = option.native.generic, let limited = generic.availability, !generic.isAuction  {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_limit, equatable: .init(option), comparable: nil, item: { initialSize, stableId in
                return LimitedRowItem(initialSize, stableId: stableId, availability: limited)
            }))
            entries.append(.sectionId(sectionId, type: .customModern(20)))
            sectionId += 1
            
            if let _ = limited.minResaleStars {
                entries.append(
                    .general(
                        sectionId: sectionId,
                        index: index,
                        value: .none,
                        error: nil,
                        identifier: _id_resale,
                        data: .init(
                            name: strings().starGiftPreviewAvailableForResale,
                            color: theme.colors.text,
                            type: .nextContext("\(limited.resale)"),
                            viewType: .singleItem,
                            action: arguments.openMarketplace
                        )
                    )
                )

                entries.append(.sectionId(sectionId, type: .customModern(20)))
                sectionId += 1
            }
        }
    case .premium:
        break
    }
    
    
    
    
    var canComment: Bool = true
    switch state.option {
    case .starGift:
        canComment = state.sendMessaagePaid == nil
    default:
        break
    }

    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starsGiftPreviewCustomize), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_preview, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return PreviewRowItem(initialSize, stableId: stableId, peer: state.peer, myPeer: state.myPeer, source: state.option, message: state.textState, context: arguments.context, viewType: canComment ? .firstItem : .singleItem, includeUpgrade: state.includeUpgrade, payWithStars: state.payWithStars, openPeerInfo: arguments.openPeerInfo, author: state.authorPeer?._asPeer())
    }))
    
    
    let maxTextLength: Int32
    let messagePlaceholder: String
    switch state.option {
    case .starGift:
        maxTextLength = arguments.context.appConfiguration.getGeneralValue("stargifts_message_length_max", orElse: 200)
        messagePlaceholder = wishMessagePlaceholder
    case .premium:
        maxTextLength = arguments.context.appConfiguration.getGeneralValue("stargifts_message_length_max", orElse: 256)
        messagePlaceholder = strings().starsGiftPreviewMessagePlaceholder
    }
    
    if canComment {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_input, equatable: .init(state.textState), comparable: nil, item: { initialSize, stableId in
            return StarsHooks.shared.makeInputTextRow(initialSize, stableId, arguments.context, state.textState, messagePlaceholder, maxTextLength, { text in
                var text = text
                while text.contains("\n\n\n") {
                    text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
                }
                
                if !text.isEmpty {
                    while text.range(of: "\n")?.lowerBound == text.startIndex {
                        text = String(text[text.index(after: text.startIndex)...])
                    }
                }
                return text
            }, arguments.updateState)
        }))
        index += 1
        
        switch state.option {
        case .starGift:
            if let sendMessaagePaid = state.sendMessaagePaid {
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().giftingUserChargeStars(state.peer._asPeer().displayTitle, strings().starListItemCountOther(Int(sendMessaagePaid.value)))), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textBottomItem)))
            }
        default:
            break
        }
    }
   
   
    switch state.option {
    case let .starGift(option):
        if let gift = option.native.generic, let limit = gift.perUserLimit {
            entries.append(.desc(
                sectionId: sectionId,
                index: index,
                text: .plain(strings().starsGiftPreviewLimitedText(Int(limit.remains))),
                data: .init(
                    color: theme.colors.listGrayText,
                    detectBold: true,
                    viewType: .textBottomItem
                )
            ))
            index += 1
        }
    default:
        break
    }
    
  
    switch state.option {
    case let .starGift(option: gift):
        
        
        if let upgraded = gift.native.generic?.upgradeStars, arguments.context.peerId != state.peer.id, !state.disallowedGifts.contains(.unique) {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_upgrade, data: .init(name: strings().giftSendUpgrade(strings().starListItemCountOther(Int(upgraded))), color: theme.colors.text, type: .switchable(state.includeUpgrade), viewType: .singleItem, action: arguments.toggleUpgrade)))

            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().giftSendUpgradeInfo(state.peer._asPeer().displayTitle), linkHandler: { _ in
                arguments.previewUpgrade(gift)
            }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1

        }
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_anonymous, data: .init(name: strings().starsGiftPreviewHideMyName, color: theme.colors.text, type: .switchable(state.isAnonymous), viewType: .singleItem, action: arguments.toggleAnonymous)))
        
        let name = state.peer._asPeer().compactDisplayTitle
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.peer.id == arguments.context.peerId ? strings().giftSendSelfHideMyNameInfo : strings().starsGiftPreviewHideMyNameInfo(name, name)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
        if let gift = gift.native.generic, let auctionState = state.auctionState, let dropSize = gift.auctionGiftsPerRound {
            switch auctionState.auctionState {
            case let .ongoing(_, _, _, _, _, _, _, giftsLeft, _, dropsTotal, _, _):
                entries.append(.sectionId(sectionId, type: .customModern(20)))
                sectionId += 1
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_limit, equatable: .init(auctionState), comparable: nil, item: { initialSize, stableId in
                    return AuctionLimitRowItem(initialSize, stableId: stableId, availability: .init(remains: giftsLeft, total: dropSize * dropsTotal, resale: 0, minResaleStars: nil))
                }))
                let droppedAttr = parseMarkdownIntoAttributedString(
                    strings().starAuctionPreviewGiftsDroppedInfoOther(
                        Int(giftsLeft),
                        strings().starAuctionPreviewTopBiddersOther(Int(dropSize))
                    ) + " [\(strings().starAuctionPreviewSendLearnMore)]()",
                    attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(11.5), textColor: theme.colors.listGrayText), bold: MarkdownAttributeSet(font: .bold(11.5), textColor: theme.colors.listGrayText), link: MarkdownAttributeSet(font: .normal(11.5), textColor: theme.colors.link), linkAttribute: { link in
                        return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { _ in
                            arguments.showAuctionInfo(gift)
                        }))
                    })).mutableCopy() as! NSMutableAttributedString
                droppedAttr.replaceChevron(color: theme.colors.link)
                entries.append(
                    .desc(
                        sectionId: sectionId,
                        index: index,
                        text: .attributed(droppedAttr),
                        data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem, context: arguments.context)
                    )
                )
                index += 1
            default:
                break
                
            }

        }
        
    case let .premium(_, starOption):
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().giftPremiumPreviewInfo(state.peer._asPeer().compactDisplayTitle)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
        
        if let starOption {
            
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_pay_stars, data: .init(name: strings().giftPremiumPayWith(strings().starListItemCountOther(Int(starOption.giftOption.amount))), color: theme.colors.text, type: .switchable(state.payWithStars), viewType: .singleItem, action: arguments.togglePayWithStars)))
                        
            if let starsState = state.starsState {
                let str = strings().giftPremiumYourBalance(clown + " " + starsState.balance.stringValue)
                
                let attr = parseMarkdownIntoAttributedString(str, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.listGrayText), bold: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.listGrayText), link: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.link), linkAttribute: { contents in
                    return (NSAttributedString.Key.link.rawValue, contents)
                })).mutableCopy() as! NSMutableAttributedString
                
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
                
                let linkExecutor = LinkHooks.shared.globalLinkExecutor()
                
                linkExecutor.processURL = { _ in
                    arguments.buyStars()
                }
                
                entries.append(.desc(sectionId: sectionId, index: index, text: .attributed(attr), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem, context: arguments.context, linkExecutor: linkExecutor)))
                index += 1
            }
        }
        
    }
   
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public enum PreviewGiftSource : Equatable {
    case starGift(option: PeerStarGift)
    case premium(option: PremiumGiftProduct, starOption: PremiumGiftProduct?)
}

public func PreviewStarGiftController(context: (any AccountContextProtocol), option: PreviewGiftSource, peer: EnginePeer, disallowedGifts: TelegramDisallowedGifts, starGiftsProfile: ProfileGiftsContext? = nil) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let paymentDisposable = MetaDisposable()
    
    let starGiftsProfile: ProfileGiftsContext = starGiftsProfile ?? ProfileGiftsContext(account: context.account, peerId: peer.id)
    
    let inAppPurchaseManager = context.inAppPurchaseManager
    
    let initialState = State(peer: peer, myPeer: .init(context.myPeer!), option: option, isAnonymous: peer.id == context.peerId, textState: .init(), disallowedGifts: disallowedGifts)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var auctionContext: GiftAuctionContext? = nil
    
    
    let auctionContextState: Promise<GiftAuctionContext.State?> = Promise(nil)
  
    switch option {
    case let .starGift(option):
        if let gift = option.native.generic, gift.isAuction {
            auctionContext = GiftAuctionContext(account: context.account, gift: .generic(gift))
            actionsDisposable.add(context.giftAuctionsManager.auctionContext(for: .giftId(gift.id)).startStandalone(next: { value in
                auctionContext = value
                if let value {
                    auctionContextState.set(value.state)
                }
            }))
        }
    default:
        break
    }
    
    

    
    var close:(()->Void)? = nil
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }
    
    let authorPeer: Signal<EnginePeer?, NoError>
    switch option {
    case .starGift(let option):
        if let authorId = option.native.releasedBy {
            authorPeer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: authorId))
        } else {
            authorPeer = .single(nil)
        }
    case .premium:
        authorPeer = .single(nil)
    }
    
    let sendMessaagePaid = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.SendPaidMessageStars(id: peer.id))
    

    actionsDisposable.add(combineLatest(context.starsContext.state, sendMessaagePaid, authorPeer, auctionContextState.get()).startStrict(next: { state, sendMessaagePaid, authorPeer, auctionContextState in
        updateState { current in
            var current = current
            current.starsState = state
            current.sendMessaagePaid = sendMessaagePaid
            current.authorPeer = authorPeer
            current.auctionState = auctionContextState
            return current
        }
    }))
    
    let timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: true, completion: {
        updateState { current in
            var current = current
            current.currentDate = context.timestamp
            return current
        }
    }, queue: .mainQueue())
    
    timer.start()

    let arguments = Arguments(context: context, toggleAnonymous: {
        updateState { current in
            var current = current
            current.isAnonymous = !current.isAnonymous
            return current
        }
    }, updateState: { state in
        updateState { current in
            var current = current
            current.textState = state
            return current
        }
    }, toggleUpgrade: {
        updateState { current in
            var current = current
            current.includeUpgrade = !current.includeUpgrade
            return current
        }
    }, previewUpgrade: { gift in
        if let giftId = gift.native.generic?.id {
            _ = showModalProgress(signal: context.engine.payments.starGiftUpgradePreview(giftId: giftId), for: window).startStandalone(next: { attributes in
                if let attributes {
                    showModal(with: StarGift_Nft_Controller(context: context, gift: gift.native, source: .preview(peer, attributes)), for: window)
                }
            })
        }
    }, buyStars: {
        showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: nil)), for: window)
    }, togglePayWithStars: {
        updateState { current in
            var current = current
            current.payWithStars = !current.payWithStars
            return current
        }
    }, openMarketplace: {
        switch option {
        case .starGift(let option):
            switch option.native {
            case .generic(let gift):
                showModal(with: StarGift_MarketplaceController(context: context, peerId: peer.id, gift: gift), for: window)
            case .unique:
                break
            }
        case .premium:
            break
        }
    }, openPeerInfo: { peerId in
        closeAllModals(window: window)
        StarsHooks.shared.openChat(context, peerId, nil)
    }, showAuctionInfo: { gift in
        showModal(with: Star_AuctionInfoController(context: context, gift: gift), for: window)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: context.peerId == peer.id ? strings().starGiftPreviewTitleBuy : strings().starGiftPreviewTitle)
    controller.analyticsScreen = .giftsPreview
    
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    let buyNonStore:(PremiumGiftProduct)->Void = { premiumProduct in
        let state = stateValue.with { $0 }
        
        let peer = state.peer
        
        let source = BotPaymentInvoiceSource.giftCode(users: [peer.id], currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount, option: .init(users: 1, months: premiumProduct.months, storeProductId: nil, storeQuantity: 0, currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount), text: state.textState.string, entities: state.textState.textInputState().messageTextEntities())
                        
        let invoice = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: source), for: context.window)

        _ = invoice.start(next: { invoice in
            if let controller = FeatureNavigationHooks.shared.makePaymentsCheckoutController(context, source, invoice, { status in
                switch status {
                case .paid:
                    PlayConfetti(for: context.window)
                    close?()
                default:
                    break
                }
            }) { showModal(with: controller, for: context.window) }
        }, error: { error in
            showModalText(for: context.window, text: strings().paymentsInvoiceNotExists)
        })
    }
    
    let buyWithStars:(PremiumGiftProduct)->Void = { premiumProduct in
        let state = stateValue.with { $0 }
        
        let peer = state.peer
        
        let source = BotPaymentInvoiceSource.premiumGift(peerId: peer.id, option: CachedPremiumGiftOption(months: premiumProduct.months, currency: premiumProduct.giftOption.currency, amount: premiumProduct.giftOption.amount, botUrl: nil, storeProductId: premiumProduct.giftOption.storeProductId), text: state.textState.string, entities: state.textState.textInputState().messageTextEntities())
                        
        let form = showModalProgress(signal: context.engine.payments.fetchBotPaymentForm(source: source, themeParams: [:]), for: context.window)

        _ = form.start(next: { form in
            _ = showModalProgress(signal: context.engine.payments.sendStarsPaymentForm(formId: form.id, source: source), for: window).startStandalone(next: { result in
                switch result {
                case .done:
                    PlayConfetti(for: window, stars: true)
                    context.starsContext.load(force: true)
                    context.starsSubscriptionsContext.load(force: true)
                    closeAllModals(window: window)
                default:
                    break
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
        }, error: { error in
            showModalText(for: context.window, text: strings().paymentsInvoiceNotExists)
        })
    }
    
    let buyAppStore:(PremiumGiftProduct)->Void = { premiumProduct in
        
        let state = stateValue.with { $0 }
        
        let peer = state.peer

        guard let storeProduct = premiumProduct.storeProduct else {
            buyNonStore(premiumProduct)
            return
        }
        
        let lockModal = PremiumLockModalController()
        
        var needToShow = true
        delay(0.2, closure: {
            if needToShow {
                showModal(with: lockModal, for: context.window)
            }
        })
        let purpose: AppStoreTransactionPurpose = .giftCode(peerIds: [peer.id], boostPeer: nil, currency: premiumProduct.priceCurrencyAndAmount.currency, amount: premiumProduct.priceCurrencyAndAmount.amount, text: state.textState.string, entities: state.textState.textInputState().messageTextEntities())
        
                
        let _ = (context.engine.payments.canPurchasePremium(purpose: purpose)
        |> deliverOnMainQueue).start(next: { [weak lockModal] available in
            if available {
                paymentDisposable.set((inAppPurchaseManager.buyProduct(storeProduct, quantity: premiumProduct.giftOption.storeQuantity, purpose: purpose)
                |> deliverOnMainQueue).start(next: { [weak lockModal] status in
    
                    lockModal?.close()
                    needToShow = false
                    
                    inAppPurchaseManager.finishAllTransactions()
                    PlayConfetti(for: context.window)
                    close?()
                    
                }, error: { [weak lockModal] error in
                    let errorText: String
                    switch error {
                        case .generic:
                            errorText = strings().premiumPurchaseErrorUnknown
                        case .network:
                            errorText = strings().premiumPurchaseErrorNetwork
                        case .notAllowed:
                            errorText = strings().premiumPurchaseErrorNotAllowed
                        case .cantMakePayments:
                            errorText = strings().premiumPurchaseErrorCantMakePayments
                        case .assignFailed:
                            errorText = strings().premiumPurchaseErrorUnknown
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
    
    
    controller.validateData = { [weak auctionContext] _ in
        
        let state = stateValue.with { $0 }
        
        guard let starsState = state.starsState else {
            return .none
        }
        
        switch state.option {
        case let .starGift(option):
            if let gift = option.native.generic, gift.isAuction {
                if let auctionContext {
                    showModal(with: Star_AuctionBidController(context: context, peerId: peer.id, gift: gift, auctionContext: auctionContext, hideName: state.isAnonymous, text: state.textState.string, entities: state.textState.textInputState().messageTextEntities()), for: window)
                    close?()
                }
                return .none
            }
            
            if starsState.balance.value < option.totalStars(state.includeUpgrade, count: state.count) {
                showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: option.totalStars(state.includeUpgrade))), for: window)
                return .none
            }
            
            let source: BotPaymentInvoiceSource = .starGift(hideName: state.isAnonymous, includeUpgrade: state.includeUpgrade, peerId: state.peer.id, giftId: option.native.generic!.id, text: state.textState.string, entities: state.textState.textInputState().messageTextEntities())
            
            let make:()->Signal<SendBotPaymentResult, BotPaymentFormRequestError> = {
                return  context.engine.payments.fetchBotPaymentForm(source: source, themeParams: nil) |> mapToSignal {
                    return context.engine.payments.sendStarsPaymentForm(formId: $0.id, source: source) |> mapError { _ in
                        return .generic
                    }
                }
            }
            
            var combined = make()
            for _ in 1 ..< state.count {
                combined = combined |> then(make())
            }
            
            _ = showModalProgress(signal: combined |> take(Int(state.count)), for: context.window).start(completed: {
                PlayConfetti(for: window, stars: true)
                closeAllModals(window: window)
                
                starGiftsProfile.reload()
                
                if peer._asPeer().isChannel {
                    StarsHooks.shared.openGiftsProfile(context, peer.id, starGiftsProfile)
                } else {
                    StarsHooks.shared.openChatIfNotCurrent(context, peer.id)
                }
            })
        case let .premium(option, starGift):
            
            if state.payWithStars, let starGift {
                
                let amount = starGift.priceCurrencyAndAmount.amount
                
                if starsState.balance.value < starGift.priceCurrencyAndAmount.amount {
                    showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: amount)), for: window)
                    return .none
                }
                verifyAlert(for: window, header: strings().giftingPremWithStarsConfirmTitle, information: strings().giftingPremWithStarsConfirmInfo(state.peer._asPeer().displayTitle, strings().starListItemCountOther(Int(amount))), successHandler: { _ in
                    buyWithStars(starGift)
                })
                return .none
            }
            
#if APP_STORE
            buyAppStore(option)
#else
            buyNonStore(option)
#endif
        }

        
        
        return .none
    }
    
    let modalInteractions = ModalInteractions(acceptTitle: "", accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    
    
    let updateRightHeader:()->Void = { [weak modalController, weak controller] in
        switch option {
        case let .starGift(option):
            if let gift = option.native.generic, gift.availability != nil, !gift.flags.contains(.requiresPremium), !gift.isAuction  {
                let count = stateValue.with { $0.count }
                controller?.rightModalHeader = ModalHeaderData(image: generateTextIcon(.initialize(string: "\(count)x", color: theme.colors.accent, font: .medium(.title))), contextMenu: {
                    let count = stateValue.with { $0.count }
                    return [ContextMenuItem("1x", handler: {
                        updateState { current in
                            var current = current
                            current.count = 1
                            return current
                        }
                    }, state: count == 1 ? .on : nil), ContextMenuItem("2x", handler: {
                        updateState { current in
                            var current = current
                            current.count = 2
                            return current
                        }
                    }, state: count == 2 ? .on : nil), ContextMenuItem("3x", handler: {
                        updateState { current in
                            var current = current
                            current.count = 3
                            return current
                        }
                    }, state: count == 3 ? .on : nil), ContextMenuItem("4x", handler: {
                        updateState { current in
                            var current = current
                            current.count = 4
                            return current
                        }
                    }, state: count == 4 ? .on : nil), ContextMenuItem("5x", handler: {
                        updateState { current in
                            var current = current
                            current.count = 5
                            return current
                        }
                    }, state: count == 5 ? .on : nil), ContextMenuItem("10x", handler: {
                        updateState { current in
                            var current = current
                            current.count = 10
                            return current
                        }
                    }, state: count == 10 ? .on : nil)]
                })
            }
            modalController?.updateLocalizationAndTheme(theme: theme)
        default:
            break
        }
    }
    
    controller.afterTransaction = { [weak modalInteractions] _ in
        let state = stateValue.with { $0 }
        let okText: String
        var subText: String?
        switch option {
        case let .starGift(option):
            
            if let auctionState = state.auctionState {
                okText = strings().starGiftPreviewPlaceBid
                switch auctionState.auctionState {
                case .finished:
                    close?()
                case let .ongoing(_, _, _, _, _, _, nextDropDate, _, currentRound, totalRounds, _, _):
                    
                    let dropsLeft = totalRounds - currentRound
                    
                    let nextDropTimeout = max(nextDropDate - context.timestamp, 0)
                    
                    if dropsLeft > 0 {
                        subText = strings().starGiftPreviewNextDropIn(timerText(Int(nextDropTimeout)))
                    } else {
                        subText = nil
                    }
                }
            } else if option.native.generic?.isAuction == true {
                okText = strings().starGiftPreviewPlaceBid
            } else if state.peer.id == context.peerId {
                if state.count > 1 {
                    okText = strings().starsGiftPreviewBuyMultiOther(
                        Int(state.count),
                        strings().starListItemCountOther(
                            Int(option.totalStars(state.includeUpgrade, count: state.count))
                        )
                    )
                } else {
                    okText = strings().starsGiftPreviewBuy(
                        strings().starListItemCountOther(
                            Int(option.totalStars(state.includeUpgrade, count: state.count))
                        )
                    )
                }
            } else {
                if state.count > 1 {
                    okText = strings().starsGiftPreviewSendMultiOther(
                        Int(state.count),
                        strings().starListItemCountOther(
                            Int(option.totalStars(state.includeUpgrade, count: state.count))
                        )
                    )
                } else {
                    okText = strings().starsGiftPreviewSend(
                        strings().starListItemCountOther(
                            Int(option.totalStars(state.includeUpgrade, count: state.count))
                        )
                    )
                }
            }

        case let .premium(option, starGift):
            if state.payWithStars, let starGift = starGift {
                okText = strings().starsGiftPreviewSend(strings().starListItemCountOther(Int(starGift.priceCurrencyAndAmount.amount)))
            } else {
                okText = strings().starsGiftPreviewSend(option.price)
            }
        }
        
        modalInteractions?.updateDone { button in
            button.set(text: okText, for: .Normal)
            button.set(subtext: subText, for: .Normal)
        }
        updateRightHeader()
    }
    
    updateRightHeader()
    
    
    controller.contextObject = (auctionContext, timer)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}


/*

 */
