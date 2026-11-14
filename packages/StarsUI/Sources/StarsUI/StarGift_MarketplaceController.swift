import Cocoa
import Foundation
import TGUIKit
import UniqueGiftBackground
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

private final class EmptyRowItem: GeneralRowItem {
    fileprivate let arguments: Arguments
    fileprivate let titleLayout: TextViewLayout
    fileprivate let clearLayout: TextViewLayout
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, arguments: Arguments) {
        self.arguments = arguments
        self.titleLayout = .init(.initialize(string: strings().giftMarketplaceEmptyFilters, color: theme.colors.text, font: .normal(.title)), alignment: .center)
        self.titleLayout.measure(width: .greatestFiniteMagnitude)
        
        self.clearLayout = .init(.initialize(string: strings().giftMarketplaceEmptyFiltersClear, color: theme.colors.accent, font: .normal(.text)), alignment: .center)
        self.clearLayout.measure(width: .greatestFiniteMagnitude)

        super.init(initialSize, stableId: stableId)
    }
    
    public override var height: CGFloat {
        return 270
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return [NSAccessibilityCustomAction(name: clearLayout.attributedString.string, handler: { [weak self] in
            self?.arguments.clearFilters()
            return true
        })]
    }
    
    public override func viewClass() -> AnyClass {
        return EmptyRowView.self
    }
}

fileprivate class EmptyRowView : GeneralRowView {
    fileprivate let titleView = TextView()
    fileprivate let clearView = TextView()
    fileprivate let animationView = StarsHooks.shared.makeStickerView(.zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(clearView)
        addSubview(animationView)
        
        titleView.isSelectable = false
        clearView.isSelectable = false
        
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? EmptyRowItem else {
            return
        }
        
        titleView.update(item.titleLayout)
        clearView.update(item.clearLayout)
        
        (animationView as? StarsStickerView)?.updateStarsSticker(file: LocalAnimatedSticker.duck_empty.file, size: NSMakeSize(100, 100), context: item.arguments.context, colors: [], playback: .standard, animated: animated)
        
        clearView.setSingle(handler: { [weak item] _ in
            item?.arguments.clearFilters()
        }, for: .Click)
    }
    
    public override func layout() {
        super.layout()
        
        animationView.centerX(y: 30)
        titleView.centerX(y: animationView.frame.maxY + 10)
        clearView.centerX(y: titleView.frame.maxY + 5)
    }
}


private extension StarGift.UniqueGift.Attribute {
    var resaleAttr: ResaleGiftsContext.Attribute {
        switch self {
        case let .model(_, file, _, _):
            return .model(file.fileId.id)
        case let .backdrop(_, id, _, _, _, _, _):
            return .backdrop(id)
        case let .pattern(_, file, _):
            return .pattern(file.fileId.id)
        default:
            fatalError()
        }
    }
}


private class AttributeMenuItem : ContextMenuItem {
    fileprivate let attribute: StarGift.UniqueGift.Attribute
    fileprivate let arguments: Arguments
    public init(attribute: StarGift.UniqueGift.Attribute, count: Int32, selected: Bool, arguments: Arguments) {
        self.attribute = attribute
        self.arguments = arguments
        super.init(attribute.name + " (\(count))", handler: {
            arguments.toggleAttribute(attribute.resaleAttr)
        }, state: selected ? .on : nil)
    }
    
    public override func rowItem(presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction) -> TableRowItem {
        return AttributeMenuRowItem(self, presentation: presentation, interaction: interaction)
    }
    
    public required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class AttributeMenuRowItem : AppMenuRowItem {
    private let disposable = MetaDisposable()
    public init(_ item: AttributeMenuItem, presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction) {
        super.init(.zero, item: item, interaction: interaction, presentation: presentation)
        
        let image = generateImage(NSMakeSize(imageSize, imageSize), rotatedContext: { size, ctx in
            ctx.clear(size.bounds)
            ctx.setFillColor(NSColor.clear.cgColor)
            ctx.fillEllipse(in: size.bounds)
        })!
        item.image = NSImage(cgImage: image, size: NSMakeSize(imageSize, imageSize))
        
        switch item.attribute {
        case let .backdrop(_, _, innerColor, outerColor, _, _, _):
            let image = generateImage(NSMakeSize(imageSize, imageSize), rotatedContext: { size, ctx in
                ctx.clear(size.bounds)
                ctx.round(size, size.height / 2)

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let colors = [NSColor(UInt32(innerColor)).cgColor, NSColor(UInt32(outerColor)).cgColor] as CFArray
                let locations: [CGFloat] = [0.0, 1.0]

                if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2

                    ctx.drawRadialGradient(
                        gradient,
                        startCenter: center, startRadius: 0,
                        endCenter: center, endRadius: radius,
                        options: [.drawsAfterEndLocation]
                    )
                }
            })!
            item.image = NSImage(cgImage: image, size: NSMakeSize(imageSize, imageSize))
        case let .model(_, file, _, _), let .pattern(_, file, _):
            
            let isPattern: Bool
            switch item.attribute {
            case .pattern:
                isPattern = true
            default:
                isPattern = false
            }
            
            let size = NSMakeSize(imageSize, imageSize)
            
            let aspectSize = file.dimensions?.size.aspectFitted(size) ?? size
            
            let signal = chatMessageAnimatedSticker(postbox: item.arguments.context.account.postbox, file: .standalone(media: file), small: false, scale: System.backingScale, size: aspectSize, fetched: true, thumbAtFrame: 0, isVideo: file.fileName == "webm-preview" || file.isVideoSticker)

            let arguments = TransformImageArguments(corners: .init(), imageSize: size, boundingSize: aspectSize, intrinsicInsets: .init(), emptyColor: isPattern ? .fill(theme.colors.text) : nil)
            
            let result = signal |> map { data -> TransformImageResult in
                let context = data.execute(arguments, data.data)
                let image = context?.generateImage()
                return TransformImageResult(image, context?.isHighQuality ?? false)
            } |> deliverOnMainQueue
            
            disposable.set(result.start(next: { [weak item] result in
                item?.image = result.image.flatMap({
                    NSImage(cgImage: $0, size: size)
                })
            }))
        default:
            break
            
        }
    }
    
