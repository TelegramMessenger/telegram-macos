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
import UniqueGiftBackground
import FoundationUtils
import InputView
import InputTextView
import InlineStickerLayer

extension StarGift {
    public var id: Int64 {
        return self.generic?.id ?? self.unique?.id ?? 0
    }
}

extension StarGift.Gift {
    public var hasResaleAvailability: Bool {
        return (self.availability?.resale ?? 0) > 0
    }
}

private let giftTileCornerRadius: CGFloat = 16

private func ribbonOutlineImage(color: NSColor) -> CGImage? {
    let image = TelegramThemeHooks.shared.image(.giftRibbon)
    return generateScaledImage(image: image._cgImage, size: CGSize(width: image.size.width + 8, height: image.size.height + 8), opaque: true, color: color)
}


public struct PremiumPaymentOption : Equatable {
    public var title: String
    public var desc: String
    public var total: String
    public var discount: String?
    public var months: Int32
    
    public var product: PremiumGiftProduct
    public var starProduct: PremiumGiftProduct?
    
    public var media: LocalAnimatedSticker {
        switch months {
        case 12:
            return LocalAnimatedSticker.premium_gift_12
        case 6:
            return LocalAnimatedSticker.premium_gift_6
        case 3:
            return LocalAnimatedSticker.premium_gift_3
        default:
            return LocalAnimatedSticker.premium_gift_3
        }
    }
    
    public var text: NSAttributedString {
        let attr = NSMutableAttributedString()
        attr.append(string: self.title, color: theme.colors.text, font: .medium(.text))
        attr.append(string: "\n")
        attr.append(string: strings().stickersPremium, color: theme.colors.text, font: .normal(.text))
        return attr
    }
    public init(title: String, desc: String, total: String, discount: String? = nil, months: Int32, product: PremiumGiftProduct, starProduct: PremiumGiftProduct? = nil) {
        self.title = title
        self.desc = desc
        self.total = total
        self.discount = discount
        self.months = months
        self.product = product
        self.starProduct = starProduct
    }
}

public struct PeerStarGift : Equatable {
    public let media: TelegramMediaFile
    public let stars: Int64
    public let limited: Bool
    public let native: StarGift
    
    public func totalStars(_ includeUpgrade: Bool, sendMessage: StarsAmount? = nil, count: Int32 = 1) -> Int64 {
        if includeUpgrade {
            switch native {
            case let .generic(gift):
                if let upgradeStars = gift.upgradeStars {
                    return (stars + upgradeStars + (sendMessage?.value ?? 0)) * Int64(count)
                }
            default:
                return (stars + (sendMessage?.value ?? 0)) * Int64(count)
            }
        }
        return (stars + (sendMessage?.value ?? 0)) * Int64(count)
    }
    public init(media: TelegramMediaFile, stars: Int64, limited: Bool, native: StarGift) {
        self.media = media
        self.stars = stars
        self.limited = limited
        self.native = native
    }
}

extension GiftOptionsRowItem.Option {
    fileprivate var accessibilityTitle: String {
        if let gift = self.gift {
            switch gift {
            case let .generic(gift):
                return gift.title ?? strings().voiceOverCommonGift
            case let .unique(gift):
                return "\(gift.title) #\(gift.number)"
            }
        }
        if let text = self.text?.string, !text.isEmpty {
            return text.replacingOccurrences(of: "\n", with: " ")
        }
        return strings().voiceOverCommonGift
    }

