import Cocoa
import TGUIKit
import UniqueGiftBackground
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputView
import InputTextView
import InlineStickerLayer

public final class AddGiftMessagePreviewItem: GeneralRowItem {
    static let stickerSize = NSMakeSize(120, 120)

    fileprivate let context: any AccountContextProtocol
    fileprivate let gift: StarGift.UniqueGift
    fileprivate let headerLayout: TextViewLayout
    fileprivate let titleLayout: TextViewLayout
    fileprivate let giftMessage: GiftMessage
    fileprivate let ribbonImage: CGImage
    fileprivate let backgroundContent: UniqueGiftBackgroundContent?
    fileprivate let stickerFile: TelegramMediaFile?
    fileprivate let send:()->Void

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, gift: StarGift.UniqueGift, message: Updated_ChatTextInputState, send: @escaping()->Void) {
        self.context = context
        self.gift = gift
        self.send = send

        var innerColor: NSColor = theme.colors.accent
        var outerColor: NSColor = theme.colors.accent
        var titleColor: NSColor = NSColor.white.withAlphaComponent(0.8)
        var stickerFile: TelegramMediaFile? = gift.file

        for attribute in gift.attributes {
            switch attribute {
            case let .backdrop(_, _, inner, outer, _, text, _):
                innerColor = NSColor(UInt32(bitPattern: inner)).withAlphaComponent(1)
                outerColor = NSColor(UInt32(bitPattern: outer)).withAlphaComponent(1)
                titleColor = NSColor(UInt32(bitPattern: text))
            case let .model(_, file, _, _):
                if stickerFile == nil {
                    stickerFile = file
                }
            default:
                break
            }
        }

        self.backgroundContent = UniqueGiftBackgroundContent(gift: gift)
        self.stickerFile = stickerFile

        let ribbon = generateGradientTintedImage(image: TelegramThemeHooks.shared.image(.giftRibbon).precomposed(), colors: [outerColor.withMultiplied(hue: 0.97, saturation: 1.45, brightness: 0.89), outerColor.withMultiplied(hue: 1.01, saturation: 1.22, brightness: 1.04)], direction: .mirroredDiagonal)!
        self.ribbonImage = generateGiftBadgeBackground(background: ribbon, text: strings().chatServiceGiftRibbonGift)

        let myName = context.myPeer?.compactDisplayTitle ?? ""
        self.headerLayout = TextViewLayout(.initialize(string: strings().chatServiceStarGiftFrom(myName), color: .white, font: .medium(.header)), alignment: .center)
        self.titleLayout = TextViewLayout(.initialize(string: "\(gift.title) #\(gift.number)", color: titleColor, font: .medium(.text)), alignment: .center)

        let messageText = NSMutableAttributedString()
        if message.string.isEmpty {
            messageText.append(string: strings().starGiftAddMessageYourMessage, color: NSColor.white.withAlphaComponent(0.6), font: .normal(theme.fontSize))
        } else {
            let textInputState = message.textInputState()
            let entities = textInputState.messageTextEntities()
            let attr = StarsHooks.shared.applyGiftMessagePreviewEntities(entities, message.string, context).mutableCopy() as! NSMutableAttributedString
            InlineStickerItem.apply(to: attr, associatedMedia: textInputState.inlineMedia, entities: entities, isPremium: context.isPremium)
            messageText.append(attr)
        }
        let textLayout = TextViewLayout(messageText)
        typealias Metrics = GiftMessage
        let messageWidth = 200 - Metrics.avatarSize - Metrics.avatarSpacing - Metrics.tailWidth - Metrics.insets.left - Metrics.insets.right
        measureBalancedGiftMessage(textLayout, width: messageWidth)
        let minimumTextLayout = TextViewLayout(.initialize(string: "123", color: .white, font: .normal(theme.fontSize)))
        minimumTextLayout.measure(width: .greatestFiniteMagnitude)
        let minimumBubbleWidth = Metrics.tailWidth + Metrics.insets.left + minimumTextLayout.layoutSize.width + Metrics.insets.right
        self.giftMessage = .init(peer: context.myPeer.flatMap(EnginePeer.init), text: textLayout, minimumBubbleWidth: minimumBubbleWidth, minimumBubbleHeight: 36)

        super.init(initialSize, stableId: stableId)

        self.headerLayout.measure(width: 200)
        self.titleLayout.measure(width: 200)
    }

    public override var height: CGFloat {
        typealias Metrics = GiftMessage
        var height: CGFloat = 10 + Self.stickerSize.height + 10
        height += headerLayout.layoutSize.height
        height += 4
        height += titleLayout.layoutSize.height
        height += 14
        height += giftMessage.size.height
        height += 14
        height += 34
        height += 10
        return height
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return headerLayout.attributedString.string
    }

    public override func viewClass() -> AnyClass {
        return AddGiftMessagePreviewView.self
    }
}