    deinit {
        disposable.dispose()
    }
    
    public var genericItem: AttributeMenuItem {
        return self.item as! AttributeMenuItem
    }
    
    public override func viewClass() -> AnyClass {
        return AttributeMenuRowView.self
    }
}

private final class AttributeMenuRowView : AppMenuRowView {
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private final class HeaderItem : GeneralRowItem {
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let balanceLayout: TextViewLayout
    
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let arguments: Arguments
    
    public struct AttributeItem {
        public let text: TextViewLayout
        public let image: CGImage?
        public let attribute: State.Attribute
        public init(attribute: State.Attribute, resaleState: ResaleGiftsContext.State?) {
            self.attribute = attribute
            self.image = attribute.image(resaleState)
            self.text = .init(.initialize(string: attribute.string(resaleState), color: theme.colors.darkGrayText, font: .medium(.text)))
            self.text.measure(width: .greatestFiniteMagnitude)
        }
    }
    
    public let items: [AttributeItem]
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, context: (any AccountContextProtocol), arguments: Arguments) {
        
        self.context = context
        self.arguments = arguments
        
        let balanceAttr = NSMutableAttributedString()
        balanceAttr.append(string: strings().starPurchaseBalance("\(clown_space)\(state.myBalance)"), color: theme.colors.text, font: .normal(.text))
        balanceAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file, playPolicy: .onceEnd), for: clown)
        
        self.balanceLayout = .init(balanceAttr, alignment: .right)

        self.headerLayout = .init(.initialize(string: state.gift.title ?? "-", color: theme.colors.text, font: .normal(.title)))
        self.infoLayout = .init(.initialize(string: strings().starMarketplaceResaleAvailableOther(Int(state.count)), color: theme.colors.grayText, font: .normal(.small)))
        
        self.items = State.Attribute.all.map { .init(attribute: $0, resaleState: state.resaleState) }

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
        return 105
    }

    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        let balance = balanceLayout.attributedString.string.replacingOccurrences(of: clown, with: "")
        return [infoLayout.attributedString.string, balance].joined(separator: ", ")
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
}

private class HeaderItemView: GeneralRowView {
    private let top_Container = View()
    private let bottom_Container = HorizontalScrollView(frame: .zero)
    private let headerView = TextView()
    private let statusView = TextView()
    private let balanceView = InteractiveTextView()
    private let dismiss = ImageButton()
    
    private let documentView = View()
    
    private let separatorView = View()
    
    private class AttributeItemView : Control {
        private let textView = TextView()
        private let imageView = ImageView()
        private var leftIconView: ImageView?
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            addSubview(imageView)
            
            scaleOnClick = true
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            textView.isAccessibilityDecorative = true
            imageView.isAccessibilityDecorative = true
            
            
            imageView.image = TelegramThemeHooks.shared.image(.iconAffiliateExpand).precomposed(theme.colors.darkGrayText)
            imageView.sizeToFit()
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(item: HeaderItem.AttributeItem, arguments: Arguments, animated: Bool) {
            self.textView.update(item.text)
            self.setAccessibilityLabel(item.text.attributedString.string)
            
            
            self.contextMenu = {
                let menu = ContextMenu()
                menu.items = arguments.getMenuItems(item.attribute)
                return menu
            }
            
            if let image = item.image {
                let current: ImageView
                if let view = self.leftIconView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    addSubview(current)
                    self.leftIconView = current
                }
                current.image = image
                current.sizeToFit()
            } else if let view = self.leftIconView {
                performSubviewRemoval(view, animated: animated)
                self.leftIconView = nil
            }
            
            self.setFrameSize(NSMakeSize((leftIconView != nil ? 14 : 0) + item.text.layoutSize.width + imageView.frame.width + 21, 30))
            self.backgroundColor = theme.colors.grayForeground
            self.layer?.cornerRadius = 15

        }
        
