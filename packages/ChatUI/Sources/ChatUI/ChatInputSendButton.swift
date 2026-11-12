import Cocoa
import AppAnalytics
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
    private let dictationWaveform = ChatDictationWaveformView(frame: NSMakeRect(7, 5, 26, 22))
    private var isDictating = false {
        didSet {
            if oldValue != isDictating {
                updateDictationBubble()
            }
        }
    }
    private var dictationBubble: ChatDictationBubble?
    private var dictationTransitionIcon: CALayer?
    private var outgoingDictationWaveform: CALayer?
    private var aiRewriteAvailable = false
    private var aiRewriteInProgress = false
    private var aiRewriteSparkles: CALayer?
    private var shouldFinishDictationTransition = false
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
        send.addSubview(dictationWaveform)
        dictationWaveform.isHidden = true
        dictationWaveform.animationsEnabled = !chatInteraction.context.isLite(.animations)

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
            if self?.isDictating == true {
                return strings().voiceOverCommonDone
            }
            return self?.state.isEditing == true ? strings().voiceOverCommonDone : strings().voiceOverMessageContextSend
        }
        (voice as? ChatAccessibleImageButton)?.accessibilityLabelProvider = {
            return FastSettings.recordingState == .voice ? strings().voiceOverChatRecordModeVoiceMessage : strings().voiceOverChatRecordModeVideoMessage
        }
        voice.setAccessibilityHelp(strings().voiceOverChatRecordModeHint)
        voice.contextMenu = { [weak self] in
            self?.chatInteraction.voiceTranscription?.languageMenu()
        }
        let recordActionName = strings().voiceOverChatRecord
        voice.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: recordActionName, handler: { [weak self] in
            self?.chatInteraction.startRecordingObserved(true, nil, via: nil)
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
            self?.chatInteraction.startRecordingObserved(false, control, via: .longPress)
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
        if let dictationBubble {
            dictationBubble.setColor(theme.colors.accent)
            send.set(background: .clear, for: .Normal)
            send.set(background: .clear, for: .Highlight)
        } else {
            send.set(background: theme.colors.accent, for: .Normal)
            send.set(background: theme.colors.accent.withAlphaComponent(0.8), for: .Highlight)
        }
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
        updateDictationAppearance()
    }

    func setDictating(_ value: Bool, animated: Bool = false) {
        guard isDictating != value else { return }
        let outgoing = !value && animated && window != nil && !chatInteraction.context.isLite(.animations)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? dictationWaveform.transitionLayer() : nil
        cancelDictationTransition()
        isDictating = value
        dictationWaveform.reset()
        if value {
            send.layer?.removeAllAnimations()
            send.layer?.filters = nil
            update(state: State(kind: .send, isEditing: false, isSendEnabled: true, isInlineLoading: false), animated: false)
        }
        updateDictationAppearance()
        if let outgoing, let layer = send.layer {
            outgoingDictationWaveform = outgoing
            shouldFinishDictationTransition = true
            layer.addSublayer(outgoing)
        }
    }

    func setAIRewriteAvailable(_ available: Bool) {
        aiRewriteAvailable = available
        updateAIRewriteSparkles()
    }

    func setAIRewriteInProgress(_ inProgress: Bool) {
        aiRewriteInProgress = inProgress
        updateAIRewriteSparkles()
    }

    private func updateAIRewriteSparkles() {
        guard aiRewriteAvailable, !aiRewriteInProgress, !isDictating, !state.isEditing,
              activeView === send, let buttonLayer = send.layer else {
            aiRewriteSparkles?.removeFromSuperlayer()
            aiRewriteSparkles = nil
            return
        }
        guard aiRewriteSparkles == nil else { return }
        let group = CALayer()
        let points: [(CGFloat, CGFloat, CGFloat)] = [(-10, -5, 1.7), (9, 7, 1.5), (10, -7, 1.0), (-7, 8, 1.0)]
        for (index, point) in points.enumerated() {
            let (x, y, size) = point
            let shape = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -size))
            path.addQuadCurve(to: CGPoint(x: size, y: 0), control: .zero)
            path.addQuadCurve(to: CGPoint(x: 0, y: size), control: .zero)
            path.addQuadCurve(to: CGPoint(x: -size, y: 0), control: .zero)
            path.addQuadCurve(to: CGPoint(x: 0, y: -size), control: .zero)
            shape.path = path
            shape.fillColor = NSColor.white.cgColor
            shape.position = CGPoint(x: x, y: y)
            shape.opacity = 0.72
            group.addSublayer(shape)
            if !chatInteraction.context.isLite(.animations), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let twinkle = CAKeyframeAnimation(keyPath: "opacity")
                twinkle.values = [0.22, 1, 0.22]
                twinkle.duration = 1.4
                twinkle.timeOffset = Double(index) * 0.27
                twinkle.repeatCount = .infinity
                shape.add(twinkle, forKey: "twinkle")
            }
        }
        group.position = CGPoint(x: send.bounds.midX, y: send.bounds.midY)
        buttonLayer.addSublayer(group)
        aiRewriteSparkles = group
    }

    private func finishDictationTransition() {
        guard shouldFinishDictationTransition, let outgoing = outgoingDictationWaveform else { return }
        shouldFinishDictationTransition = false
        guard activeView === send else {
            outgoing.removeFromSuperlayer()
            outgoingDictationWaveform = nil
            return
        }
        outgoing.opacity = 0
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.4
        shrink.duration = 0.16
        shrink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        outgoing.add(shrink, forKey: "dictationWavesShrink")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.completion = { [weak self, weak outgoing] _ in
            outgoing?.removeFromSuperlayer()
            if self?.outgoingDictationWaveform === outgoing {
                self?.outgoingDictationWaveform = nil
            }
        }
        outgoing.add(fade, forKey: "dictationWavesFade")
        if let iconLayer = send.imageView.layer {
            let reveal = CABasicAnimation(keyPath: "opacity")
            reveal.fromValue = 0
            reveal.toValue = 1
            reveal.duration = 0.2
            reveal.beginTime = iconLayer.convertTime(CACurrentMediaTime(), from: nil) + 0.04
            reveal.fillMode = .backwards
            reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
            iconLayer.add(reveal, forKey: "dictationPlaneReveal")
        }
        if !state.isEditing {
            animatePlaneFlight()
        }
    }

    func animateDictationTransition(from origin: ChatDictationButtonOrigin) {
        cancelDictationTransition()
        guard isDictating, !chatInteraction.context.isLite(.animations),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window, let host = send.superview, let buttonLayer = send.layer,
              let waveLayer = dictationWaveform.layer else { return }
        layoutSubtreeIfNeeded()
        let source = host.convert(window.convertFromScreen(origin.screenFrame), from: nil)
        guard source.width > 0, source.height > 0,
              source.minX.isFinite, source.minY.isFinite, source.width.isFinite, source.height.isFinite else { return }
        let bounds = buttonLayer.bounds
        let sourceBounds = CGRect(origin: bounds.origin, size: source.size)
        let sourcePosition = CGPoint(x: source.minX + source.width * buttonLayer.anchorPoint.x,
                                     y: source.minY + source.height * buttonLayer.anchorPoint.y)
        func spring(_ keyPath: String, from: Any, to: Any) -> CASpringAnimation {
            let animation = CASpringAnimation(keyPath: keyPath)
            animation.mass = 1
            animation.stiffness = ChatInputSendButton.fieldSpringStiffness
            animation.damping = ChatInputSendButton.fieldSpringDamping
            animation.fromValue = from
            animation.toValue = to
            animation.duration = animation.settlingDuration
            return animation
        }
        let distance = CGPoint(x: sourcePosition.x - buttonLayer.position.x, y: sourcePosition.y - buttonLayer.position.y)
        let position = spring("position", from: NSValue(point: distance), to: NSValue(point: .zero))
        position.isAdditive = true
        let size = spring("bounds", from: NSValue(rect: sourceBounds), to: NSValue(rect: bounds))
        let radius = spring("cornerRadius", from: min(source.width, source.height) / 2, to: buttonLayer.cornerRadius)
        let flight = CAAnimationGroup()
        flight.animations = [position, size, radius]
        flight.duration = position.duration
        buttonLayer.add(flight, forKey: "dictationFlight")

        let offset = CGPoint(x: sourceBounds.midX - bounds.midX, y: sourceBounds.midY - bounds.midY)
        let wavePosition = spring("position", from: NSValue(point: offset), to: NSValue(point: .zero))
        wavePosition.isAdditive = true
        waveLayer.add(wavePosition, forKey: "dictationFlight")
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 0
        reveal.toValue = 1
        reveal.duration = 0.2
        reveal.beginTime = waveLayer.convertTime(CACurrentMediaTime(), from: nil) + 0.06
        reveal.fillMode = .backwards
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        waveLayer.add(reveal, forKey: "dictationReveal")

        if let icon = origin.icon {
            let outgoing = CALayer()
            outgoing.contents = icon
            outgoing.contentsGravity = .resizeAspect
            outgoing.contentsScale = window.backingScaleFactor
            outgoing.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
            outgoing.position = CGPoint(x: bounds.midX, y: bounds.midY)
            outgoing.opacity = 0
            buttonLayer.addSublayer(outgoing)
            dictationTransitionIcon = outgoing
            outgoing.add(spring("position", from: NSValue(point: CGPoint(x: sourceBounds.midX, y: sourceBounds.midY)), to: NSValue(point: outgoing.position)), forKey: "dictationFlight")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.2
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fade.completion = { [weak self, weak outgoing] _ in
                outgoing?.removeFromSuperlayer()
                if self?.dictationTransitionIcon === outgoing {
                    self?.dictationTransitionIcon = nil
                }
            }
            outgoing.add(fade, forKey: "dictationFade")
        }
    }

    private func cancelDictationTransition() {
        send.layer?.removeAnimation(forKey: "dictationFlight")
        dictationWaveform.layer?.removeAnimation(forKey: "dictationFlight")
        dictationWaveform.layer?.removeAnimation(forKey: "dictationReveal")
        dictationTransitionIcon?.removeFromSuperlayer()
        dictationTransitionIcon = nil
        outgoingDictationWaveform?.removeFromSuperlayer()
        outgoingDictationWaveform = nil
        shouldFinishDictationTransition = false
        send.imageView.layer?.removeAnimation(forKey: "dictationPlaneReveal")
        send.imageView.layer?.removeAnimation(forKey: "planeFlight")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelDictationTransition()
        }
    }

    func updateDictationLevel(_ level: CGFloat) {
        guard isDictating else { return }
        dictationWaveform.updateLevel(level)
        dictationBubble?.update(level: level)
    }

    private func updateDictationBubble() {
        let animated = !chatInteraction.context.isLite(.animations) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if isDictating, animated {
            let bubble = dictationBubble ?? ChatDictationBubble(host: send)
            dictationBubble = bubble
            bubble.start(color: theme.colors.accent)
            send.set(background: .clear, for: .Normal)
            send.set(background: .clear, for: .Highlight)
        } else if let bubble = dictationBubble {
            dictationBubble = nil
            bubble.stop { [weak self] in
                guard let self, self.dictationBubble == nil else { return }
                self.send.set(background: theme.colors.accent, for: .Normal)
                self.send.set(background: theme.colors.accent.withAlphaComponent(0.8), for: .Highlight)
            }
        }
    }

    private func updateDictationAppearance() {
        send.imageView.isHidden = isDictating
        dictationWaveform.isHidden = !isDictating
        send.appTooltip = isDictating ? strings().voiceOverCommonDone : nil
    }

    private func updateVoiceIcon(animated: Bool) {
        voice.appTooltip = FastSettings.recordingState == .voice ? strings().appTooltipVoiceRecord : strings().appTooltipVideoRecord
        voice.removeImage(for: .Normal)
        voiceIcon.isHidden = false
        voiceIcon.update(state: FastSettings.recordingState, color: theme.colors.text, animated: animated)
    }

    public func prepare(with chatInteraction: ChatInteraction) {
        let showMenu: (Control) -> Void = { [weak self] control in
            if let event = NSApp.currentEvent {
                if self?.isDictating == true {
                    if let menu = chatInteraction.voiceTranscription?.languageMenu() {
                        AppMenu.show(menu: menu, event: event, for: control)
                    }
                    return
                }
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
            self?.activateSend()
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

    private func activateSend() {
        if isDictating {
            chatInteraction.voiceTranscription?.perform(.edit)
        } else {
            chatInteraction.sendMessage(false, nil, chatInteraction.presentation.messageEffect)
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
        updateDictationAppearance()
        finishDictationTransition()
        updateAIRewriteSparkles()
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
