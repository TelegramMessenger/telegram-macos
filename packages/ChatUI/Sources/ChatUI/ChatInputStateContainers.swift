import AppAnalytics
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import PremiumUI
import LocalAnimations

private extension ChatState.AdditionIcon {
    var accessibilityLabel: String {
        switch self {
        case .gigagroup_info:
            return strings().voiceOverCommonInfo
        case .monoforum_suggestion:
            return strings().voiceOverSuggestPost
        case .channel_gift:
            return strings().voiceOverCommonGift
        }
    }
}

public class ChatInputStateView: View {

    public let containerView: Control = Control()

    internal var glassEffect: LiquidGlassView?

    /// Latest chat theme used to render this state container. Stored so
    /// subclasses' `applyUpdate` / `applyText` helpers (which run from both
    /// caller-driven `update(...)` flows and from `updateLocalizationAndTheme`)
    /// can resolve tints/colours against the chat's palette instead of
    /// falling through to the global app `theme` singleton — a chat on a
    /// custom palette would otherwise show the wrong glass tint on its
    /// state pills.
    internal var currentChatTheme: TelegramPresentationTheme?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundColor = .clear

        self.layer?.masksToBounds = false

        containerView.layer?.cornerRadius = 20
        containerView.layer?.masksToBounds = false
        containerView.isAccessibilityDecorative = true

        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: true, hasBorder: true)
        glassEffect = glass
        containerView.addSubview(glass)
        containerView.backgroundColor = .clear
        containerView.interactiveGlassView = containerView

        addSubview(containerView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let chatTheme = (theme as! TelegramPresentationTheme)
        self.currentChatTheme = chatTheme
        containerView.backgroundColor = .clear

        // Forward to the glass so its forceAppearance.didSet rebuilds the
        // inner NSGlassEffectView at the new dark/light boundary — Apple's
        // glass bakes its appearance at construction time, so toggling
        // .appearance on the existing instance leaves it visually stale.
        glassEffect?.updateLocalizationAndTheme(theme: theme)

        // Install the chat-theme tint explicitly. The default tint inside
        // `LiquidGlassView.applyAppearance` reads from the global
        // `presentation` theme; a chat on a custom palette / wallpaper
        // would otherwise show the wrong tint on this state container's
        // pill.
        glassEffect?.customTint = chatTheme.colors.background.withAlphaComponent(0.4)
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let edge: CGFloat = 12
        let contentHeight = size.height - ChatInputView.inputBottomInset
        let containerFrame = NSMakeRect(edge, 0, size.width - edge * 2, contentHeight)
        transition.updateFrame(view: containerView, frame: containerFrame)
        if let glass = glassEffect {
            transition.updateFrame(view: glass, frame: containerView.bounds)
            glass.updateLayout(size: containerView.bounds.size, transition: transition)
        }
    }

    func glassMorphSlots(visible: Bool) -> ChatInputGlassSlots? {
        guard let glass = glassEffect else {
            return nil
        }
        let frame = convert(visible ? visibleFrame(glass) : glass.frame, from: glass.superview)
        return ChatInputGlassSlots(attach: frame, text: frame, voice: frame)
    }

    func setMorphGlassHidden(_ hidden: Bool) {
        glassEffect?.isHidden = hidden
    }
}

extension ChatInputStateView: ChatInputGlassMorphing {
}


public final class ChatInputBlockView: ChatInputStateView {

    private let textView: TextView = TextView()
    private var pendingText: (text: String, context: any AccountContextProtocol)?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isSelectable = false
        textView.userInteractionEnabled = true
        containerView.addSubview(textView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(text: String, context: any AccountContextProtocol) {
        pendingText = (text, context)
        applyText()
    }

    private func applyText() {
        guard let (text, context) = pendingText else { return }
        let activeTheme = currentChatTheme ?? theme
        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(
            body: MarkdownAttributeSet(font: .normal(.text), textColor: activeTheme.colors.grayText),
            bold: MarkdownAttributeSet(font: .medium(.text), textColor: activeTheme.colors.grayText),
            link: MarkdownAttributeSet(font: .medium(.text), textColor: activeTheme.colors.link),
            linkAttribute: { link in
                return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(link, { value in
                    if value == "premium" {
                        prem(with: PremiumBoardingController(context: context), for: context.window)
                    }
                }))
            }
        )).detectBold(with: .medium(.text))