        public override func layout() {
            super.layout()
            
            var offset: CGFloat = 10
            if let leftIconView {
                leftIconView.centerY(x: 5)
                offset = leftIconView.frame.maxX + 5
            }
            
            self.textView.centerY(x: offset)
            self.imageView.centerY(x: self.textView.frame.maxX + 3)
            
            
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(top_Container)
        addSubview(bottom_Container)
        
        
        top_Container.addSubview(dismiss)
        
        top_Container.layer?.masksToBounds = false
        
        dismiss.scaleOnClick = true
        dismiss.autohighlight = false
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
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
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        while documentView.subviews.count > item.items.count {
            documentView.subviews.last?.removeFromSuperview()
        }
        
        while documentView.subviews.count < item.items.count {
            documentView.addSubview(AttributeItemView(frame: .zero))
        }
        
        var x: CGFloat = 10
        for (i, attr) in item.items.enumerated() {
            let view = documentView.subviews[i] as! AttributeItemView
            view.set(item: attr, arguments: item.arguments, animated: animated)
            view.centerY(x: x)
            x += view.frame.width + 10
        }
        
        documentView.frame = NSMakeRect(0, 0, x - 10, 30)
        bottom_Container.documentView = documentView

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
        bottom_Container.frame = NSMakeRect(0, frame.height - 50, frame.width, 30)
        
        headerView.centerX(y: 9)
        statusView.centerX(y: top_Container.frame.height - 9 - statusView.frame.height)
        
        balanceView.centerY(x: top_Container.frame.width - balanceView.frame.width - 10)
        
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
        
        var x: CGFloat = 10
        for view in documentView.subviews {
            view.centerY(x: x)
            x += view.frame.width + 5
        }
        
        separatorView.frame = NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize)
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss:()->Void
    public let getMenuItems:(State.Attribute)->[ContextMenuItem]
    public let toggleAttribute:(ResaleGiftsContext.Attribute)->Void
    public let selectAll:(ResaleGiftsContext.Attribute)->Void
    public let open:(StarGift.UniqueGift, (() -> NSView?)?)->Void
    public let clearFilters:()->Void
    public let selectGift:((ProfileGiftsContext.State.StarGift)->Void)?
    public init(context: (any AccountContextProtocol), dismiss:@escaping()->Void, getMenuItems:@escaping(State.Attribute)->[ContextMenuItem], toggleAttribute:@escaping(ResaleGiftsContext.Attribute)->Void,
         selectAll:@escaping(ResaleGiftsContext.Attribute)->Void,
         open:@escaping(StarGift.UniqueGift, (() -> NSView?)?)->Void,
         clearFilters:@escaping()->Void,
         selectGift:((ProfileGiftsContext.State.StarGift)->Void)? = nil) {
        self.context = context
        self.dismiss = dismiss
        self.getMenuItems = getMenuItems
        self.toggleAttribute = toggleAttribute
        self.selectAll = selectAll
        self.open = open
        self.clearFilters = clearFilters
        self.selectGift = selectGift
    }
}

private struct State : Equatable {

    public enum Attribute {
        case sort
        case model
        case backdrop
        case symbol

        public func image(_ state: ResaleGiftsContext.State?) -> CGImage? {
            switch self {
            case .sort:
                switch state?.sorting {
                case .date:
                    return TelegramThemeHooks.shared.image(.menuCalendarUp).precomposed(theme.colors.darkGrayText)
                case .value:
                    return TelegramThemeHooks.shared.image(.menuCashUp).precomposed(theme.colors.darkGrayText)
                case .number:
                    return TelegramThemeHooks.shared.image(.menuHashtagUp).precomposed(theme.colors.darkGrayText)
                case .none:
                    return nil
                }
            default:
                return nil
            }
        }

        public func string(_ state: ResaleGiftsContext.State?) -> String {
            switch self {
            case .sort:
                switch state?.sorting {
                case .date:
                    return strings().giftMarketplaceAttrDate
                case .value:
                    return strings().giftMarketplaceAttrPrice
                case .number:
                    return strings().giftMarketplaceAttrNumber
                case .none:
                    return strings().giftMarketplaceAttrDate
                }
            case .model:
                let attrs = state?.filterAttributes.filter({
                    switch $0 {
                    case .model:
                        return true
                    default:
                        return false
                    }
                }).count ?? 0
                return strings().giftMarketplaceAttrModelOther(attrs)

            case .backdrop:
                let attrs = state?.filterAttributes.filter({
                    switch $0 {
                    case .backdrop:
                        return true
                    default:
                        return false
                    }
                }).count ?? 0
                return strings().giftMarketplaceAttrBackdropOther(attrs)
            case .symbol:
                let attrs = state?.filterAttributes.filter({
                    switch $0 {
                    case .pattern:
                        return true
                    default:
                        return false
                    }
                }).count ?? 0
                return strings().giftMarketplaceAttrSymbolOther(attrs)
            }
        }

        public static var all: [Attribute] {
            return [.sort, .model, .backdrop, .symbol]
        }
    }

    public var gift: StarGift.Gift

    public var starsState: StarsContext.State?
    public var myBalance: Int64 {
        return starsState?.balance.value ?? 0
    }

    public var count: Int64 {
        return self.resaleState?.count.flatMap(Int64.init) ?? self.gift.availability?.resale ?? 0
    }

    public var resaleState: ResaleGiftsContext.State?

