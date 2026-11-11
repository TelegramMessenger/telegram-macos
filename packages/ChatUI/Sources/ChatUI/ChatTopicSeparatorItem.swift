import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramCore
import TGUIKit
import AvatarUI
import ChatHistoryModel
import TelegramContext
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

extension ChatHistoryEntry.TopicType {
    public var title: String {
        switch self {
        case let .peer(peer):
            return peer._asPeer().displayTitle
        case let .topic(_, info):
            return info.title
        }
    }
    public var threadId: Int64 {
        switch self {
        case let .peer(peer):
            return peer.id.toInt64()
        case let .topic(threadId, _):
            return threadId
        }
    }
}

public class ChatTopicSeparatorItem : TableStickItem {
    
    public let layout:TextViewLayout
    public let glassLayout: TextViewLayout
    public let color: NSColor
    public let entry: ChatHistoryEntry
    public let interaction: ChatInteraction?
    public let presentation: TelegramPresentationTheme
    
    public var context: (any AccountContextProtocol)? {
        return interaction?.interactionContext
    }

    
    public convenience init(_ initialSize:NSSize, _ entry:ChatHistoryEntry, interaction: ChatInteraction, theme: TelegramPresentationTheme) {
        self.init(initialSize, entry: entry, interaction: interaction, theme: theme)
    }