        let layout = TextViewLayout(parsed, alignment: .center)
        layout.measure(width: frame.width - 80)
        layout.interactions = LinkHooks.shared.globalLinkExecutor()
        textView.update(layout)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        applyText()
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        textView.center()
    }
}


private let actionTransitionDuration: Double = 0.2
private let actionTransitionCurve = CAMediaTimingFunction(name: .easeInEaseOut)
private let actionTitleBlurRadius: CGFloat = 8

private func animateActionTitle(_ layer: CALayer?, alphaFrom: CGFloat, alphaTo: CGFloat, blurFrom: CGFloat, blurTo: CGFloat, completion: (() -> Void)? = nil) {
    guard let layer else {
        return
    }
    layer.opacity = Float(alphaTo)
    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = alphaFrom
    opacity.toValue = alphaTo
    opacity.duration = actionTransitionDuration
    opacity.timingFunction = actionTransitionCurve
    opacity.completion = { _ in
        completion?()
    }
    layer.add(opacity, forKey: "actionTitleOpacity")

    guard let blur = ee2_makeBlurFilter() else {
        return
    }
    blur.setValue(blurTo as NSNumber, forKey: "inputRadius")
    layer.filters = [blur]
    let radius = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
    radius.fromValue = blurFrom
    radius.toValue = blurTo
    radius.duration = actionTransitionDuration
    radius.timingFunction = CAMediaTimingFunction(name: .easeOut)
    radius.completion = { [weak layer] completed in
        if completed, blurTo == 0 {
            layer?.filters = nil
        }
    }
    layer.add(radius, forKey: "actionTitleBlur")
}

func visibleFrame(_ view: NSView) -> NSRect {
    if let layer = view.layer, layer.animationKeys()?.isEmpty == false, let presentation = layer.presentation() {
        return presentation.frame
    }
    return view.frame
}

public final class ChatInputActionButtonView: ChatInputStateView {

    private let button: TextButton = TextButton()
    private var rightAddition: ImageButton?
    private var leftAddition: ImageButton?
    private var shimmerView: ShimmerEffectView?
    private var isBot: Bool = false