    public var craftGifts: [ProfileGiftsContext.State.StarGift] = []
    public var isCraftMode: Bool = false

}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_loading = InputDataIdentifier("_id_loading")
private let _id_empty = InputDataIdentifier("_id_empty")
private let _id_filter_row = InputDataIdentifier("_id_filter_row")
private func _id_stars_gifts(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_stars_gifts_\(index)")
}
private func _id_craft_gifts(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_craft_gifts_\(index)")
}
private let _id_your_gifts_header = InputDataIdentifier("_id_your_gifts_header")
private let _id_resale_header = InputDataIdentifier("_id_resale_header")

private final class SectionHeaderItem: GeneralRowItem {
    fileprivate let titleLayout: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, title: String) {
        self.titleLayout = .init(.initialize(string: title, color: theme.colors.grayText, font: .medium(.text)))
        self.titleLayout.measure(width: .greatestFiniteMagnitude)
        super.init(initialSize, stableId: stableId)
    }

    public override var height: CGFloat {
        return 30
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return SectionHeaderView.self
    }
}

private final class SectionHeaderView: GeneralRowView {
    private let titleView = TextView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        titleView.isSelectable = false
        titleView.userInteractionEnabled = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? SectionHeaderItem else { return }
        titleView.update(item.titleLayout)
    }

    public override func layout() {
        super.layout()
        titleView.setFrameOrigin(NSMakePoint(10, (frame.height - titleView.frame.height) / 2))
    }
}

private final class CraftGiftsRowItem: GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let gifts: [ProfileGiftsContext.State.StarGift]
    fileprivate let selectGift: (ProfileGiftsContext.State.StarGift) -> Void

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), gifts: [ProfileGiftsContext.State.StarGift], selectGift: @escaping (ProfileGiftsContext.State.StarGift) -> Void, inset: NSEdgeInsets = .init(left: 5, right: 5)) {
        self.context = context
        self.gifts = gifts
        self.selectGift = selectGift
        super.init(initialSize, stableId: stableId, inset: inset)
    }

    public override var height: CGFloat {
        return 120
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonGift
    }

    public override func viewClass() -> AnyClass {
        return CraftGiftsRowView.self
    }
}

private final class CraftGiftsRowView: GeneralRowView {

    private final class GiftView: Control {
        private let modelView: NSView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 60, 60))
        private var backgroundView: UniqueGiftBackgroundView?
        private var backgroundContent: UniqueGiftBackgroundContent?
        private var backgroundContext: (any AccountContextProtocol)?
        private var badgeView: ImageView?
        private let chanceTextView = TextView()
        private var accessibilityGift: StarGift.UniqueGift?
        private var isAccessibilityLocked: Bool = false

        public override var accessibilityDefaultLabel: String? {
            guard let gift = accessibilityGift else {
                return nil
            }
            return "\(gift.title) #\(gift.number)"
        }

        public override func accessibilityValue() -> Any? {
            var parts: [String] = []
            if let text = chanceTextView.textLayout?.attributedString.string, !text.isEmpty {
                parts.append(text)
            }
            if isAccessibilityLocked {
                parts.append(strings().voiceOverCommonLocked)
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(modelView)
            addSubview(chanceTextView)

            (modelView as? View)?.userInteractionEnabled = false
            chanceTextView.userInteractionEnabled = false
            chanceTextView.isSelectable = false
            chanceTextView.isAccessibilityDecorative = true

            scaleOnClick = true
            layer?.cornerRadius = 14
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func set(gift: ProfileGiftsContext.State.StarGift, context: (any AccountContextProtocol), animated: Bool, callback: @escaping () -> Void) {
            removeAllHandlers()

            let isCraftLocked: Bool
            if let canCraftAt = gift.canCraftAt, canCraftAt > context.timestamp {
                isCraftLocked = true
            } else {
                isCraftLocked = false
            }

            set(handler: { _ in
                if isCraftLocked, let canCraftAt = gift.canCraftAt {
                    let remaining = Int(canCraftAt - context.timestamp)
                    showModalText(for: context.window, text: strings().starGiftCraftGiftTooEarly(autoremoveLocalized(remaining)))
                } else {
                    callback()
                }
            }, for: .Click)

            self.alphaValue = isCraftLocked ? 0.8 : 1.0
            self.isAccessibilityLocked = isCraftLocked
            self.accessibilityGift = gift.gift.unique

            guard let unique = gift.gift.unique else { return }


            (modelView as? StarsStickerView)?.updateStarsSticker(file: unique.file!, size: modelView.frame.size, context: context, colors: [], playback: .loopHidden, animated: animated)

            let colors = unique.backdrop ?? [NSColor(0x6C5CE7), NSColor(0xA29BFE)]

            if let content = UniqueGiftBackgroundContent(gift: unique) {
                if self.backgroundView == nil {
                    let current = UniqueGiftBackgroundView(frame: bounds.insetBy(dx: 1, dy: 1))
                    self.addSubview(current, positioned: .below, relativeTo: modelView)
                    self.backgroundView = current
                }
                self.backgroundContent = content
                self.backgroundContext = context
            } else {
                self.backgroundView?.removeFromSuperview()
                self.backgroundView = nil
                self.backgroundContent = nil
                self.backgroundContext = nil
            }

            let badge: ImageView
            if let existing = badgeView {
                badge = existing
            } else {
                badge = ImageView()
                badge.isAccessibilityDecorative = true
                addSubview(badge)
                badgeView = badge
            }
            let ribbon = generateGradientTintedImage(image: TelegramThemeHooks.shared.image(.giftRibbon).precomposed(), colors: colors, direction: .diagonal)!
            badge.image = generateGiftBadgeBackground(background: ribbon, text: "#\(unique.number)", textColor: .white)
            badge.sizeToFit()

            let chancePercent = (gift.gift.unique?.craftChancePermille ?? 0) / 10
            let chanceLayout = TextViewLayout(.initialize(string: "+\(chancePercent)%", color: .white, font: .medium(9)), alignment: .center)
            chanceLayout.measure(width: .greatestFiniteMagnitude)
            chanceTextView.update(chanceLayout)
            chanceTextView.setFrameSize(NSMakeSize(chanceLayout.layoutSize.width + 6, chanceLayout.layoutSize.height + 5))
            chanceTextView.layer?.cornerRadius = chanceTextView.frame.height / 2
            chanceTextView.backgroundColor = NSColor.white.withAlphaComponent(0.2)

            needsLayout = true
        }

        public override func layout() {
            super.layout()
            modelView.centerX(y: 15)
            if let backgroundView, let content = backgroundContent, let context = backgroundContext {
                backgroundView.frame = bounds.insetBy(dx: 1, dy: 1)
                backgroundView.update(context: context, content: content, style: .item(giftCenterY: modelView.frame.midY - backgroundView.frame.minY, cornerRadius: 10))
            }
            badgeView?.setFrameOrigin(NSMakePoint(frame.width - (badgeView?.frame.width ?? 0), 0))
            chanceTextView.setFrameOrigin(NSMakePoint(5, 5))
        }
    }

    private var giftViews: [GiftView] = []

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? CraftGiftsRowItem else { return }

        while giftViews.count > item.gifts.count {
            giftViews.removeLast().removeFromSuperview()
        }
        while giftViews.count < item.gifts.count {
            let view = GiftView(frame: .zero)
            giftViews.append(view)
            addSubview(view)
        }

        for (i, gift) in item.gifts.enumerated() {
            let view = giftViews[i]
            view.set(gift: gift, context: item.context, animated: animated, callback: { [weak item] in
                item?.selectGift(gift)
            })
        }

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        guard let item = item as? CraftGiftsRowItem else { return }
        let insets = item.inset
        let count = CGFloat(3)
        let space = frame.width - insets.left - insets.right - (10 * (count - 1))
        let itemWidth = floor(space / 3)
        var x: CGFloat = insets.left
        for view in giftViews {
            view.setFrameSize(NSMakeSize(itemWidth, 110))
            view.setFrameOrigin(NSMakePoint(x, 5))
            x += itemWidth + 10
        }
    }
}

