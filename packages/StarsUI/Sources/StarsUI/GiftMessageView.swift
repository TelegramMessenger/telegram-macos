import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import TelegramTheme
import GeneralRows
import AvatarUI

public struct GiftMessage {
    public static let avatarSize: CGFloat = 20
    public static let avatarSpacing: CGFloat = 6
    public static let tailWidth: CGFloat = 6
    public static let topSpacing: CGFloat = 4
    public static let bottomSpacing: CGFloat = 10
    public static let insets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)

    public let peer: EnginePeer?
    public let text: TextViewLayout
    public let minimumBubbleWidth: CGFloat
    public let minimumBubbleHeight: CGFloat

    public init(peer: EnginePeer?, text: TextViewLayout, minimumBubbleWidth: CGFloat = 0, minimumBubbleHeight: CGFloat = GiftMessage.avatarSize) {
        self.peer = peer
        self.text = text
        self.minimumBubbleWidth = minimumBubbleWidth
        self.minimumBubbleHeight = minimumBubbleHeight
    }

    public var bubbleSize: NSSize {
        let width = GiftMessage.tailWidth + GiftMessage.insets.left + text.layoutSize.width + GiftMessage.insets.right
        let height = GiftMessage.insets.top + text.layoutSize.height + GiftMessage.insets.bottom
        return NSMakeSize(max(width, minimumBubbleWidth), max(height, minimumBubbleHeight))
    }

    public var size: NSSize {
        let bubble = bubbleSize
        return NSMakeSize(GiftMessage.avatarSize + GiftMessage.avatarSpacing + bubble.width, bubble.height)
    }

    public var height: CGFloat {
        return GiftMessage.topSpacing + size.height + GiftMessage.bottomSpacing
    }

    public func makeSize(width: CGFloat) {
        let inset = GiftMessage.avatarSize + GiftMessage.avatarSpacing + GiftMessage.tailWidth + GiftMessage.insets.left + GiftMessage.insets.right
        text.measure(width: width - inset)
    }
}

public final class GiftMessageView : View {

    private static let bubble: (CGImage, NSEdgeInsets) = messageBubbleImageModern(incoming: true, fillColor: NSColor.white.withAlphaComponent(0.15), strokeColor: .clear, neighbors: .none)

    private let bubbleView = SImageView()
    private let textView = InteractiveTextView()
    private let avatar = AvatarControl(font: .avatar(6))

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        avatar.setFrameSize(NSMakeSize(GiftMessage.avatarSize, GiftMessage.avatarSize))
        avatar.userInteractionEnabled = false

        textView.userInteractionEnabled = false

        addSubview(avatar)
        addSubview(bubbleView)
        addSubview(textView)

        self.userInteractionEnabled = false
        self.isEventLess = true

        bubbleView.data = GiftMessageView.bubble
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func set(message: GiftMessage, context: any AccountContextProtocol, animated: Bool, openPeer: (() -> Void)? = nil) {
        textView.set(text: message.text, context: context)
        avatar.setPeer(account: context.account, peer: message.peer?._asPeer())
        avatar.removeAllHandlers()
        avatar.userInteractionEnabled = openPeer != nil
        if let openPeer {
            avatar.set(handler: { _ in
                openPeer()
            }, for: .Click)
        }
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        typealias Metrics = GiftMessage

        transition.updateFrame(view: avatar, frame: NSMakeRect(0, size.height - avatar.frame.height, avatar.frame.width, avatar.frame.height))

        let bubbleX = avatar.frame.width + Metrics.avatarSpacing
        transition.updateFrame(view: bubbleView, frame: NSMakeRect(bubbleX, 0, size.width - bubbleX, size.height))

        let bubbleBodyX = bubbleX + Metrics.tailWidth
        let bubbleBodyWidth = size.width - bubbleBodyX
        let textX = floorToScreenPixels(System.backingScale, bubbleBodyX + (bubbleBodyWidth - textView.frame.width) / 2)
        let textOrigin = NSMakePoint(textX, floorToScreenPixels(System.backingScale, (size.height - textView.frame.height) / 2))
        transition.updateFrame(view: textView, frame: CGRect(origin: textOrigin, size: textView.frame.size))
    }
}