    /// Latest data passed to `update(...)`. Captured so `updateLocalizationAndTheme`
    /// can re-render the button text/colors and re-resolve the side icons
    /// against the new theme without needing the caller to push the data again.
    private struct PendingUpdate {
        let text: String
        let action: (ChatInteraction) -> Void
        let chatInteraction: ChatInteraction
        let isBot: Bool
        let rightAdditionData: ChatState.AdditionAction?
        let leftAdditionData: ChatState.AdditionAction?
        let accent: Bool
    }
    private var pending: PendingUpdate?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.autoSizeToFit = false
        containerView.scaleOnClick = true
        containerView.addSubview(button)
        if let glass = glassEffect {
            button.interactiveGlassTransformView = containerView
            button.interactiveGlassView = glass
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var accentButton: TextButton?
    private var outgoingTitles: [TextView] = []

    public func canUpdateInPlace(accent: Bool, rightAdditionData: ChatState.AdditionAction?, leftAdditionData: ChatState.AdditionAction?) -> Bool {
        guard let pending, !pending.isBot, !pending.accent, !accent else {
            return false
        }
        return pending.rightAdditionData?.icon == rightAdditionData?.icon && pending.leftAdditionData?.icon == leftAdditionData?.icon
    }

    override func glassMorphSlots(visible: Bool) -> ChatInputGlassSlots? {
        guard !isBot, var slots = super.glassMorphSlots(visible: visible) else {
            return nil
        }
        if let view = leftAddition {
            slots.attach = visible ? visibleFrame(view) : view.frame
        }
        if let view = rightAddition {
            slots.voice = visible ? visibleFrame(view) : view.frame
        }
        return slots
    }

    override func setMorphGlassHidden(_ hidden: Bool) {
        super.setMorphGlassHidden(hidden)
        leftAddition?.setGlassEffectHidden(hidden)
        rightAddition?.setGlassEffectHidden(hidden)
    }

    public func update(text: String, action: @escaping (ChatInteraction) -> Void, chatInteraction: ChatInteraction, isBot: Bool = false, rightAdditionData: ChatState.AdditionAction? = nil, leftAdditionData: ChatState.AdditionAction? = nil, accent: Bool = false, animated: Bool = false) {
        let previousText = pending?.text
        pending = PendingUpdate(text: text, action: action, chatInteraction: chatInteraction, isBot: isBot, rightAdditionData: rightAdditionData, leftAdditionData: leftAdditionData, accent: accent)
        if animated, let previousText, previousText != text {
            applyTitleChange(from: previousText)
        } else {
            applyUpdate()
        }
    }

    private func bindAddition(_ button: ImageButton, data: ChatState.AdditionAction, chatInteraction: ChatInteraction) {
        button.removeAllHandlers()
        button.set(handler: { [weak chatInteraction] control in
            if let chatInteraction {
                data.action(chatInteraction, control)
            }
        }, for: .Click)
    }

    private func applyTitleChange(from previousText: String) {
        guard let pending else { return }

        let activeTheme = currentChatTheme ?? theme
        let action = pending.action
        let chatInteraction = pending.chatInteraction

        button.set(text: pending.text, for: .Normal)
        button.removeAllHandlers()
        button.set(handler: { _ in
            action(chatInteraction)
        }, for: .Click)

        if let view = rightAddition, let data = pending.rightAdditionData {
            bindAddition(view, data: data, chatInteraction: chatInteraction)
        }
        if let view = leftAddition, let data = pending.leftAdditionData {
            bindAddition(view, data: data, chatInteraction: chatInteraction)
        }

        let previousContainerFrame = containerView.frame
        let visibleGlassFrame = (glassEffect?.effectView).map(visibleFrame)
        let titleAlpha: CGFloat = button.layer?.animation(forKey: "actionTitleOpacity") != nil ? CGFloat(button.layer?.presentation()?.opacity ?? 1) : 1

        updateLayout(size: frame.size, transition: .immediate)
        let containerFrame = containerView.frame
        let shift = previousContainerFrame.minX - containerFrame.minX

        for view in outgoingTitles {
            view.setFrameOrigin(NSMakePoint(view.frame.minX + shift, view.frame.minY))
        }

        if let effectView = glassEffect?.effectView, let start = visibleGlassFrame?.offsetBy(dx: shift, dy: 0), start != containerFrame.size.bounds {
            effectView.frame = start
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = actionTransitionDuration
                ctx.timingFunction = actionTransitionCurve
                ctx.allowsImplicitAnimation = true
                effectView.animator().frame = containerFrame.size.bounds
            }
        }

        let outgoing = TextView()
        outgoing.userInteractionEnabled = false
        outgoing.isSelectable = false
        outgoing.isEventLess = true
        outgoing.disableBackgroundDrawing = true
        outgoing.backgroundColor = .clear
        let layout = TextViewLayout(.initialize(string: previousText, color: activeTheme.colors.text, font: .normal(.title)), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
        layout.measure(width: .greatestFiniteMagnitude)
        outgoing.update(layout)
        outgoing.setFrameOrigin(NSMakePoint(round((containerFrame.width - outgoing.frame.width) / 2), floor((containerFrame.height - outgoing.frame.height) / 2)))
        containerView.addSubview(outgoing, positioned: .below, relativeTo: button)
        outgoingTitles.append(outgoing)

        animateActionTitle(button.layer, alphaFrom: 0, alphaTo: 1, blurFrom: actionTitleBlurRadius, blurTo: 0)
        animateActionTitle(outgoing.layer, alphaFrom: titleAlpha, alphaTo: 0, blurFrom: 0, blurTo: actionTitleBlurRadius, completion: { [weak self, weak outgoing] in
            outgoing?.removeFromSuperview()
            self?.outgoingTitles.removeAll(where: { $0 === outgoing })
        })
    }

    private func applyUpdate() {
        guard let pending else { return }

        let activeTheme = currentChatTheme ?? theme
        let chatGlassTint = activeTheme.colors.background.withAlphaComponent(0.4)

        let text = pending.text
        let action = pending.action
        let chatInteraction = pending.chatInteraction
        let isBot = pending.isBot
        let accent = pending.accent
        self.isBot = isBot

        accentButton?.removeFromSuperview()
        accentButton = nil
        shimmerView?.removeFromSuperview()
        shimmerView = nil
        rightAddition?.removeFromSuperview()
        rightAddition = nil
        leftAddition?.removeFromSuperview()
        leftAddition = nil
        button.isHidden = false
        button.removeAllHandlers()

        if isBot {
            button.style = ControlStyle(font: .medium(.title), foregroundColor: activeTheme.colors.underSelectedColor)
            button.set(text: text, for: .Normal)
            button.set(background: .clear, for: .Normal)
            button.set(background: .clear, for: .Highlight)
            button.scaleOnClick = true
            button.layer?.cornerRadius = 0

            glassEffect?.customTint = activeTheme.colors.accent

            let shimmer = ShimmerEffectView()
            shimmer.isStatic = true
            button.addSubview(shimmer)
            self.shimmerView = shimmer
        } else if accent {
            button.isHidden = true
            let ab = TextButton()
            ab.autoSizeToFit = false
            ab.set(color: activeTheme.colors.underSelectedColor, for: .Normal)
            ab.set(font: .medium(.title), for: .Normal)
            ab.set(text: text, for: .Normal)
            ab.set(background: activeTheme.colors.accent, for: .Normal)
            ab.set(background: activeTheme.colors.accent.withAlphaComponent(0.8), for: .Highlight)
            ab.scaleOnClick = true
            containerView.addSubview(ab)
            self.accentButton = ab
            if let glass = glassEffect {
                ab.interactiveGlassTransformView = containerView
                ab.interactiveGlassView = glass
            }
            ab.set(handler: { _ in
                action(chatInteraction)
            }, for: .Click)
            // The accent button's bg covers the pill; keep the underlying
            // glass tinted to the chat background so any borders/shadows
            // around it still match.
            glassEffect?.customTint = chatGlassTint
        } else {
            glassEffect?.customTint = chatGlassTint
            button.set(color: activeTheme.colors.text, for: .Normal)
            button.set(font: .normal(.title), for: .Normal)
            button.set(text: text, for: .Normal)
            button.scaleOnClick = true
            button.set(background: .clear, for: .Normal)
        }

        button.set(handler: { _ in
            action(chatInteraction)
        }, for: .Click)

        if let data = pending.rightAdditionData {
            let btn = ImageButton()
            btn.animates = false
            btn.scaleOnClick = true
            btn.set(image: data.icon.resolve(activeTheme), for: .Normal)
            btn.setAccessibilityLabel(data.icon.accessibilityLabel)
            btn.setGlassEffect(size: NSMakeSize(40, 40))
            btn.glassTintColor = chatGlassTint

            btn.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
            addSubview(btn)
            self.rightAddition = btn
            bindAddition(btn, data: data, chatInteraction: chatInteraction)
        }

        if let data = pending.leftAdditionData {
            let btn = ImageButton()
            btn.animates = false
            btn.scaleOnClick = true
            btn.set(image: data.icon.resolve(activeTheme), for: .Normal)
            btn.setAccessibilityLabel(data.icon.accessibilityLabel)
            btn.setGlassEffect(size: NSMakeSize(40, 40))
            btn.glassTintColor = chatGlassTint

            btn.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
            addSubview(btn)
            self.leftAddition = btn
            bindAddition(btn, data: data, chatInteraction: chatInteraction)
        }

        needsLayout = true
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        applyUpdate()
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let edge: CGFloat = 10
        let contentHeight = size.height - ChatInputView.inputBottomInset

        if let view = leftAddition {
            transition.updateFrame(view: view, frame: NSMakeRect(edge, 0, view.frame.width, view.frame.height))
        }
        if let view = rightAddition {
            transition.updateFrame(view: view, frame: NSMakeRect(size.width - edge - view.frame.width, 0, view.frame.width, view.frame.height))
        }

        _ = button.sizeToFit()
        _ = accentButton?.sizeToFit()

        let containerFrame: NSRect
        if isBot {
            containerFrame = NSMakeRect(edge, 0, size.width - edge * 2, contentHeight)
        } else {
            let accentExtra: CGFloat = accentButton != nil ? 80 : 0
            let textWidth = accentButton?.frame.width ?? button.frame.width
            let containerWidth = textWidth + 80 + accentExtra
            let containerX = (size.width - containerWidth) / 2
            containerFrame = NSMakeRect(containerX, 0, containerWidth, contentHeight)
        }

        transition.updateFrame(view: containerView, frame: containerFrame)
        if let glass = glassEffect {
            transition.updateFrame(view: glass, frame: containerView.bounds)
            glass.updateLayout(size: containerView.bounds.size, transition: transition)
        }

        button.sizeToFit(.zero, NSMakeSize(containerFrame.width, contentHeight), thatFit: true)
        button.center()

        if let ab = accentButton {
            let inset: CGFloat = 2
            let abFrame = NSMakeRect(inset, inset, containerFrame.width - inset * 2, containerFrame.height - inset * 2)
            transition.updateFrame(view: ab, frame: abFrame)
            ab.layer?.cornerRadius = abFrame.height / 2
        }

        if let shimmer = shimmerView {
            shimmer.frame = button.bounds
            shimmer.updateAbsoluteRect(button.bounds, within: button.frame.size)
            let shimmerRadius: CGFloat = isBot ? containerFrame.height / 2 : 10
            shimmer.layer?.cornerRadius = shimmerRadius
            shimmer.layer?.masksToBounds = true
            shimmer.update(backgroundColor: .clear, foregroundColor: .clear, shimmeringColor: NSColor.white.withAlphaComponent(0.3), shapes: [.roundedRect(rect: button.bounds, cornerRadius: shimmerRadius)], horizontal: true, size: button.frame.size)
        }
    }
}


public final class ChatInputFrozenView: ChatInputStateView {