private final class FilterRowItem: TableStickItem {
    fileprivate let arguments: Arguments!
    fileprivate let items: [HeaderItem.AttributeItem]
    private let _stableId: AnyHashable

    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments) {
        self._stableId = stableId
        self.arguments = arguments
        self.items = State.Attribute.all.map { .init(attribute: $0, resaleState: state.resaleState) }
        super.init(initialSize)
    }

    public required init(_ initialSize: NSSize) {
        self._stableId = AnyHashable(0)
        self.arguments = nil
        self.items = []
        super.init(initialSize)
    }

    public override var stableId: AnyHashable {
        return _stableId
    }
    
    public override var singletonItem: Bool {
        return false
    }
    
    public override var isFixed: Bool {
        return true
    }
    
    public override var canBeAnchor: Bool {
        return false
    }

    public override var height: CGFloat {
        return 40
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonFilter
    }

    public override func viewClass() -> AnyClass {
        return FilterRowView.self
    }
}

private final class FilterRowView: TableStickView {
    private let containerView = View()

    private class AttributeItemView: Control {
        private let textView = TextView()
        private let imageView = ImageView()
        private var leftIconView: ImageView?

        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            addSubview(imageView)
            scaleOnClick = true
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            textView.isAccessibilityDecorative = true
            imageView.isAccessibilityDecorative = true
            imageView.image = TelegramThemeHooks.shared.image(.iconAffiliateExpand).precomposed(theme.colors.darkGrayText)
            imageView.sizeToFit()
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func set(item: HeaderItem.AttributeItem, arguments: Arguments, animated: Bool) {
            self.textView.update(item.text)
            self.setAccessibilityLabel(item.text.attributedString.string)
            self.contextMenu = {
                let menu = ContextMenu()
                menu.items = arguments.getMenuItems(item.attribute)
                return menu
            }

            if let image = item.image {
                let current: ImageView
                if let view = self.leftIconView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    addSubview(current)
                    self.leftIconView = current
                }
                current.image = image
                current.sizeToFit()
            } else if let view = self.leftIconView {
                performSubviewRemoval(view, animated: animated)
                self.leftIconView = nil
            }

            self.setFrameSize(NSMakeSize((leftIconView != nil ? 14 : 0) + item.text.layoutSize.width + imageView.frame.width + 21, 30))
            self.backgroundColor = theme.colors.grayForeground
            self.layer?.cornerRadius = 15
        }