    init(_ initialSize: NSSize, entry: ChatHistoryEntry, interaction: ChatInteraction? = nil, theme: TelegramPresentationTheme) {
        self.entry = entry
        self.interaction = interaction
        self.presentation = theme
        
        guard case let .topicSeparator(_, type, _, _) = entry else {
            fatalError()
        }
        
        let color = theme.chatServiceItemTextColor
        self.color = color
        
        self.layout = TextViewLayout(.initialize(string: type.title, color: color, font: .medium(theme.fontSize)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
        self.glassLayout = TextViewLayout(.initialize(string: type.title, color: theme.colors.text, font: .medium(theme.fontSize)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)


        super.init(initialSize)
    }
    
    public var shouldBlurService: Bool {
        if TelegramUtilsHooks.shared.isLite(.blur) {
            return false
        }
        return presentation.shouldBlurService || presentation.bubbled && presentation.backgroundMode.hasWallpaper
    }
    
    public required init(_ initialSize: NSSize) {
        self.entry = .empty(MessageIndex.absoluteLowerBound(), theme)
        self.layout = TextViewLayout(NSAttributedString())
        self.glassLayout = TextViewLayout(NSAttributedString())
        self.interaction = nil
        self.presentation = theme
        self.color = .random
        super.init(initialSize)
    }
    
    public override var canBeAnchor: Bool {
        return false
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        layout.measure(width: width - 100)
        glassLayout.measure(width: width - 100)
        return success
    }
    
    public override var stableId: AnyHashable {
        return entry.stableId
    }
    
    public override var height: CGFloat {
        return 28
    }
    
    public override func viewClass() -> AnyClass {
        return ChatTopicSeparatorItemView.self
    }
    
}

private class ChatTopicSeparatorItemView : TableStickView {
    
    private final class LineView : View {
        
        weak var item: ChatTopicSeparatorItem? {
            didSet {
                needsDisplay = true
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            if newSize != frame.size {
                needsDisplay = true
            }
            super.setFrameSize(newSize)
        }

        override func draw(_ layer: CALayer, in ctx: CGContext) {
            super.draw(layer, in: ctx)

            guard let item else {
                return
            }

            let bounds = layer.bounds
            let lineWidth: CGFloat = 1.0
            let dashLength: CGFloat = 4.0
            let dashGap: CGFloat = 2.0
            let centerY = bounds.midY

            ctx.saveGState()
            ctx.setStrokeColor(item.presentation.chatServiceItemColor.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: 0, lengths: [dashLength, dashGap])
            ctx.move(to: CGPoint(x: bounds.minX, y: centerY))
            ctx.addLine(to: CGPoint(x: bounds.maxX, y: centerY))
            ctx.strokePath()
            ctx.restoreGState()

        }
    }
    
    private let textView:TextView = TextView()
    private var avatarView: AvatarControl?
    private var iconView: InlineStickerView?
    private var topicIconIdentity: ChatTopicIconIdentity?
    private let containerView: View = View()
    private let backgroundView = View()
    private let serviceView = View()
    private let glassView = LiquidGlassView(frame: .zero, hasShadow: true, hasBorder: true)
    private var appliedGlass: Bool?
    private let overlay = Control()
    private let chevron = ImageView()
    private let lineView = LineView()
    private var visualEffect: VisualEffect?
    required init(frame frameRect: NSRect) {

        self.textView.isSelectable = false
        self.textView.userInteractionEnabled = false
        self.containerView.wantsLayer = true
        self.glassView.isEventLess = true
        super.init(frame: frameRect)
        addSubview(lineView)
        addSubview(backgroundView)
        backgroundView.addSubview(serviceView)
        backgroundView.addSubview(glassView)
        serviceView.layer?.masksToBounds = true
        containerView.addSubview(textView)
        containerView.addSubview(chevron)
        textView.isAccessibilityDecorative = true
        chevron.isAccessibilityDecorative = true
        addSubview(containerView)
        
        addSubview(overlay)
        
        
    }
    
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
       
        return .clear
    }
    
    override func updateIsVisible(_ visible: Bool, animated: Bool) {
        if visible || !animated {
            backgroundView.isHidden = !visible
            containerView.isHidden = !visible
        }
        backgroundView.change(opacity: visible ? 1 : 0, animated: animated)
        containerView.change(opacity: visible ? 1 : 0, animated: animated)
        overlay.isHidden = !visible
    }
    
    override var header: Bool {
        didSet {
            lineView.change(opacity: header ? 0 : 1, animated: false)
            if header != oldValue {
                updateStyle(animated: true)
            }
        }
    }

    private var usesGlass: Bool {
        return header && !TelegramUtilsHooks.shared.isLite(.blur)
    }

    private func updateStyle(animated: Bool) {
        guard let item = item as? ChatTopicSeparatorItem else {
            return
        }
        let usesGlass = self.usesGlass
        let styleChanged = appliedGlass.flatMap { $0 != usesGlass } ?? false
        let animated = animated && styleChanged && !TelegramUtilsHooks.shared.isLite(.animations) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        appliedGlass = usesGlass
        if animated {
            glassView.isHidden = false
            glassView.change(opacity: usesGlass ? 1 : 0, animated: true, completion: { [weak self] _ in
                guard let self, self.appliedGlass == false else {
                    return
                }
                self.glassView.isHidden = true
            })
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            textView.layer?.add(fade, forKey: "styleFade")
            chevron.layer?.add(fade, forKey: "styleFade")
        } else {
            glassView.change(opacity: usesGlass ? 1 : 0, animated: false)
            glassView.isHidden = !usesGlass
        }
        serviceView.change(opacity: usesGlass ? 0 : 1, animated: animated)
        let textColor = usesGlass ? item.presentation.colors.text : item.color
        chevron.image = TelegramThemeHooks.shared.image(.iconAffiliateChevron).precomposed(textColor.withAlphaComponent(0.6), zoom: 0.8)
        chevron.sizeToFit()
        textView.update(usesGlass ? item.glassLayout : item.layout)
        if case let .topicSeparator(_, .topic(threadId, info), _, _) = item.entry {
            updateTopicIcon(threadId: threadId, info: info, item: item)
        }
    }

    private func updateTopicIcon(threadId: Int64, info: Message.AssociatedThreadInfo, item: ChatTopicSeparatorItem) {
        guard let context = item.context else { return }
        let fileId = info.icon ?? 0
        let iconColor = usesGlass ? item.presentation.colors.text : item.color
        let identity = ChatTopicIconIdentity(account: context.account, fileId: fileId, title: info.title, iconColor: info.iconColor, isGeneral: threadId == 1, generalColor: theme.chatList.badgeMutedBackgroundColor, customColor: iconColor)
        if self.iconView == nil || topicIconIdentity != identity {
            let origin = self.iconView?.frame.origin ?? .zero
            topicIconIdentity = identity
            if let iconView {
                iconView.removeFromSuperview()
                self.iconView = nil
            }

            let file: TelegramMediaFile?
            if fileId == 0 {
                file = ChatInterfaceHooks.shared.makeTopicIconFile(info.title, info.iconColor, threadId == 1)
            } else {
                file = nil
            }

            let animatedView = InlineStickerView(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId == 0 ? threadId : fileId, file: file, emoji: ""), size: NSMakeSize(18, 18), getColors: { file in
                file.isCustomTemplateEmoji ? [.init(keyPath: "", color: iconColor)] : []
            }, playPolicy: .framesCount(1))

            animatedView.setFrameOrigin(origin)
            self.iconView = animatedView
            containerView.addSubview(animatedView)
        }
    }


    override func updateColors() {
        super.updateColors()

        guard let item = item as? ChatTopicSeparatorItem else {
            return
        }
        serviceView.backgroundColor = visualEffect == nil ? item.presentation.chatServiceItemColor : .clear
        visualEffect?.bgColor = item.presentation.chatServiceItemColor
        visualEffect?.material = topicSeparatorMaterial(dark: item.presentation.colors.isDark)
        glassView.updateLocalizationAndTheme(theme: item.presentation)
    }
    

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? ChatTopicSeparatorItem, let monoforumState = item.entry.additionalData.monoforumState else {
            return
        }
        
        let animationView = self.avatarView ?? self.iconView

        
        let blockWidth = (animationView?.frame.width ?? 0) + textView.frame.width + chevron.frame.width + 5 + 3
        
        transition.updateFrame(view: containerView, frame: focus(NSMakeSize(blockWidth, size.height)).offsetBy(dx: monoforumState == .vertical ? 40 : 0, dy: 0))
        
        
        
        if let animationView {
            transition.updateFrame(view: animationView, frame: animationView.centerFrameY(x: self.iconView != nil ? 1 : 0))
            transition.updateFrame(view: textView, frame: textView.centerFrameY(x: animationView.frame.maxX + 5))
        }
        transition.updateFrame(view: chevron, frame: chevron.centerFrameY(x: textView.frame.maxX + 3, addition: -1))
        transition.updateFrame(view: overlay, frame: size.bounds)
        
        
        let backgroundFrame = NSMakeRect(containerView.frame.minX - 3, 2, containerView.frame.width + 3, size.height - 4)
        transition.updateFrame(view: backgroundView, frame: backgroundFrame)
        transition.updateFrame(view: serviceView, frame: backgroundFrame.size.bounds)
        transition.updateFrame(view: glassView, frame: backgroundFrame.size.bounds)
        glassView.updateLayout(size: backgroundFrame.size, transition: transition)

        transition.updateFrame(view: lineView, frame: size.bounds)

        if let visualEffect {
            transition.updateFrame(view: visualEffect, frame: backgroundFrame.size.bounds)
        }

    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated:animated)
        
        guard let item = item as? ChatTopicSeparatorItem else {
            return
        }
        overlay.setAccessibilityLabel(item.layout.attributedString.string)
        
        guard case let .topicSeparator(_, type, _, _) = item.entry else {
            return
        }
        
        if item.shouldBlurService {
            let blurBackground = item.presentation.chatServiceItemColor
            
            if self.visualEffect == nil {
                self.visualEffect = VisualEffect(frame: self.bounds)
                self.serviceView.addSubview(self.visualEffect!, positioned: .below, relativeTo: nil)
            }
            self.visualEffect?.bgColor = blurBackground
            self.visualEffect?.material = topicSeparatorMaterial(dark: item.presentation.colors.isDark)
            self.serviceView.backgroundColor = .clear
        } else {
            if let visualEffect {
                performSubviewRemoval(visualEffect, animated: animated)
                self.visualEffect = nil
            }
            self.serviceView.backgroundColor = item.presentation.chatServiceItemColor
        }

        lineView.item = item

        serviceView.layer?.cornerRadius = (item.height - 4) / 2
        glassView.cornerRadius = (item.height - 4) / 2

        updateStyle(animated: false)
        
        if let context = item.context {
            
            switch type {
            case let .peer(peer):
                
                if let iconView {
                    performSubviewRemoval(iconView, animated: animated)
                    self.iconView = nil
                }
                
                let current: AvatarControl
                if let view = self.avatarView {
                    current = view
                } else {
                    current = AvatarControl(font: .avatar(10))
                    current.setFrameSize(NSMakeSize(18, 18))
                    containerView.addSubview(current)
                    self.avatarView = current
                }
                current.setPeer(account: context.account, peer: peer._asPeer())
            case let .topic(threadId, info):
                
                if let avatarView {
                    performSubviewRemoval(avatarView, animated: animated)
                    self.avatarView = nil
                }
                
                updateTopicIcon(threadId: threadId, info: info, item: item)

            }
            
            overlay.setSingle(handler: { [weak item] _ in
                item?.interaction?.updateChatLocationThread(type.threadId)
            }, for: .Click)
        }
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        
        self.updateLayout(size: self.frame.size, transition: transition)

    }
    
}

private func topicSeparatorMaterial(dark: Bool) -> NSVisualEffectView.Material {
    if #available(macOS 10.14, *) {
        return dark ? .hudWindow : .titlebar
    }
    return .appearanceBased
}