    private let textView: TextView = TextView()
    private var pending: (action: (ChatInteraction) -> Void, chatInteraction: ChatInteraction)?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isSelectable = false
        containerView.addSubview(textView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(action: @escaping (ChatInteraction) -> Void, chatInteraction: ChatInteraction) {
        pending = (action, chatInteraction)
        applyUpdate()
    }

    private func applyUpdate() {
        guard let pending else { return }
        let activeTheme = currentChatTheme ?? theme
        let frozenText = NSMutableAttributedString()
        frozenText.append(string: strings().freezeAccountTitle, color: activeTheme.colors.redUI, font: .medium(.text))
        frozenText.append(string: "\n")
        frozenText.append(string: strings().freezeAccountClickDetails, color: activeTheme.colors.grayText, font: .normal(.small))

        let layout = TextViewLayout(frozenText, alignment: .center)
        layout.measure(width: frame.width - 80)
        textView.update(layout)

        textView.removeAllHandlers()
        textView.set(handler: { [action = pending.action, chatInteraction = pending.chatInteraction] _ in
            action(chatInteraction)
        }, for: .Click)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        applyUpdate()
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        textView.resize(containerView.frame.width - 40)
        textView.center()
    }
}


public final class ChatInputRestrictedView: ChatInputStateView {

    private let textView: TextView = TextView()
    private var pendingText: String?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        containerView.addSubview(textView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(text: String) {
        pendingText = text
        applyText()
    }

    private func applyText() {
        guard let text = pendingText else { return }
        let activeTheme = currentChatTheme ?? theme
        let layout = TextViewLayout(.initialize(string: text, color: activeTheme.colors.grayText, font: .normal(.text)), alignment: .center)
        layout.measure(width: frame.width - 80)
        textView.update(layout)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        applyText()
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        textView.center()
    }
}


public final class ChatInputDiscussionView: ChatInputStateView {

    private let discussionView: ChannelDiscussionInputView

    public required init(frame frameRect: NSRect) {
        self.discussionView = ChannelDiscussionInputView(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        discussionView.backgroundColor = .clear
        containerView.addSubview(discussionView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(chatInteraction: ChatInteraction, discussionGroupId: PeerId?, leftAction: String, rightAction: String) {
        discussionView.update(with: chatInteraction, discussionGroupId: discussionGroupId, leftAction: leftAction, rightAction: rightAction)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        discussionView.updateLocalizationAndTheme(theme: theme)
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        transition.updateFrame(view: discussionView, frame: containerView.bounds)
        discussionView.needsLayout = true
    }
}