        public override func layout() {
            super.layout()
            var offset: CGFloat = 10
            if let leftIconView {
                leftIconView.centerY(x: 5)
                offset = leftIconView.frame.maxX + 5
            }
            self.textView.centerY(x: offset)
            self.imageView.centerY(x: self.textView.frame.maxX + 3)
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(containerView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var header: Bool {
        didSet {
            updateColors()
        }
    }

    public override func updateIsVisible(_ visible: Bool, animated: Bool) {
        containerView.change(opacity: 1, animated: animated)
    }
    
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview?.className == "TGUIKit.TGFlipableTableView" {
            var bp = 0
            bp += 1
        }
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func updateColors() {
        self.containerView.backgroundColor = theme.colors.background
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? FilterRowItem else { return }

        while containerView.subviews.count > item.items.count {
            containerView.subviews.last?.removeFromSuperview()
        }
        while containerView.subviews.count < item.items.count {
            containerView.addSubview(AttributeItemView(frame: .zero))
        }

        var x: CGFloat = 10
        for (i, attr) in item.items.enumerated() {
            let view = containerView.subviews[i] as! AttributeItemView
            view.set(item: attr, arguments: item.arguments, animated: animated)
            view.setFrameOrigin(NSMakePoint(x, 5))
            x += view.frame.width + 5
        }

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        containerView.frame = bounds
        var x: CGFloat = 10
        for view in containerView.subviews {
            view.setFrameOrigin(NSMakePoint(x, 5))
            x += view.frame.width + 5
        }
    }

}

private final class StarsOnlyToggleView: Control {
    private let checkView = SelectingControl(
        unselectedImage: generateChatGroupToggleUnselected(foregroundColor: theme.colors.grayIcon.withAlphaComponent(0.6), backgroundColor: NSColor.black.withAlphaComponent(0.01)),
        selectedImage: generateChatGroupToggleSelected(foregroundColor: theme.colors.accentIcon, backgroundColor: theme.colors.underSelectedColor)
    )
    private let textView = TextView()
    private var glassView: NSView?

    public var isOn: Bool = false {
        didSet {
            checkView.set(selected: isOn, animated: true)
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 999, hasShadow: true, hasBorder: true)
        addSubview(glass, positioned: .below, relativeTo: nil)
        self.glassView = glass
        self.shadow = nil

        addSubview(checkView)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        checkView.userInteractionEnabled = false

        let layout = TextViewLayout(.initialize(string: strings().starGiftMarketplaceShowStarsOnly, color: theme.colors.text, font: .medium(.text)))
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)

        let height: CGFloat = 40
        let padding: CGFloat = 12
        let spacing: CGFloat = 6
        let width = padding + checkView.frame.width + spacing + layout.layoutSize.width + padding
        setFrameSize(NSMakeSize(width, height))
        layer?.cornerRadius = height / 2


        scaleOnClick = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        glassView?.frame = bounds
        let spacing: CGFloat = 6
        let padding: CGFloat = 12
        checkView.centerY(x: padding)
        textView.centerY(x: checkView.frame.maxX + spacing)
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    if state.isCraftMode {
        if !state.craftGifts.isEmpty {

            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_your_gifts_header, equatable: nil, comparable: nil, item: { initialSize, stableId in
                return SectionHeaderItem(initialSize, stableId: stableId, title: strings().starGiftMarketplaceYourGifts)
            }))
            index += 1

            let yourGiftsChunks = state.craftGifts.chunks(3)
            for (i, chunk) in yourGiftsChunks.enumerated() {
                if !chunk.isEmpty {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_craft_gifts(i), equatable: .init(chunk), comparable: nil, item: { initialSize, stableId in
                        return CraftGiftsRowItem(initialSize, stableId: stableId, context: arguments.context, gifts: chunk, selectGift: { gift in
                            arguments.selectGift?(gift)
                        }, inset: .init(left: 10, right: 10))
                    }))
                    index += 1

                }
            }
        } else {
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_your_gifts_header, equatable: nil, comparable: nil, item: { initialSize, stableId in
                return SectionHeaderItem(initialSize, stableId: stableId, title: strings().starGiftMarketplaceYourGifts)
            }))
            index += 1

            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().starGiftMarketplaceNoOtherGifts), data: .init(color: theme.colors.grayText, viewType: .singleItem, fontSize: .text, centerViewAlignment: true, alignment: .center)))
            index += 1

        }

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_resale_header, equatable: .init(state.count), comparable: nil, item: { initialSize, stableId in
            return SectionHeaderItem(initialSize, stableId: stableId, title: strings().starGiftMarketplaceSuitableGiftsOnSale(Int(state.count)))
        }))
        index += 1

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_filter_row, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return FilterRowItem(initialSize, stableId: stableId, state: state, arguments: arguments)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(5)))
        sectionId += 1
    }

    if let resaleState = state.resaleState {

        let chunks = resaleState.gifts.filter { $0.unique?.resellStars != nil }.chunks(3)

        let isLoading: Bool
        switch resaleState.dataState {
        case .loading:
            isLoading = true
        case .ready:
            isLoading = false
        }

        if !chunks.isEmpty {
            for (i, chunk) in chunks.enumerated() {
                if !chunk.isEmpty {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_stars_gifts(i), equatable: .init(chunk), comparable: nil, item: { initialSize, stableId in
                        return GiftOptionsRowItem(initialSize, stableId: stableId, context: arguments.context, options: chunk.map { .initialize($0.unique!, context: arguments.context, showNumber: true) }, insets: .init(left: 5, right: 5), callback: { option, morphSource in
                            if let gift = option.nativeStarUniqueGift {
                                arguments.open(gift, morphSource)
                            }
                        })
                    }))

                    entries.append(.sectionId(sectionId, type: .customModern(10)))
                    sectionId += 1
                }
            }
        } else if isLoading {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .legacy, height: 270)
            }))
        } else {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return EmptyRowItem(initialSize, stableId: stableId, arguments: arguments)
            }))
        }


    }

    return entries
}