    fileprivate func accessibilityStatus(selected: Bool) -> String? {
        var parts: [String] = []
        switch type {
        case let .price(string):
            parts.append(string)
        case let .stars(amount, _, addPlus, _):
            if nativeStarGift?.native.generic?.isAuction == true, nativeStarGift?.native.generic?.soldOut == nil {
                parts.append(strings().starGiftOptionJoin)
            } else {
                parts.append(strings().starListItemCountOther(Int(amount)) + (addPlus ? "+" : ""))
            }
        case .none:
            break
        }
        if let starProduct = nativePayment?.starProduct {
            parts.append(strings().giftPremiumPayOrStars(strings().starListItemCountOther(Int(starProduct.giftOption.amount))))
        }
        if let priceBadge {
            let amount = priceBadge.attributedString.string.replacingOccurrences(of: clown, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("\(amount) \(strings().voiceOverCommonStars)")
        }
        if let badge {
            parts.append(badge.text)
        }
        if let generic = gift?.generic, generic.upgradeStars != nil {
            parts.append(strings().selectGiftsFilterUpgradable)
        }
        if let peer {
            parts.append(strings().chatServiceStarGiftFrom(peer._asPeer().displayTitle))
        }
        if pinned {
            parts.append(strings().voiceOverCommonPinned)
        }
        if invisible {
            parts.append(strings().peerInfoGiftsHidden)
        }
        if limitDatePurchase != nil {
            parts.append(strings().voiceOverCommonLocked)
        }
        if let toggleSelect {
            parts.append(toggleSelect ? strings().voiceOverCommonSelected : strings().voiceOverCommonNotSelected)
        } else if selected {
            parts.append(strings().voiceOverCommonSelected)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

public final class GiftOptionsRowItem : GeneralRowItem {
    
    public struct Option : Equatable {
        
        public static func ==(lhs: Option, rhs: Option) -> Bool {
            if lhs.nativePayment != rhs.nativePayment {
                return false
            }
            if lhs.nativeProfileGift != rhs.nativeProfileGift {
                return false
            }
            if lhs.nativeStarGift != rhs.nativeStarGift {
                return false
            }
            if lhs.nativeStarUniqueGift != rhs.nativeStarUniqueGift {
                return false
            }
            if lhs.file != rhs.file {
                return false
            }
            return true
        }
        
        public enum TypeValue {
            case price(String)
            case stars(Int64, Bool, Bool, Bool)
            case none
        }
        public struct Badge {
            public let text: String
            public let colors: [NSColor]
            public let textColor: NSColor
            public let outline: Bool
            public init(text: String, colors: [NSColor], textColor: NSColor, outline: Bool) {
                self.text = text
                self.colors = colors
                self.textColor = textColor
                self.outline = outline
            }
        }
        public let file: TelegramMediaFile?
        public let image: CGImage?
        public let colors: [LottieColor]
        public let text: NSAttributedString?
        public let type: TypeValue
        public let badge: Badge?
        public let peer: EnginePeer?
        public let invisible: Bool
        public let pinned: Bool
        public let toggleSelect: Bool?
        public let limitDatePurchase: Int32?
        
        public let priceBadge: TextViewLayout?
        
        public var starsPrice: TextViewLayout?
        
        public var nativePayment: PremiumPaymentOption?
        public var nativeStarGift: PeerStarGift?
        public var nativeProfileGift: ProfileGiftsContext.State.StarGift?
        public var nativeStarUniqueGift: StarGift.UniqueGift?
        
        public var gift: StarGift? {
            return nativeStarUniqueGift.flatMap { .unique($0) } ?? nativeStarGift?.native ?? nativeProfileGift?.gift
        }
        
        public static func initialize(_ option: PremiumPaymentOption) -> Option {
            
            var colors: [NSColor] = []
            if theme.colors.isDark {
                colors = [NSColor(0x522124), NSColor(0x653634)]
            } else {
                colors = [theme.colors.redUI.withMultipliedBrightnessBy(1.1), theme.colors.redUI.withMultipliedBrightnessBy(0.9)]
            }
            
            let starsPrice: TextViewLayout?
            if let starOption = option.starProduct {
                let price = NSMutableAttributedString()
                
                price.append(string: strings().giftPremiumPayOrStars(clown + " " + "\(starOption.giftOption.amount)"), color: GOLD, font: .normal(.small))
                price.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
                
                starsPrice = .init(price)
                starsPrice?.measure(width: .greatestFiniteMagnitude)
            } else {
                starsPrice = nil
            }
            
            return .init(file: option.media.file, image: nil, colors: [], text: option.text, type: .price(option.total), badge: option.discount.flatMap { .init(text: $0, colors: colors, textColor: .white, outline: false )}, peer: nil, invisible: false, pinned: false, toggleSelect: nil, limitDatePurchase: nil, priceBadge: nil, starsPrice: starsPrice, nativePayment: option)
        }
        
        
        public static func initialize(_ image: CGImage, text: NSAttributedString) -> Option {
            return .init(file: nil, image: image, colors: [], text: text, type: .none, badge: nil, peer: nil, invisible: false, pinned: false, toggleSelect: nil, limitDatePurchase: nil, priceBadge: nil, starsPrice: nil, nativePayment: nil)
        }

        
        public static func initialize(_ option: PeerStarGift, preview: Bool = false, customText: String? = nil) -> Option {
            let badge: Badge?
            
            var redColor: [NSColor] = []
            var blueColor: [NSColor] = []
            let greenColor: [NSColor] = [NSColor(0x4bb121), NSColor(0x53d654)]
            let goldColor: [NSColor] = [NSColor(0xea8b01), NSColor(0xfab625)]
            
            if theme.colors.isDark {
                redColor = [NSColor(0x522124), NSColor(0x653634)]
                blueColor = [NSColor(0x142e42), NSColor(0x354f5b)]
            } else {
                redColor = [theme.colors.redUI.withMultipliedBrightnessBy(1.1), theme.colors.redUI.withMultipliedBrightnessBy(0.9)]
                blueColor = [theme.colors.accent.withMultipliedBrightnessBy(1.1), theme.colors.accent.withMultipliedBrightnessBy(0.9)]
            }
            if option.native.generic?.isAuction == true, option.native.generic?.soldOut == nil || preview {
                
                var soon: Bool = false
                if let auctonStarDate = option.native.generic?.auctionStartDate {
                    soon = auctonStarDate > Int32(Date().timeIntervalSince1970)
                }
                badge = .init(
                    text: customText ?? (soon ? strings().starGiftBadgeSoon : strings().starGiftBadgeAuction),
                    colors: customText != nil ? blueColor : goldColor,
                    textColor: theme.colors.underSelectedColor,
                    outline: customText == nil
                )
            } else if option.native.generic?.flags.contains(.requiresPremium) == true, option.native.generic?.soldOut == nil {
                if let remains = option.native.generic?.perUserLimit?.remains {
                    badge = .init(
                        text: strings().giftingStarGiftBadgeRemainingOther(Int(remains)),
                        colors: goldColor,
                        textColor: theme.colors.underSelectedColor,
                        outline: true
                    )
                } else {
                    badge = .init(text: strings().premiumLimitPremium, colors: goldColor, textColor: theme.colors.underSelectedColor, outline: true)
                }
            } else if let availability = option.native.generic?.availability {
                if availability.resale > 0 && option.native.generic?.soldOut != nil {
                    badge = .init(text: strings().giftResale, colors: greenColor, textColor: .white, outline: true)
                } else if availability.remains == 0 {
                    badge = .init(text: strings().giftSoldOut, colors: redColor, textColor: .white, outline: false)
                } else {
                    badge = .init(text: strings().starGiftLimited, colors: blueColor, textColor: theme.colors.underSelectedColor, outline: false)
                }
            } else if let unique = option.native.unique {
                badge = .init(text: customText ?? "#\(unique.number)", colors: option.native.backdropColor ?? blueColor, textColor: theme.colors.underSelectedColor, outline: false)
            } else {
                badge = nil
            }
            
            
            let price: Int64
            let resale: Bool
            let availability = option.native.generic?.availability
            if let availability, availability.remains == 0, availability.resale > 0, let minResaleStars = availability.minResaleStars {
                price = minResaleStars
                resale = true
            } else {
                price = option.stars
                resale = false
            }
            
            return .init(file: option.media, image: nil, colors: [], text: nil, type: preview ? .none : .stars(price, false, resale, false), badge: badge, peer: nil, invisible: false, pinned: false, toggleSelect: nil, limitDatePurchase: option.native.generic?.lockedUntilDate, priceBadge: nil, nativeStarGift: option)
        }
        
        public static func initialize(_ option: StarGift.UniqueGift, context: (any AccountContextProtocol), resale: Bool = false, showNumber: Bool = false) -> Option {
            
            let badge: Option.Badge?
            
            var blueColor: [NSColor] = []
            
            if theme.colors.isDark {
                blueColor = [NSColor(0x142e42), NSColor(0x354f5b)]
            } else {
                blueColor = [theme.colors.accent.withMultipliedBrightnessBy(1.1), theme.colors.accent.withMultipliedBrightnessBy(0.9)]
            }
            
            
            if showNumber {
                badge = .init(text: "#\(option.number)", colors: option.backdrop ?? blueColor, textColor: theme.colors.underSelectedColor, outline: false)
            } else {
                badge = nil
            }
            
            let priceValue = option.resellStars(context)
            
            return .init(file: option.file!, image: nil, colors: [], text: nil, type: option.resellAmounts != nil && showNumber && priceValue != nil ? .stars(priceValue!.amount.value, true, resale, option.resellForTonOnly) : .none, badge: badge, peer: nil, invisible: false, pinned: false, toggleSelect: nil, limitDatePurchase: nil, priceBadge: nil, nativeStarUniqueGift: option)
        }
        
        
        public static func initialize(_ option: ProfileGiftsContext.State.StarGift, context: (any AccountContextProtocol), transfrarable: Bool = false, selected: Bool? = nil) -> Option {
            
            var blueColor: [NSColor] = []
            
            if theme.colors.isDark {
                blueColor = [NSColor(0x142e42), NSColor(0x354f5b)]
            } else {
                blueColor = [theme.colors.accent.withMultipliedBrightnessBy(1.1), theme.colors.accent.withMultipliedBrightnessBy(0.9)]
            }
            
            var priceBadge: TextViewLayout? = nil
            
            let badge: Badge?
            if let resellStars = option.gift.unique?.resellStars(context) {
                badge = .init(text: strings().giftSale, colors: [NSColor(0x74b036), NSColor(0x87d151)], textColor: theme.colors.underSelectedColor, outline: true)
                
                let attr = NSMutableAttributedString()
                attr.append(.initialize(string: "\(clown_space)\(resellStars.amount.value.separatedNumber)", color: .white, font: .normal(.text)))
                attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_mono.file), for: clown)
                
                priceBadge = .init(attr)
                priceBadge?.measure(width: .greatestFiniteMagnitude)
            } else if let availability = option.gift.generic?.availability {
                badge = .init(text: strings().starTransactionAvailabilityOf(1, Int(availability.total).prettyNumber), colors: blueColor, textColor: theme.colors.underSelectedColor, outline: false)
            } else if let unique = option.gift.unique {
                badge = .init(text: "#\(unique.number)", colors: option.gift.backdropColor ?? blueColor, textColor: theme.colors.underSelectedColor, outline: false)
            } else {
                badge = nil
            }
            
            let file: TelegramMediaFile
            switch option.gift {
            case .generic(let gift):
                file = gift.file
            case .unique(let uniqueGift):
                file = uniqueGift.file!
            }            
            return .init(file: file, image: nil, colors: [], text: nil, type: transfrarable ? .price(strings().starNftTransfer) : .none, badge: badge, peer: selected != nil || option.pinnedToTop ? nil : option.fromPeer, invisible: selected != nil ? false : !option.savedToProfile, pinned: selected != nil ? false : option.pinnedToTop, toggleSelect: selected, limitDatePurchase: nil, priceBadge: selected != nil ? nil : priceBadge, nativeProfileGift: option)
        }
        
        public var height: CGFloat {
            var height: CGFloat = 0
            switch type {
            case .price:
                height = nativeProfileGift != nil ? 135 : 160
            case .stars:
                height = 135
            case .none:
                height = 130
            }
            if let starsPrice {
                height += starsPrice.layoutSize.height + 10
            }
            return height
        }
        public init(file: TelegramMediaFile?, image: CGImage?, colors: [LottieColor], text: NSAttributedString?, type: TypeValue, badge: Badge?, peer: EnginePeer?, invisible: Bool, pinned: Bool, toggleSelect: Bool?, limitDatePurchase: Int32?, priceBadge: TextViewLayout?, starsPrice: TextViewLayout? = nil, nativePayment: PremiumPaymentOption? = nil, nativeStarGift: PeerStarGift? = nil, nativeProfileGift: ProfileGiftsContext.State.StarGift? = nil, nativeStarUniqueGift: StarGift.UniqueGift? = nil) {
            self.file = file
            self.image = image
            self.colors = colors
            self.text = text
            self.type = type
            self.badge = badge
            self.peer = peer
            self.invisible = invisible
            self.pinned = pinned
            self.toggleSelect = toggleSelect
            self.limitDatePurchase = limitDatePurchase
            self.priceBadge = priceBadge
            self.starsPrice = starsPrice
            self.nativePayment = nativePayment
            self.nativeStarGift = nativeStarGift
            self.nativeProfileGift = nativeProfileGift
            self.nativeStarUniqueGift = nativeStarUniqueGift
        }
    }
    
    fileprivate let options: [Option]
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let perRowCount: Int
    fileprivate let fitToSize: Bool
    fileprivate let selected: StarGift?
    fileprivate let surfaceBackgroundColor: NSColor?

    fileprivate let callback:(Option, (() -> NSView?)?)->Void
    private let _contextMenu:(Option)->[ContextMenuItem]
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), options: [Option], perRowCount: Int = 3, fitToSize: Bool = false, insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20), viewType: GeneralViewType = .legacy, surfaceBackgroundColor: NSColor? = nil, callback:@escaping(Option, (() -> NSView?)?)->Void, selected: StarGift? = nil, contextMenu:@escaping(Option)->[ContextMenuItem] = { _ in return [] }) {
        self.options = options
        self.context = context
        self.callback = callback
        self.perRowCount = perRowCount
        self.fitToSize = fitToSize
        self.selected = selected
        self.surfaceBackgroundColor = surfaceBackgroundColor
        self._contextMenu = contextMenu
        assert(!options.isEmpty)
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: insets)
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        
        let itemSize: NSSize
        if self.fitToSize, self.options.count == 1 {
            itemSize = NSMakeSize(width - self.inset.right - self.inset.left, self.height)
        } else {
            let insets = self.inset
            let count = self.fitToSize ? CGFloat(self.options.count) : CGFloat(self.perRowCount)
            let space = self.width - insets.left - insets.right - (10 * CGFloat(count - 1))
            itemSize = NSMakeSize(floorToScreenPixels(space / count), self.height)
        }
        var x: CGFloat = self.inset.left

        for (i, _) in options.enumerated() {
            if location.x > x && location.x < (x + itemSize.width + 10) {
                return .single(_contextMenu(options[i]))
            }
            x += itemSize.width + 10
        }
        
        
        return .single([])
    }
    
    public override var hasBorder: Bool {
        return false
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonGift
    }
    
    public override func viewClass() -> AnyClass {
        return GiftOptionsRowView.self
    }
    
    public override var height: CGFloat {
        return options[0].height
    }
}

