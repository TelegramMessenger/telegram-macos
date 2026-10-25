import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
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
import MessageTextUtils

/// Standalone 40×40 glass-pill view that shows a centered `ProgressIndicator`.
/// Used as the action-button while inline bot context loads — mirrors the
/// look of `send` / `voice` / `inlineCancel` (which are ImageButtons with
/// `setGlassEffect`) but hosts a spinner instead of an icon.
public final class InlineProgressView: Control {
    private let glass: LiquidGlassView
    public let progress: ProgressIndicator

    public required init(frame frameRect: NSRect) {
        let radius: CGFloat = 999
        let size = frameRect.size == .zero ? NSMakeSize(40, 40) : frameRect.size
        self.glass = LiquidGlassView(frame: size.bounds, cornerRadius: radius, hasShadow: true, hasBorder: true)
        self.progress = ProgressIndicator(frame: NSMakeRect(0, 0, 22, 22))
        super.init(frame: NSRect(origin: frameRect.origin, size: size))
        self.layer?.masksToBounds = false
        self.scaleOnClick = true
        self.interactiveGlassView = self.glass
        addSubview(self.glass)
        addSubview(self.progress)
        self.progress.progressColor = theme.colors.text
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        progress.center()
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        progress.progressColor = theme.colors.grayIcon
    }
}

final class ChatAccessibleImageButton: ImageButton {
    var accessibilityLabelProvider: (() -> String?)?
    var accessibilityPress: (() -> Void)?

    override var accessibilityDefaultLabel: String? {
        return accessibilityLabelProvider?()
    }

    override func isAccessibilityElement() -> Bool {
        if accessibilityPress != nil {
            return TGUIKitAccessibility.isEnabled && !isAccessibilityDecorative && !isHidden
        }
        return super.isAccessibilityElement()
    }

    override func accessibilityPerformPress() -> Bool {
        if let accessibilityPress {
            accessibilityPress()
            return true
        }
        return super.accessibilityPerformPress()
    }
}

public final class ChatInputSendButton: View {

    public struct State: Equatable {
        public enum Kind: Equatable {
            case voice
            case stop
            case send
            case slowMode(text: String, isBoost: Bool)
            case inlineCancel
            case paidStars(amount: Int64)
        }
        public var kind: Kind
        public var isEditing: Bool
        public var isSendEnabled: Bool
        public var isInlineLoading: Bool

        public static let initial = State(kind: .voice, isEditing: false, isSendEnabled: true, isInlineLoading: false)
    }

    public let send: ImageButton = ChatAccessibleImageButton()
    public let voice: ImageButton = ChatAccessibleImageButton()
    private let voiceIcon = ChatInputRecordModeIcon(frame: NSMakeRect(5, 5, ChatInputRecordModeIcon.canvasSize.width, ChatInputRecordModeIcon.canvasSize.height))
    public let stop: ImageButton = ImageButton()
    public let slowModeTimeout: TextButton = TextButton()
    public let inlineCancel: ImageButton = ImageButton()
    public var inlineProgress: InlineProgressView? = nil
    public var sendPaidMessages: StarsSendActionView?

    public static let fieldSize = NSMakeSize(40, 32)
    public static let fieldInset: CGFloat = 4
    public static let fieldTextGap: CGFloat = 6
    public static let fieldMotionDuration: Double = 0.22
    private static let fieldSpringStiffness: CGFloat = 555.027
    private static let fieldSpringDamping: CGFloat = 47.118
    private static let fieldCollapsedScale: CGFloat = 0.1
    private static let fieldBlurRadius: CGFloat = 6
    private static let fieldBlurDuration: Double = 0.15
    private static let fieldFadeDuration: Double = 0.08
    private static let planeFlightOffset = NSMakePoint(-22, 18)
    private static let iconMorphDuration: Double = 0.2
    private static let iconMorphScale: CGFloat = 0.2

    private let chatInteraction: ChatInteraction
    private var state: State = .initial
    private var activeView: View
    private var first: Bool = true

    public var isInField: Bool {
        return isFieldAction(activeView)
    }