final class AddGiftMessagePreviewView: TableRowView {
    private let card = Control(frame: NSMakeRect(0, 0, 220, 0))
    private let backgroundView = UniqueGiftBackgroundView(frame: .zero)
    private let ribbonView = ImageView()
    private let stickerView = StarsHooks.shared.makeStickerView(NSRect(origin: .zero, size: AddGiftMessagePreviewItem.stickerSize))
    private let headerView = TextView()
    private let titleView = TextView()
    private let messageView = GiftMessageView(frame: .zero)
    private let button = TextButton()
    private let buttonStars = GiftButtonStarsView(frame: .zero)

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        card.layer?.cornerRadius = 24
        card.layer?.masksToBounds = true
        card.backgroundColor = NSColor.white.withAlphaComponent(0.2)
        card.isAccessibilityDecorative = true
        ribbonView.isAccessibilityDecorative = true
        addSubview(card)

        card.addSubview(backgroundView)
        card.addSubview(stickerView)
        card.addSubview(headerView)
        card.addSubview(titleView)
        card.addSubview(messageView)
        card.addSubview(button)
        card.addSubview(ribbonView)

        button.addSubview(buttonStars, positioned: .below, relativeTo: button.subviews.first)
        button.layer?.masksToBounds = true
        button.scaleOnClick = true
        button.autohighlight = false

        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        (stickerView as? View)?.userInteractionEnabled = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? AddGiftMessagePreviewItem else {
            return
        }

        backgroundView.isHidden = item.backgroundContent == nil
        ribbonView.image = item.ribbonImage
        ribbonView.sizeToFit()

        if let file = item.stickerFile {
            (stickerView as? StarsStickerView)?.updateStarsSticker(file: file, size: stickerView.frame.size, context: item.context, colors: [], playback: .onceEnd, animated: animated)
        }

        headerView.update(item.headerLayout)
        titleView.update(item.titleLayout)

        messageView.setFrameSize(item.giftMessage.size)
        messageView.set(message: item.giftMessage, context: item.context, animated: animated)

        button.set(font: .medium(.text), for: .Normal)
        button.set(color: .white, for: .Normal)
        button.set(background: NSColor.black.withAlphaComponent(0.12), for: .Normal)
        button.set(text: strings().starGiftAddMessageSendNow, for: .Normal)
        button.sizeToFit(NSMakeSize(38, 0))
        button.setFrameSize(NSMakeSize(button.frame.width, 34))
        button.layer?.cornerRadius = 17
        buttonStars.frame = button.bounds

        button.setSingle(handler: { [weak item] _ in
            item?.send()
        }, for: .Click)

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        guard let item = item as? AddGiftMessagePreviewItem else {
            return
        }
        typealias Metrics = GiftMessage

        card.setFrameSize(NSMakeSize(220, item.height))
        card.centerX(y: 0)

        ribbonView.setFrameOrigin(NSMakePoint(card.frame.width - ribbonView.frame.width, 0))

        stickerView.centerX(y: 10)
        backgroundView.frame = card.bounds.insetBy(dx: 4, dy: 4)
        if let content = item.backgroundContent {
            backgroundView.update(context: item.context, content: content, style: .message(patternCenterY: stickerView.frame.midY - backgroundView.frame.minY + 32, cornerRadius: 20))
        }
        headerView.centerX(y: stickerView.frame.maxY + 10)
        titleView.centerX(y: headerView.frame.maxY + 4)
        messageView.centerX(y: titleView.frame.maxY + 14)
        button.centerX(y: messageView.frame.maxY + 14)
        buttonStars.frame = button.bounds
    }
}