public final class GiftOptionsRowView:  GeneralContainableRowView {
    
    
    public class OptionView : Control, MorphHoldObserving {
        
        
        public final class InvisibleView : VisualEffect {
            private let imageView = ImageView()
            public override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(imageView)
                imageView.image = TelegramThemeHooks.shared.image(.menuEyeSlash).precomposed(NSColor.white)
                imageView.isAccessibilityDecorative = true
                imageView.sizeToFit()
                layer?.cornerRadius = frameRect.height / 2
                layer?.masksToBounds = true
                if #available(macOS 10.15, *) {
                    layer?.cornerCurve = .continuous
                }
                self.bgColor = NSColor.blackTransparent.withAlphaComponent(0.1)
            }
            
            public required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            public override func layout() {
                super.layout()
                imageView.center()
            }
        }
        
        public final class PriceBadgeView : VisualEffect {
            private let textView = InteractiveTextView()
            public override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(textView)
                textView.isEventLess = true
                textView.userInteractionEnabled = false
                self.bgColor = NSColor.black.withAlphaComponent(0.05)
            }
            
            public required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            public func update(_ layout: TextViewLayout, context: (any AccountContextProtocol)) {
                self.textView.set(text: layout, context: context)
                
                setFrameSize(NSMakeSize(layout.layoutSize.width + 10, layout.layoutSize.height + 6))
                
                self.layer?.cornerRadius = self.frame.height / 2
            }
            
            public override func layout() {
                super.layout()
                textView.center()
            }
        }
        
        private let sticker = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 80, 80))
        private var imageView: ImageView?
        private var textView: TextView?
        private var badgeView: ImageView?
        private var badgeOutlineView: ImageView?
        private var priceView: PriceView?
        private var starPriceView: StarPriceView?
        private var avatarView: AvatarControl?
        private var invisibleView: InvisibleView?
        private var uniqueBackground: UniqueGiftBackgroundView?
        private var uniqueBackgroundContent: UniqueGiftBackgroundContent?
        private var uniqueBackgroundContext: (any AccountContextProtocol)?
        private var selectionView: View?
        private var starsPrice: InteractiveTextView?
        private var pinnedView: ImageView?
        private var priceBadgeView: PriceBadgeView?
        private let surfaceView = SimpleLayer()
        private var premiumSelectView: View?
        private var toggleSelect: SelectingControl?
        private var onlyTonView: OnlyTonView?
        private var limitDatePurchase: ImageView?

        private class PriceView: View {
            private let textView = TextView()
            public required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(textView)
                textView.userInteractionEnabled = false
                textView.isSelectable = false
                textView.isAccessibilityDecorative = true
            }
            
            public required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            public func update(text: TextViewLayout) {
                self.textView.update(text)
                self.setFrameSize(NSMakeSize(text.layoutSize.width + 16, text.layoutSize.height + 10))
                self.layer?.cornerRadius = frame.height / 2
                self.needsLayout = true
            }
            public override func layout() {
                super.layout()
                self.textView.center()
            }
        }
        
        private class OnlyTonView : View {
            private let visual = VisualEffect(frame: NSMakeRect(0, 0, 24, 24))
            private let imageView = ImageView()
            public required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(visual)
                addSubview(imageView)
                
                imageView.image = TelegramThemeHooks.shared.image(.iconTonCurrency).precomposed(.white)
                imageView.isAccessibilityDecorative = true
                imageView.sizeToFit()
                self.layer?.cornerRadius = 15
                
                needsLayout = true
                
            }
            
            public required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            
            public override func layout() {
                super.layout()
                self.visual.frame = bounds
                self.imageView.center()
            }
            
        }
        
        private class StarPriceView: View {
            private let textView = InteractiveTextView()
            public let effect = StarsButtonEffectLayer()
            public required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(textView)
                self.layer?.addSublayer(effect)
                textView.userInteractionEnabled = false
                self.layer?.masksToBounds = false
            }
            
            public required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            public func update(text: TextViewLayout, context: (any AccountContextProtocol)) {
                self.textView.set(text: text, context: context)
                self.setFrameSize(NSMakeSize(text.layoutSize.width + 16, text.layoutSize.height + 10))
                self.layer?.cornerRadius = frame.height / 2
                self.layer?.masksToBounds = false
                self.needsLayout = true
                
                
                let rect = self.bounds.insetBy(dx: -5, dy: -5)
                effect.frame = rect
                effect.update(size: rect.size)
            }
            public override func layout() {
                super.layout()
                self.textView.center()
            }
        }
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            surfaceView.anchorPoint = .zero
            surfaceView.masksToBounds = true
            if #available(macOS 10.15, *) {
                surfaceView.cornerCurve = .continuous
            }
            layer?.insertSublayer(surfaceView, at: 0)
            addSubview(sticker)
            
                        
            (sticker as? View)?.userInteractionEnabled = false

            surfaceView.cornerRadius = giftTileCornerRadius
            
            scaleOnClick = true
            set(handler: { _ in
                
            }, for: .Click)
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public var option: GiftOptionsRowItem.Option?
        private var isChosen: Bool = false

        public override var accessibilityDefaultLabel: String? {
            return option?.accessibilityTitle
        }

        public override func accessibilityValue() -> Any? {
            return option?.accessibilityStatus(selected: isChosen)
        }
        
        public func morphHoldDidChange(_ isHeld: Bool) {
            (self.sticker as? StarsStickerView)?.overridePlayValue = isHeld ? true : nil
        }
        
        public func set(option: GiftOptionsRowItem.Option, context: (any AccountContextProtocol), selected: Bool, surfaceBackgroundColor: NSColor = theme.colors.background, animated: Bool, callback:@escaping(GiftOptionsRowItem.Option, (() -> NSView?)?)->Void) {

            // The morph hides this cell while it stands in for the opened gift (holdSource). Table/grid
            // reuse can hand a still-hidden cell to a DIFFERENT gift on reload, which would make that gift
            // vanish; whenever the cell takes a different gift, force it visible so it never stays stuck.
            if option.gift?.id != self.option?.gift?.id {
                self.isHidden = false
            }
            self.option = option
            self.isChosen = selected
            self.surfaceView.backgroundColor = surfaceBackgroundColor.cgColor

            self.setSingle(handler: { [weak self] _ in
                callback(option, { [weak self] in self })
            }, for: .Click)
            
            
            
            if let file = option.file {
                (self.sticker as? StarsStickerView)?.updateStarsSticker(file: file, size: self.sticker.frame.size, context: context, colors: [], playback: .previewFrames, animated: false)
            }
            
            self.sticker.isHidden = option.file == nil
            
            if let image = option.image {
                let current: ImageView
                if let view = self.imageView {
                    current = view
                } else {
                    current = ImageView()
                    self.addSubview(current)
                    self.imageView = current
                    current.isEventLess = true
                    current.isAccessibilityDecorative = true
                }
                current.image = image
                current.sizeToFit()
            } else if let view = self.imageView {
                performSubviewRemoval(view, animated: false)
                self.imageView = nil
            }
            
            if let text = option.text {
                let current: TextView
                if let view = self.textView {
                    current = view
                } else {
                    current = TextView()
                    self.addSubview(current)
                    self.textView = current
                    current.userInteractionEnabled = false
                    current.isSelectable = false
                    current.isAccessibilityDecorative = true
                }
                let textLayout = TextViewLayout(text, alignment: .center)
                textLayout.measure(width: .greatestFiniteMagnitude)
                current.update(textLayout)
            } else if let view = self.textView {
                performSubviewRemoval(view, animated: false)
                self.textView = nil
            }
            
            if let peer = option.peer {
                let current: AvatarControl
                if let view = self.avatarView {
                    current = view
                } else {
                    current = AvatarControl(font: .avatar(8))
                    current.setFrameSize(20, 20)
                    self.addSubview(current)
                    self.avatarView = current
                    current.userInteractionEnabled = false
                }
                current.setPeer(account: context.account, peer: peer._asPeer())
            } else if let avatarView {
                performSubviewRemoval(avatarView, animated: false)
                self.avatarView = nil
            }
            
            switch option.type {
            case .price(let string):
                
                if let view = self.starPriceView {
                    performSubviewRemoval(view, animated: false)
                    self.starPriceView = nil
                }
                
                
                let current: PriceView
                if let view = self.priceView {
                    current = view
                } else {
                    current = PriceView(frame: .zero)
                    self.addSubview(current)
                    self.priceView = current
                }
                let priceLayout = TextViewLayout(.initialize(string: string, color: option.gift?.unique != nil ? .white : theme.colors.accent, font: .medium(.text)))
                priceLayout.measure(width: .greatestFiniteMagnitude)
                current.backgroundColor = option.gift?.unique != nil ? NSColor.white.withAlphaComponent(0.2) : theme.colors.accent.withAlphaComponent(0.2)
                current.update(text: priceLayout)
                
            case let .stars(int64, plain, addPlus, _):
                if let view = self.priceView {
                    performSubviewRemoval(view, animated: false)
                    self.priceView = nil
                }
                
                let current: StarPriceView
                if let view = self.starPriceView {
                    current = view
                } else {
                    current = StarPriceView(frame: .zero)
                    self.addSubview(current)
                    self.starPriceView = current
                }
                
                if let view = self.onlyTonView {
                    performSubviewRemoval(view, animated: false)
                    self.onlyTonView = nil
                }
                
                current.effect.isHidden = plain
                
                let attr = NSMutableAttributedString()
                if option.nativeStarGift?.native.generic?.isAuction == true, option.nativeStarGift?.native.generic?.soldOut == nil {
                    attr.append(
                        string: strings().starGiftOptionJoin,
                        color: plain ? NSColor.white : GOLD,
                        font: .medium(.text)
                    )
                } else {
                    attr.append(string: "\(clown_space)\(int64)" + (addPlus ? "+" : ""), color: plain ? NSColor.white : GOLD, font: .medium(.text))
                    attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file, color: nil), for: clown)
                }
                let priceLayout = TextViewLayout(attr)
                priceLayout.measure(width: .greatestFiniteMagnitude)
                current.backgroundColor = plain ? NSColor.white.withAlphaComponent(0.2) : GOLD.withAlphaComponent(0.2)
                current.update(text: priceLayout, context: context)
            case .none:
                if let view = self.priceView {
                    performSubviewRemoval(view, animated: false)
                    self.priceView = nil
                }
                if let view = self.starPriceView {
                    performSubviewRemoval(view, animated: false)
                    self.starPriceView = nil
                }
                if let view = self.onlyTonView {
                    performSubviewRemoval(view, animated: false)
                    self.onlyTonView = nil
                }
            }
            
            if let badge = option.badge {
                let current: ImageView
                if let view = self.badgeView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    addSubview(current, positioned: .above, relativeTo: self.sticker)
                    self.badgeView = current
                }
                                
                let ribbon = generateGradientTintedImage(image: TelegramThemeHooks.shared.image(.giftRibbon).precomposed(), colors: badge.colors, direction: .diagonal)!


                current.image = generateGiftBadgeBackground(background: ribbon, text: badge.text, textColor: badge.textColor)

                current.sizeToFit()
            } else if let view = badgeView {
                performSubviewRemoval(view, animated: false)
                self.badgeView = nil
            }
            
            

            
            if option.invisible {
                let current: InvisibleView
                if let view = self.invisibleView {
                    current = view
                } else {
                    current = InvisibleView(frame: NSMakeRect(0, 0, 30, 30))
                    addSubview(current)
                    self.invisibleView = current
                }
            } else if let view = self.invisibleView {
                performSubviewRemoval(view, animated: false)
                self.invisibleView = nil
            }
            
            
            if let uniqueGift = option.gift?.unique, let content = UniqueGiftBackgroundContent(gift: uniqueGift) {
                if self.uniqueBackground == nil {
                    let current = UniqueGiftBackgroundView(frame: bounds.insetBy(dx: 1, dy: 1))
                    self.addSubview(current, positioned: .below, relativeTo: sticker)
                    self.uniqueBackground = current
                }
                self.uniqueBackgroundContent = content
                self.uniqueBackgroundContext = context
            } else {
                if let view = self.uniqueBackground {
                    performSubviewRemoval(view, animated: false)
                    self.uniqueBackground = nil
                }
                self.uniqueBackgroundContent = nil
                self.uniqueBackgroundContext = nil
            }
            
            if option.pinned {
                let current: ImageView
                if let view = self.pinnedView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    self.pinnedView = current
                    addSubview(current)
                }
                current.image = TelegramThemeHooks.shared.image(.iconChatListPinned).precomposed(.white)
                current.sizeToFit()
            } else if let view = self.pinnedView {
                performSubviewRemoval(view, animated: animated)
                self.pinnedView = nil
            }
            
            
            if let starsPrice = option.starsPrice {
                let current: InteractiveTextView
                if let view = self.starsPrice {
                    current = view
                } else {
                    current = InteractiveTextView()
                    current.userInteractionEnabled = false
                    self.starsPrice = current
                    addSubview(current)
                }
                current.set(text: starsPrice, context: context)
            } else if let view = self.starsPrice {
                performSubviewRemoval(view, animated: animated)
                self.starsPrice = nil
            }
            
            if let priceBadge = option.priceBadge {
                let current: PriceBadgeView
                if let view = self.priceBadgeView {
                    current = view
                } else {
                    current = PriceBadgeView(frame: .zero)
                    self.priceBadgeView = current
                    addSubview(current)
                }
                
                current.update(priceBadge, context: context)
            } else if let view = self.priceBadgeView {
                performSubviewRemoval(view, animated: animated)
                self.priceBadgeView = nil
            }
            
            if option.nativeProfileGift?.gift.unique?.resellForTonOnly == true || option.nativeStarUniqueGift?.resellForTonOnly == true {
                let current: OnlyTonView
                if let view = self.onlyTonView {
                    current = view
                } else {
                    current = OnlyTonView(frame: NSMakeRect(4, 4, 30, 30))
                    self.onlyTonView = current
                    addSubview(current)
                }
            } else if let view = self.onlyTonView {
                performSubviewRemoval(view, animated: animated)
                self.onlyTonView = nil
            }
            
            if option.limitDatePurchase != nil {
                let current: ImageView
                if let view = self.limitDatePurchase {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    self.limitDatePurchase = current
                    addSubview(current)
                }
                current.image = TelegramThemeHooks.shared.image(.iconStarGiftLock).precomposed(theme.colors.redUI)
                current.sizeToFit()
            } else if let view = self.limitDatePurchase {
                performSubviewRemoval(view, animated: animated)
                self.limitDatePurchase = nil
            }
            
            if selected {
                let current: View
                if let view = selectionView {
                    current = view
                } else {
                    current = View()
                    addSubview(current)
                    self.selectionView = current
                    current.layer?.cornerRadius = giftTileCornerRadius - 2
                }
                current.layer?.borderColor = theme.colors.background.cgColor
                current.layer?.borderWidth = 3
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            } else if let selectionView {
                performSubviewRemoval(selectionView, animated: animated)
                self.selectionView = nil
            }
            
            let premiumSelection = (option.gift?.generic?.flags.contains(.requiresPremium) == true || option.gift?.generic?.isAuction == true) && option.nativeStarGift != nil && option.badge != nil && option.nativeStarGift?.native.generic?.soldOut == nil
            
            
            if premiumSelection, let badge = option.badge {
                let current: View
                if let view = premiumSelectView {
                    current = view
                } else {
                    current = View()
                    addSubview(current, positioned: .below, relativeTo: badgeView)
                    self.premiumSelectView = current
                    current.layer?.cornerRadius = giftTileCornerRadius
                }
                current.layer?.borderColor = badge.colors[0].cgColor
                current.layer?.borderWidth = 1
                
            } else if let premiumSelectView {
                performSubviewRemoval(premiumSelectView, animated: animated)
                self.premiumSelectView = nil
            }
            
            
            if let badge = option.badge, badge.outline {
                let current: ImageView
                if let view = self.badgeOutlineView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    addSubview(current, positioned: .below, relativeTo: self.badgeView)
                    self.badgeOutlineView = current
                }
                                
                let ribbon = ribbonOutlineImage(color: theme.colors.listBackground)
                
                current.image = ribbon
                
                current.sizeToFit()
            } else if let view = badgeOutlineView {
                performSubviewRemoval(view, animated: false)
                self.badgeOutlineView = nil
            }
            
            if let toggleSelect = option.toggleSelect {
                
                let unselected: CGImage = theme.icons.chatToggleUnselected
                let selected: CGImage = theme.icons.chatToggleSelected

                let current: SelectingControl
                if let view = self.toggleSelect {
                    current = view
                } else {
                    current = SelectingControl(unselectedImage: unselected, selectedImage: selected)
                    current.isAccessibilityDecorative = true
                    current.scaleOnClick = true
                    addSubview(current)
                    self.toggleSelect = current
                }
                current.update(unselectedImage: unselected, selectedImage: selected, selected: toggleSelect, animated: animated)
                current.userInteractionEnabled = false
            } else if let view = self.toggleSelect {
                performSubviewRemoval(view, animated: animated)
                self.toggleSelect = nil
            }
            
            needsLayout = true
        }
        
        public override func layout() {
            super.layout()
            if starsPrice != nil || starPriceView != nil || priceView != nil {
                sticker.centerX(y: 5)
            } else {
                sticker.center()
            }
            textView?.centerX(y: sticker.frame.maxY + 5)
            if let badgeView {
                badgeView.setFrameOrigin(frame.width - badgeView.frame.width, 0)
            }
            
            if let toggleSelect {
                toggleSelect.setFrameOrigin(NSMakePoint(5, 5))
            }
            
            if let badgeOutlineView {
                badgeOutlineView.setFrameOrigin(frame.width - badgeOutlineView.frame.width + 4.5, -2)
            }
            
            var offset: CGFloat = 0
            if let starsPrice {
                starsPrice.centerX(y: frame.height - starsPrice.frame.height - 10)
                offset += starsPrice.frame.height + 10
            }
            
            if let priceView {
                priceView.centerX(y: frame.height - priceView.frame.height - 10 - offset)
            }
            if let starPriceView {
                starPriceView.centerX(y: frame.height - starPriceView.frame.height - 10 - offset)
            }
            if let avatarView {
                avatarView.setFrameOrigin(NSMakePoint(4, 4))
            }
            if let onlyTonView {
                onlyTonView.setFrameOrigin(NSMakePoint(4, 4))
            }
            if let limitDatePurchase {
                limitDatePurchase.setFrameOrigin(NSMakePoint(4, 4))
            }
            if let uniqueBackground, let content = uniqueBackgroundContent, let context = uniqueBackgroundContext {
                uniqueBackground.frame = bounds.insetBy(dx: 1, dy: 1)
                uniqueBackground.update(context: context, content: content, style: .item(giftCenterY: sticker.frame.midY - uniqueBackground.frame.minY, cornerRadius: giftTileCornerRadius))
            }
            
            surfaceView.frame = bounds.insetBy(dx: 1, dy: 1)
            
            if let pinnedView {
                pinnedView.setFrameOrigin(NSMakePoint(4, 4))
            }
           
            invisibleView?.center()
            
            if let selectionView {
                selectionView.frame = bounds.insetBy(dx: 3, dy: 3)
            }
            if let premiumSelectView {
                premiumSelectView.frame = bounds.insetBy(dx: 1, dy: 1)
            }
            
            if let imageView {
                imageView.centerX(y: 20)
                if let textView {
                    textView.centerX(y: frame.height - textView.frame.height - 20)
                }
            } else {
                textView?.centerX(y: sticker.frame.maxY + 5)
            }
            
            
            if let priceBadgeView {
                priceBadgeView.centerX(y: frame.height - priceBadgeView.frame.height - 10)
            }
        }
    }
    
    private let content = View()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(content)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? GiftOptionsRowItem else {
            return
        }
                
        
        let itemSize: NSSize
        if item.fitToSize, item.options.count == 1 {
            itemSize = NSMakeSize(content.frame.width - item.inset.right - item.inset.left, content.frame.height)
        } else {
            let insets = item.inset
            let count = item.fitToSize ? CGFloat(item.options.count) : 3
            let space = content.frame.width - insets.left - insets.right - (10 * CGFloat(count - 1))
            itemSize = NSMakeSize(floor(space / count), content.frame.height)
        }

        while self.content.subviews.count > item.options.count {
            self.content.subviews.last?.removeFromSuperview()
        }
        while self.content.subviews.count < item.options.count {
            self.content.addSubview(OptionView(frame: itemSize.bounds))
        }
        
        layout()
        
        for (i, subview) in content.subviews.enumerated() {
            let view = subview as? OptionView
            if view?.option?.gift?.id != item.options[i].gift?.id {
                if animated {
                    view?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.35)
                }
            }
            view?.set(option: item.options[i], context: item.context, selected: item.options[i].gift == item.selected && item.selected != nil, surfaceBackgroundColor: item.surfaceBackgroundColor ?? theme.colors.background, animated: animated, callback: item.callback)
        }
        
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? GiftOptionsRowItem else {
            return .clear
        }
        return item.viewType == .legacy ? .clear : super.backdorColor
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? GiftOptionsRowItem else {
            return
        }
        
        content.frame = containerView.bounds.insetBy(dx: 0, dy: 0)
        
        let itemSize: NSSize
        if item.fitToSize, item.options.count == 1 {
            itemSize = NSMakeSize(content.frame.width - item.inset.right - item.inset.left, content.frame.height)
        } else {
            let insets = item.inset
            let count = item.fitToSize ? CGFloat(item.options.count) : CGFloat(item.perRowCount)
            let space = content.frame.width - insets.left - insets.right - (10 * CGFloat(count - 1))
            itemSize = NSMakeSize(floor(space / count), content.frame.height)
        }
        var x: CGFloat = item.inset.left

        for (_, subview) in content.subviews.enumerated() {
            let view = subview as? OptionView
            view?.setFrameSize(itemSize)
            subview.setFrameOrigin(x, 0)
            x += subview.frame.width + 10
        }
    }
}