    private func isFieldAction(_ view: View) -> Bool {
        return view === send || view is StarsSendActionView
    }

    public var hasAppliedState: Bool {
        return !first
    }

    public init(frame frameRect: NSRect, chatInteraction: ChatInteraction) {
        self.chatInteraction = chatInteraction
        self.activeView = self.voice
        super.init(frame: frameRect)

        self.layer?.masksToBounds = false

        addSubview(send)
        addSubview(voice)
        addSubview(stop)
        addSubview(inlineCancel)
        addSubview(slowModeTimeout)

        voiceIcon.isEventLess = true
        voice.addSubview(voiceIcon)

        stop.isHidden = true
        inlineCancel.isHidden = true
        send.isHidden = true
        slowModeTimeout.isHidden = true

        voice.autohighlight = false
        stop.autohighlight = false
        send.autohighlight = false
        stop.scaleOnClick = true
        send.scaleOnClick = true
        slowModeTimeout.scaleOnClick = true
        inlineCancel.scaleOnClick = true

        stop.setAccessibilityLabel(strings().voiceOverChatStop)
        inlineCancel.setAccessibilityLabel(strings().voiceOverCommonCancel)
        (send as? ChatAccessibleImageButton)?.accessibilityLabelProvider = { [weak self] in
            return self?.state.isEditing == true ? strings().voiceOverCommonDone : strings().voiceOverMessageContextSend
        }
        (voice as? ChatAccessibleImageButton)?.accessibilityLabelProvider = {
            return FastSettings.recordingState == .voice ? strings().voiceOverChatRecordModeVoiceMessage : strings().voiceOverChatRecordModeVideoMessage
        }
        voice.setAccessibilityHelp(strings().voiceOverChatRecordModeHint)
        let recordActionName = strings().voiceOverChatRecord
        voice.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: recordActionName, handler: { [weak self] in
            self?.chatInteraction.startRecording(true, nil)
            return true
        })])

        voice.set(handler: { [weak self] _ in
            guard let self else { return }
            FastSettings.toggleRecordingState()
            self.updateVoiceIcon(animated: true)
            getAppTooltip(for: FastSettings.recordingState == .voice ? .voiceRecording : .videoRecording, callback: { value in
                tooltip(for: self.voice, text: value)
            })
        }, for: .Click)

        voice.set(handler: { [weak self] control in
            self?.chatInteraction.startRecording(false, control)
        }, for: .LongMouseDown)

        inlineCancel.set(handler: { [weak self] _ in
            if let inputContext = self?.chatInteraction.presentation.inputContext, case let .contextRequest(_, query) = inputContext {
                if query.isEmpty {
                    self?.chatInteraction.clearInput()
                } else {
                    self?.chatInteraction.clearContextQuery()
                }
            }
        }, for: .Up)

        updateLocalizationAndTheme(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)

        let icon = chatInteraction.presentation.state == .editing ? theme.icons.chat_header_done : theme.icons.send_message_large
        send.set(image: icon, for: .Normal)
        send.set(background: theme.colors.accent, for: .Normal)
        send.set(background: theme.colors.accent.withAlphaComponent(0.8), for: .Highlight)
        send.sizeToFit(.zero, ChatInputSendButton.fieldSize, thatFit: true)
        send.layer?.cornerRadius = ChatInputSendButton.fieldSize.height / 2
        send.layer?.masksToBounds = false

        voice.setGlassEffect(size: NSMakeSize(40, 40))
        voice.setFrameSize(NSMakeSize(40, 40))
        voice.updateLayout()
        updateVoiceIcon(animated: false)

        let stopIcon = generateImage(NSMakeSize(14, 14), contextGenerator: { size, context in
            context.clear(size.bounds)
            context.setFillColor(theme.colors.text.cgColor)
            context.addPath(CGPath(roundedRect: size.bounds, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.fillPath()
        })!
        stop.set(image: stopIcon, for: .Normal)
        stop.setGlassEffect(size: NSMakeSize(40, 40))
        stop.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)

        inlineCancel.set(image: theme.icons.chatInlineDismiss, for: .Normal)
        _ = inlineCancel.sizeToFit()
    }

    private func updateVoiceIcon(animated: Bool) {
        voice.removeImage(for: .Normal)
        voiceIcon.isHidden = false
        voiceIcon.update(state: FastSettings.recordingState, color: theme.colors.text, animated: animated)
    }

    public func prepare(with chatInteraction: ChatInteraction) {
        let showMenu: (Control) -> Void = { control in
            if let event = NSApp.currentEvent {
                let sendMenu = chatInteraction.sendMessageMenu(false) |> deliverOnMainQueue
                _ = sendMenu.startStandalone(next: { menu in
                    if let menu {
                        AppMenu.show(menu: menu, event: event, for: control)
                    }
                })
            }
        }

        send.set(handler: { control in
            showMenu(control)
        }, for: .RightDown)

        send.set(handler: { control in
            showMenu(control)
        }, for: .LongMouseDown)

        send.set(handler: { [weak self] control in
            guard let interaction = self?.chatInteraction else { return }
            interaction.sendMessage(false, nil, interaction.presentation.messageEffect)
        }, for: .Click)

        stop.set(handler: { [weak chatInteraction] _ in
            guard let chatInteraction else {
                return
            }
            _ = chatInteraction.interactionContext.engine.messages.stopIncomingTypingDraft(
                peerId: chatInteraction.peerId,
                threadId: chatInteraction.chatLocation.threadId
            ).startStandalone()
        }, for: .Click)

        slowModeTimeout.set(handler: { [weak chatInteraction] control in
            if let chatInteraction = chatInteraction {
                if let totalBoostNeed = chatInteraction.presentation.totalBoostNeed {
                    chatInteraction.boostToUnrestrict(.unblockSlowmode(totalBoostNeed))
                } else {
                    if let slowMode = chatInteraction.presentation.slowMode {
                        showSlowModeTimeoutTooltip(slowMode, for: control)
                    }
                }
            }
        }, for: .Click)
    }

    public var currentActionView: NSView {
        if !stop.isHidden {
            return stop
        }
        if let inlineProgress, !inlineProgress.isHidden {
            return inlineProgress
        }
        if let sendPaidMessages {
            return sendPaidMessages
        } else if !send.isHidden {
            return send
        } else if !voice.isHidden {
            return voice
        } else if !slowModeTimeout.isHidden {
            return slowModeTimeout
        } else {
            return self
        }
    }

    public var canSend: Bool {
        if let superview = superview, let window = window {
            let mouse = superview.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            return NSPointInRect(mouse, superview.frame)
        }
        return false
    }

    public var desiredSize: NSSize {
        if let sendPaidMessages, activeView === sendPaidMessages {
            return NSMakeSize(sendPaidMessages.frame.width, 40)
        }
        if case .slowMode = state.kind {
            return NSMakeSize(max(40, slowModeTimeout.frame.width), 40)
        }
        return NSMakeSize(40, 40)
    }

    @discardableResult
    public func update(state: State, animated: Bool) -> Bool {
        let oldState = self.state
        let oldDesired = desiredSize
        self.state = state

        let previousIcon = send.imageView.image
        let previousIconFrame = send.imageView.frame
        let morphsIcon = animated && !first && oldState.isEditing != state.isEditing && oldState.kind == .send && state.kind == .send
        send.animates = false
        send.set(image: state.isEditing ? theme.icons.chat_header_done : theme.icons.send_message_large, for: .Normal)
        send.sizeToFit(.zero, ChatInputSendButton.fieldSize, thatFit: true)
        stop.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        send.animates = true
        send.isEnabled = state.isSendEnabled

        if case .slowMode(let text, let isBoost) = state.kind {
            slowModeTimeout.set(text: text, for: .Normal)
            slowModeTimeout.set(font: .normalMonospaced(.text), for: .Normal)
            slowModeTimeout.autoSizeToFit = false
            slowModeTimeout.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, 40), thatFit: false)
            slowModeTimeout.layer?.cornerRadius = 20
            slowModeTimeout.set(background: .clear, for: .Normal)
            if isBoost {
                slowModeTimeout.setGlassEffect(size: NSMakeSize(slowModeTimeout.frame.width, 40), tintColor: premiumGradient[1])
                slowModeTimeout.glassTintColor = premiumGradient[1]
                slowModeTimeout.set(color: .white, for: .Normal)
            } else {
                slowModeTimeout.setGlassEffectHidden(true)
                slowModeTimeout.set(color: theme.colors.grayIcon, for: .Normal)
            }
        }

        if case .paidStars(let amount) = state.kind {
            let current: StarsSendActionView
            if let view = sendPaidMessages {
                current = view
            } else {
                current = StarsSendActionView(frame: .zero)
                current.setAccessibilityLabel(strings().voiceOverMessageContextSend)
                addSubview(current)
                self.sendPaidMessages = current
                current.setSingle(handler: { [weak self] _ in
                    self?.send.send(event: .Click)
                }, for: .Click)
            }
            current.update(price: amount, context: chatInteraction.interactionContext, animated: animated)
        } else if let view = sendPaidMessages {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.sendPaidMessages = nil
        }

        if state.isInlineLoading, inlineProgress == nil {
            let progress = InlineProgressView(frame: NSMakeRect(0, 0, 40, 40))
            progress.setAccessibilityLabel(strings().voiceOverCommonCancel)
            progress.setAccessibilityValue(strings().voiceOverCommonLoading)
            progress.isHidden = true
            addSubview(progress, positioned: .below, relativeTo: inlineCancel)
            progress.set(handler: { [weak self] _ in
                if let inputContext = self?.chatInteraction.presentation.inputContext, case let .contextRequest(_, query) = inputContext {
                    if query.isEmpty {
                        self?.chatInteraction.clearInput()
                    } else {
                        self?.chatInteraction.clearContextQuery()
                    }
                }
            }, for: .Click)
            inlineProgress = progress
        }

        let newView: View
        if case .stop = state.kind {
            newView = stop
        } else if state.isInlineLoading, let progress = inlineProgress {
            newView = progress
        } else {
            switch state.kind {
            case .voice: newView = voice
            case .stop: newView = stop
            case .send: newView = send
            case .slowMode: newView = slowModeTimeout
            case .inlineCancel: newView = inlineCancel
            case .paidStars: newView = sendPaidMessages ?? send
            }
        }

        let kindChanged = oldState.kind != state.kind || oldState.isInlineLoading != state.isInlineLoading
        if first || kindChanged || activeView !== newView {
            let prevView = activeView
            activeView = newView
            let anim = animated && !first && prevView !== newView
            first = false

            newView.isHidden = false
            newView.layer?.opacity = 1.0
            if prevView !== newView {
                prevView.layer?.opacity = 0.0
            }
            if anim {
                let isFieldTransition = isFieldAction(newView) || isFieldAction(prevView)
                if isFieldTransition {
                    newView.layer?.animateAlpha(from: 0.0, to: 1.0, duration: ChatInputSendButton.fieldFadeDuration)
                    if isFieldAction(newView) {
                        animateFieldTransition(newView, appearing: true)
                        if newView === send && !state.isEditing {
                            animatePlaneFlight()
                        }
                    }
                    if isFieldAction(prevView) {
                        animateFieldTransition(prevView, appearing: false)
                    }
                } else {
                    newView.layer?.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                    newView.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.6)
                }
                prevView.layer?.animateAlpha(from: 1.0, to: 0.0, duration: isFieldTransition ? ChatInputSendButton.fieldFadeDuration : 0.2, completion: { [weak prevView] complete in
                    if complete {
                        prevView?.isHidden = true
                    }
                })
            } else if prevView !== newView {
                prevView.isHidden = true
            }
        }

        if morphsIcon, let previousIcon {
            animateSendIconChange(from: previousIcon, frame: previousIconFrame)
        }

        needsLayout = true
        return desiredSize != oldDesired
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        for subview in subviews {
            let subSize: NSSize
            if subview === slowModeTimeout {
                subSize = NSMakeSize(size.width, 40)
            } else {
                subSize = subview.frame.size
            }
            let frame = NSMakeRect((size.width - subSize.width) / 2, (size.height - subSize.height) / 2, subSize.width, subSize.height)
            transition.updateFrame(view: subview, frame: frame)
        }
    }

    private func animateFieldTransition(_ view: NSView, appearing: Bool) {
        guard let layer = view.layer else {
            return
        }
        let bounds = layer.bounds
        var collapsed = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        collapsed = CATransform3DScale(collapsed, ChatInputSendButton.fieldCollapsedScale, ChatInputSendButton.fieldCollapsedScale, 1)
        collapsed = CATransform3DTranslate(collapsed, -bounds.midX, -bounds.midY, 0)

        let target = appearing ? CATransform3DIdentity : collapsed
        let running = layer.animation(forKey: "transform") != nil ? layer.presentation()?.transform : nil
        let scale = CASpringAnimation(keyPath: "transform")
        scale.mass = 1
        scale.stiffness = ChatInputSendButton.fieldSpringStiffness
        scale.damping = ChatInputSendButton.fieldSpringDamping
        scale.fromValue = NSValue(caTransform3D: running ?? (appearing ? collapsed : CATransform3DIdentity))
        scale.toValue = NSValue(caTransform3D: target)
        scale.duration = scale.settlingDuration
        layer.add(scale, forKey: "transform")

        guard let blur = ee2_makeBlurFilter() else {
            return
        }
        blur.setValue(0.0 as NSNumber, forKey: "inputRadius")
        layer.filters = [blur]
        let animation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
        animation.fromValue = appearing ? ChatInputSendButton.fieldBlurRadius : 0.0
        animation.toValue = appearing ? 0.0 : ChatInputSendButton.fieldBlurRadius
        animation.duration = ChatInputSendButton.fieldBlurDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.completion = { [weak layer] completed in
            if completed {
                layer?.filters = nil
            }
        }
        layer.add(animation, forKey: "fieldTransitionBlur")
    }

    private func animatePlaneFlight() {
        guard let layer = send.imageView.layer else {
            return
        }
        let flight = CASpringAnimation(keyPath: "position")
        flight.mass = 1
        flight.stiffness = ChatInputSendButton.fieldSpringStiffness
        flight.damping = ChatInputSendButton.fieldSpringDamping
        flight.fromValue = NSValue(point: ChatInputSendButton.planeFlightOffset)
        flight.toValue = NSValue(point: .zero)
        flight.isAdditive = true
        flight.duration = flight.settlingDuration
        layer.add(flight, forKey: "planeFlight")
    }

    private func animateSendIconChange(from previous: CGImage, frame: NSRect) {
        guard let buttonLayer = send.layer, let iconLayer = send.imageView.layer else {
            return
        }
        let duration = ChatInputSendButton.iconMorphDuration
        let scale = ChatInputSendButton.iconMorphScale

        let outgoing = CALayer()
        outgoing.contents = previous
        outgoing.contentsGravity = .resizeAspect
        outgoing.contentsScale = System.backingScale
        outgoing.frame = frame
        outgoing.opacity = 0
        buttonLayer.addSublayer(outgoing)

        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = scale
        shrink.duration = duration
        shrink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        outgoing.add(shrink, forKey: "sendIconMorphScale")
        outgoing.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: .easeInEaseOut, completion: { [weak outgoing] _ in
            outgoing?.removeFromSuperlayer()
        })

        iconLayer.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: .easeInEaseOut)
        iconLayer.animateScaleCenter(from: scale, to: 1, duration: duration)
    }

    public func setMediaActionInnerGlassHidden(_ hidden: Bool) {
        voice.setGlassEffectHidden(hidden)
        stop.setGlassEffectHidden(hidden)
    }

    public func setSharedGlassGhost(_ ghost: NSView?) {
        voice.additionalGlassEffectView = ghost
        stop.additionalGlassEffectView = ghost
    }
}