public func StarGift_MarketplaceController(context: (any AccountContextProtocol), peerId: PeerId, gift: StarGift.Gift, craftGiftsContext: CraftGiftsContext? = nil, excludedReferences: Set<StarGiftReference> = [], selectGift: ((ProfileGiftsContext.State.StarGift) -> Bool)? = nil) -> InputDataModalController {

    
    
    let actionsDisposable = DisposableSet()

    var initialState = State(gift: gift)
    initialState.isCraftMode = craftGiftsContext != nil

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let resaleContext = ResaleGiftsContext(account: context.account, giftId: gift.id, forCrafting: craftGiftsContext != nil)
    
    var getController:(()->InputDataController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }
    
    let starsContext = context.starsContext
    
    starsContext.load(force: true)
    
    actionsDisposable.add(starsContext.state.startStrict(next: { starsState in
        updateState { current in
            var current = current
            current.starsState = starsState
            return current
        }
    }))
        
    actionsDisposable.add(resaleContext.state.startStrict(next: { state in
        updateState { current in
            var current = current
            current.resaleState = state
            return current
        }
    }))

    if let craftGiftsContext = craftGiftsContext {
        let debugSimulateEmptyCraftGifts = false
        actionsDisposable.add(craftGiftsContext.state.startStrict(next: { craftState in
            updateState { current in
                var current = current
                if debugSimulateEmptyCraftGifts {
                    current.craftGifts = []
                } else {
                    current.craftGifts = craftState.gifts.filter { gift in
                        guard gift.gift.unique != nil else { return false }
                        if let reference = gift.reference, excludedReferences.contains(reference) {
                            return false
                        }
                        return true
                    }
                }
                return current
            }
        }))
    }

    var getMenuItems:((State.Attribute)->[ContextMenuItem])? = nil

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, getMenuItems: { attribute in
        return getMenuItems?(attribute) ?? []
    }, toggleAttribute: { [weak resaleContext] value in
        
        let state = stateValue.with { $0 }
        
        var currentFilterAttributes: [ResaleGiftsContext.Attribute] = []
        
        if let filterAttributes = state.resaleState?.filterAttributes {
            currentFilterAttributes = filterAttributes
        }

        if currentFilterAttributes.contains(where: { $0 == value }) {
            currentFilterAttributes.removeAll(where: { $0 == value })
        } else {
            currentFilterAttributes.insert(value, at: 0)
        }
        
        resaleContext?.updateFilterAttributes(currentFilterAttributes)
        
    }, selectAll: { [weak resaleContext] attr in
        let state = stateValue.with { $0 }
        
        var currentFilterAttributes: [ResaleGiftsContext.Attribute] = []
        
        if let filterAttributes = state.resaleState?.filterAttributes {
            currentFilterAttributes = filterAttributes
        }

        currentFilterAttributes.removeAll(where: { value in
            switch value {
            case .backdrop:
                if case .backdrop = attr {
                    return true
                }
            case .model:
                if case .model = attr {
                    return true
                }
            case .pattern:
                if case .pattern = attr {
                    return true
                }
            }
            return false
        })
        
        resaleContext?.updateFilterAttributes(currentFilterAttributes)
    }, open: { [weak resaleContext] gift, morphSource in
        let onPurchaseCallback: (ProfileGiftsContext.State.StarGift) -> Void = { purchasedGift in
            if let selectGift, !selectGift(purchasedGift) {
                craftGiftsContext?.reload()
            } else {
                close?()
            }
        }
        showModal(with: StarGift_Nft_Controller(context: context, gift: .unique(gift), source: .quickLook(nil, gift), purpose: .starGift(gift: .unique(gift), convertStars: nil, text: nil, entities: nil, nameHidden: false, savedToProfile: false, converted: false, fromProfile: false, upgraded: true, prepaidUpgradeHash: nil, transferStars: nil, canExportDate: nil, reference: nil, sender: nil, saverId: nil, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: nil, canUpgrade: false, number: nil, isRefunded: false, canCraftAt: nil, craftChancePermille: nil, upgradeStars: nil), resaleContext: resaleContext, toPeerId: peerId, onPurchase: onPurchaseCallback), for: window, morphSource: morphSource)
    }, clearFilters: { [weak resaleContext] in
        resaleContext?.updateFilterAttributes([])
    }, selectGift: selectGift.flatMap { callback in
        return { gift in
            if callback(gift) {
                close?()
            }
        }
    })
    
    getMenuItems = { [weak arguments, weak resaleContext] attribute in
        
        guard let arguments else {
            return []
        }
        let state = stateValue.with { $0 }
        
        var items: [ContextMenuItem] = []
        switch attribute {
        case .sort:
            
            items.append(ContextMenuItem(strings().giftMarketplaceSortPrice, handler: {
                resaleContext?.updateSorting(.value)
            }, state: state.resaleState?.sorting == .value ? .on : nil, itemImage: MenuAnimation.menu_cash_up.value))
            
            items.append(ContextMenuItem(strings().giftMarketplaceSortDate, handler: {
                resaleContext?.updateSorting(.date)
            }, state: state.resaleState?.sorting == .date ? .on : nil, itemImage: MenuAnimation.menu_calendar_up.value))
            
            items.append(ContextMenuItem(strings().giftMarketplaceSortNumber, handler: {
                resaleContext?.updateSorting(.number)
            }, state: state.resaleState?.sorting == .number ? .on : nil, itemImage: MenuAnimation.menu_hashtag_up.value))
        default:
            if let resaleState = state.resaleState {
                
               
                
                let attrs = resaleState.attributes.filter({ attr in
                    switch attr {
                    case .model:
                        return attribute == .model
                    case .backdrop:
                        return attribute == .backdrop
                    case .pattern:
                        return attribute == .symbol
                    default:
                        return false
                    }
                })
                
                let filteredAttrs = resaleState.filterAttributes.filter({ attr in
                    switch attr {
                    case .model:
                        return attribute == .model
                    case .backdrop:
                        return attribute == .backdrop
                    case .pattern:
                        return attribute == .symbol
                    }
                })
                
                let allSelected: Bool = filteredAttrs.isEmpty
    

                if !allSelected {
                    items.append(ContextMenuItem(strings().giftMarketplaceSelectAll, handler: {
                        if let first = attrs.first?.resaleAttr {
                            arguments.selectAll(first)
                        }
                    }, state: allSelected ? .on : nil))
                    
                    items.append(ContextSeparatorItem())
                }
                
                
                
                for attr in attrs {
                    let count = resaleState.attributeCount[attr.resaleAttr] ?? 0
                    items.append(AttributeMenuItem(attribute: attr, count: count, selected: resaleState.filterAttributes.contains(where: { $0 == attr.resaleAttr }) || allSelected, arguments: arguments))
                }
            }

        }
        return items
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let isCraftMode = craftGiftsContext != nil

    
    let controller = InputDataController(dataSignal: signal, title: isCraftMode ? "Select Gifts" : "")
    controller.analyticsScreen = isCraftMode ? AnalyticsScreen.giftsCraftPicker : AnalyticsScreen.giftsMarketplace
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.contextObject = resaleContext


    if !isCraftMode {
        let view = HeaderItemView(frame: NSMakeRect(0, 0, 368, 105))
        controller.contextObject_second = view

        controller.afterTransaction = { controller in
            let view = controller.contextObject_second as? HeaderItemView
            let item = HeaderItem(controller.frame.size, stableId: InputDataEntryId.custom(_id_header), state: stateValue.with { $0 }, context: context, arguments: arguments)
            view?.set(item: item, animated: false)

            if let toggleView = controller.contextObject_third as? StarsOnlyToggleView {
                let tableFrame = controller.tableView.frame
                toggleView.setFrameOrigin(NSMakePoint(round((controller.genericView.frame.width - toggleView.frame.width) / 2), tableFrame.maxY - toggleView.frame.height - 10))
            }
        }
    }

    controller.didLoad = { [weak resaleContext] controller, _ in
        controller.tableView.getBackgroundColor = {
            return theme.colors.background
        }
        
        controller.tableView.set(stickClass: FilterRowItem.self, handler: { _ in })

        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                resaleContext?.loadMore()
            default:
                break
            }
        }

        if !isCraftMode {
            let view = controller.contextObject_second as? HeaderItemView
            controller.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak view, weak controller] scroll in
                guard let view, let controller else {
                    return
                }
                let visible = scroll.rect.minY >= (controller.tableView.frame.height)
                view.updateBorder(visible: visible)
            }))
        }
    }

    controller.afterViewDidLoad = { [resaleContext] in
        guard let controller = getController?() else {
            return
        }
        if !isCraftMode {
            let view = controller.contextObject_second as? HeaderItemView
            controller.genericView.set(view)

            let toggleView = StarsOnlyToggleView(frame: .zero)
            toggleView.set(handler: { [weak toggleView, weak resaleContext] _ in
                guard let toggleView else { return }
                toggleView.isOn = !toggleView.isOn
                resaleContext?.updateStarsOnly(toggleView.isOn)
            }, for: .Click)
            controller.genericView.addSubview(toggleView)
            controller.contextObject_third = toggleView
        }
    }
    

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalController = InputDataModalController(controller, modalInteractions: nil, size: NSMakeSize(390, 0))
    modalController.fullSizeList = true

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    modalController.alwaysActiveHeader = true

    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}


/*

 */



