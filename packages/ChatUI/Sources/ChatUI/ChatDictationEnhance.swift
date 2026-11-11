import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramTheme
import Localization
import InputView
import InputDataUI
import AppAnalytics
import TelegramContext
import InlineStickerLayer
import LocalAnimations

final class ChatDictationEnhanceView: Control {
    static let height: CGFloat = 28
    private static let inset: CGFloat = 12
    private static let spacing: CGFloat = 5
    private static let iconSide: CGFloat = 16
    private static let bandWidth: CGFloat = 46
    private static let dividerGap: CGFloat = 8
    private static let chevronSize = NSMakeSize(4.5, 8)
    private static let chevronInset: CGFloat = 11

    private let glass = LiquidGlassView(frame: .zero, cornerRadius: ChatDictationEnhanceView.height / 2, hasShadow: true, hasBorder: true)
    private let effects = View()
    private let icon = ImageView()
    private let label = TextView()
    private let sheenMask = CAShapeLayer()
    private let sheen = CALayer()
    private let sheenBand = CAGradientLayer()
    private let outlineMask = CAShapeLayer()
    private let outline = CALayer()
    private let outlineBand = CAGradientLayer()
    private let divider = CALayer()
    private let chevron = CAShapeLayer()
    private var textColor: NSColor = .white
    private(set) var accentColor: NSColor = .systemBlue
    private var appliedSweep: (working: Bool, width: CGFloat)?
    private(set) var isWorking = false
    var anchor: ((NSView) -> CGFloat?)?
    var onEnhance: (() -> Void)?
    var onStyles: ((NSEvent) -> Void)?

    private var dividerX: CGFloat {
        return label.frame.maxX + Self.dividerGap
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        scaleOnClick = true
        interactiveGlassView = glass
        addSubview(glass)
        addSubview(effects)
        addSubview(icon)
        addSubview(label)
        label.userInteractionEnabled = false
        label.isSelectable = false
        icon.contentGravity = .resizeAspect

        let clear = NSColor.white.withAlphaComponent(0).cgColor
        sheenBand.startPoint = CGPoint(x: 0, y: 0.5)
        sheenBand.endPoint = CGPoint(x: 1, y: 0.5)
        sheenBand.colors = [clear, NSColor.white.withAlphaComponent(0.28).cgColor, clear]
        sheen.mask = sheenMask
        sheen.addSublayer(sheenBand)

        outlineMask.fillColor = nil
        outlineMask.strokeColor = NSColor.black.cgColor
        outlineMask.lineWidth = 1.5
        outlineBand.startPoint = CGPoint(x: 0, y: 0.5)
        outlineBand.endPoint = CGPoint(x: 1, y: 0.5)
        outlineBand.colors = [clear, NSColor.white.withAlphaComponent(0.85).cgColor, clear]
        outline.mask = outlineMask
        outline.addSublayer(outlineBand)

        chevron.fillColor = nil
        chevron.lineWidth = 1.6
        chevron.lineCap = .round
        chevron.lineJoin = .round

        effects.layer?.addSublayer(sheen)
        effects.layer?.addSublayer(outline)
        effects.layer?.addSublayer(divider)
        effects.layer?.addSublayer(chevron)

        set(handler: { [weak self] _ in
            guard let self, !self.isWorking else { return }
            if let event = NSApp.currentEvent, self.convert(event.locationInWindow, from: nil).x >= self.dividerX - 2, let onStyles = self.onStyles {
                onStyles(event)
            } else {
                self.onEnhance?()
            }
        }, for: .Click)
        setAccessibilityRole(.button)
        updateLocalizationAndTheme(theme: theme)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        textColor = theme.colors.underSelectedColor
        accentColor = theme.colors.accent
        glass.customTint = theme.colors.accent
        divider.backgroundColor = textColor.withAlphaComponent(0.35).cgColor
        chevron.strokeColor = textColor.cgColor
        icon.image = TelegramThemeHooks.shared.image(.iconAiInput).precomposed(textColor)
        let layout = TextViewLayout(.initialize(string: strings().chatInputDictationEnhance, color: textColor, font: .medium(12.5)), maximumNumberOfLines: 1)
        layout.measure(width: 300)
        label.update(layout)
        setAccessibilityLabel(isWorking ? strings().chatInputDictationEnhancing : strings().chatInputDictationEnhanceAccessibility)
        setFrameSize(NSMakeSize(ceil(Self.inset + Self.iconSide + Self.spacing + layout.layoutSize.width + Self.dividerGap + 1 + Self.chevronInset * 2 + Self.chevronSize.width - 2), Self.height))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        effects.frame = bounds
        icon.frame = NSMakeRect(Self.inset, floorToScreenPixels(backingScaleFactor, (frame.height - Self.iconSide) / 2), Self.iconSide, Self.iconSide)
        label.setFrameOrigin(NSMakePoint(icon.frame.maxX + Self.spacing, floorToScreenPixels(backingScaleFactor, (frame.height - label.frame.height) / 2)))

        let capsule = CGPath(roundedRect: bounds, cornerWidth: frame.height / 2, cornerHeight: frame.height / 2, transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheen.frame = bounds
        sheenMask.frame = bounds
        sheenMask.path = capsule
        outline.frame = bounds
        outlineMask.frame = bounds
        outlineMask.path = CGPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: frame.height / 2 - 0.75, cornerHeight: frame.height / 2 - 0.75, transform: nil)
        sheenBand.frame = NSMakeRect(-Self.bandWidth, 0, Self.bandWidth, frame.height)
        outlineBand.frame = NSMakeRect(-Self.bandWidth, 0, Self.bandWidth, frame.height)
        let scale = backingScaleFactor
        divider.frame = NSMakeRect(floorToScreenPixels(scale, dividerX), floorToScreenPixels(scale, (frame.height - 14) / 2), 1 / max(1, scale), 14)
        let chevronX = floorToScreenPixels(scale, dividerX + 1 + Self.chevronInset - 1)
        let chevronY = (frame.height - Self.chevronSize.height) / 2
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: chevronX, y: chevronY))
        arrow.addLine(to: CGPoint(x: chevronX + Self.chevronSize.width, y: chevronY + Self.chevronSize.height / 2))
        arrow.addLine(to: CGPoint(x: chevronX, y: chevronY + Self.chevronSize.height))
        chevron.frame = bounds
        chevron.path = arrow
        CATransaction.commit()
        runSweeps()
    }

    private func runSweeps() {
        guard frame.width > 0 else { return }
        if let appliedSweep, appliedSweep.working == isWorking, appliedSweep.width == frame.width, sheenBand.animation(forKey: "sweep") != nil {
            return
        }
        appliedSweep = (isWorking, frame.width)
        let sweep = isWorking ? 0.9 : 1.1
        let pause = isWorking ? 0.0 : 1.6
        for (layer, delay) in [(sheenBand, 0.0), (outlineBand, 0.12)] {
            let move = CABasicAnimation(keyPath: "position.x")
            move.fromValue = -Self.bandWidth / 2
            move.toValue = frame.width + Self.bandWidth / 2
            move.duration = sweep
            move.beginTime = delay
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            let group = CAAnimationGroup()
            group.animations = [move]
            group.duration = sweep + pause + delay
            group.repeatCount = .infinity
            layer.add(group, forKey: "sweep")
        }
    }

    func animateIn() {
        layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        layer?.animateScaleSpringFrom(anchor: NSMakePoint(frame.width / 2, frame.height), from: 0.3, to: 1, duration: 0.45, bounce: true)
    }

    static let flowDuration: CFTimeInterval = 0.52
    static let landingFraction: Double = 0.6

    func flow(into target: NSRect?) -> CFTimeInterval {
        guard let container = superview, let target, target.width > 0, target.height > 0 else {
            performSubviewRemoval(self, animated: true, scale: true)
            return 0
        }
        let pill = frame
        let cover = target.insetBy(dx: -4, dy: -1)
        let gather = Self.scaled(pill, by: 0.92).offsetBy(dx: 0, dy: -2)
        let overshoot = Self.scaled(cover, by: 1.035)
        let frames = [pill, gather, overshoot, cover]
        let radii = [pill.height / 2, gather.height / 2, min(10, overshoot.height / 2), min(7, cover.height / 2)]
        let keyTimes: [NSNumber] = [0, 0.2, NSNumber(value: Self.landingFraction), 1]

        let overlay = View(frame: container.bounds)
        overlay.isEventLess = true
        container.addSubview(overlay, positioned: .above, relativeTo: self)

        let body = CAShapeLayer()
        body.frame = overlay.bounds
        body.fillColor = accentColor.cgColor
        body.path = Self.rounded(cover, radius: radii[3])
        body.opacity = 0
        overlay.layer?.addSublayer(body)

        let shape = CAKeyframeAnimation(keyPath: "path")
        shape.values = zip(frames, radii).map { Self.rounded($0.0, radius: $0.1) }
        shape.keyTimes = keyTimes
        shape.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1), CAMediaTimingFunction(name: .easeOut)]
        shape.duration = Self.flowDuration
        body.add(shape, forKey: "flow")
        let fill = CAKeyframeAnimation(keyPath: "opacity")
        fill.values = [0, 1, 1, 0.9, 0]
        fill.keyTimes = [0, 0.08, 0.45, NSNumber(value: Self.landingFraction), 1]
        fill.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeIn)]
        fill.duration = Self.flowDuration
        body.add(fill, forKey: "fill")

        layer?.animateAlpha(from: 1, to: 0, duration: 0.12, removeOnCompletion: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            self?.removeFromSuperview()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flowDuration + 0.05) {
            overlay.removeFromSuperview()
        }
        return Self.flowDuration * Self.landingFraction
    }

    private static func scaled(_ rect: NSRect, by factor: CGFloat) -> NSRect {
        let width = rect.width * factor
        let height = rect.height * factor
        return NSMakeRect(rect.midX - width / 2, rect.midY - height / 2, width, height)
    }

    private static func rounded(_ rect: NSRect, radius: CGFloat) -> CGPath {
        let corner = max(0.5, min(radius, rect.width / 2 - 0.01, rect.height / 2 - 0.01))
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    func setWorking(_ working: Bool) {
        guard isWorking != working else { return }
        isWorking = working
        setAccessibilityLabel(working ? strings().chatInputDictationEnhancing : strings().chatInputDictationEnhanceAccessibility)
        if working {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.45
            pulse.duration = 0.55
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            icon.layer?.add(pulse, forKey: "pulse")
        } else {
            icon.layer?.removeAnimation(forKey: "pulse")
        }
        runSweeps()
    }
}

struct ChatDictationEnhanceStyle {
    static let fixId = "fix"
    private static let selectedKey = "kChatDictationEnhanceStyle"
    private static let defaults = ["formal": "Formal", "short": "Short", "savage": "Savage", "biblical": "Biblical", "posh": "Posh"]
    private static let defaultOrder = ["formal", "short", "savage", "biblical", "posh"]

    let id: String
    let title: String
    let fileId: Int64?
    let reference: TelegramComposeAIMessageMode.CloudStyle.Reference?

    static var selectedId: String {
        get { UserDefaults.standard.string(forKey: selectedKey) ?? fixId }
        set { UserDefaults.standard.set(newValue, forKey: selectedKey) }
    }

    init(id: String, title: String, fileId: Int64?, reference: TelegramComposeAIMessageMode.CloudStyle.Reference?) {
        self.id = id
        self.title = title
        self.fileId = fileId
        self.reference = reference
    }

    init(cloud: TelegramComposeAIMessageMode.CloudStyle) {
        switch cloud.content {
        case let .standard(standard):
            self.init(id: standard.type, title: standard.title, fileId: standard.emojiFileId, reference: cloud.reference)
        case let .custom(custom):
            self.init(id: "custom_\(custom.id)", title: custom.title, fileId: custom.emojiFileId, reference: cloud.reference)
        }
    }

    static func configured(_ context: any AccountContextProtocol) -> [ChatDictationEnhanceStyle] {
        if let data = context.appConfiguration.data, let styles = data["ai_compose_styles"] as? [[Any]] {
            let items = styles.compactMap { entry -> ChatDictationEnhanceStyle? in
                guard entry.count >= 3, let id = entry[0] as? String, let title = entry[2] as? String else { return nil }
                return ChatDictationEnhanceStyle(id: id, title: title, fileId: (entry[1] as? String).flatMap { Int64($0) }, reference: .standard(id))
            }
            if !items.isEmpty {
                return items
            }
        }
        return defaultOrder.map { ChatDictationEnhanceStyle(id: $0, title: defaults[$0] ?? $0, fileId: nil, reference: .standard($0)) }
    }
}

private final class ChatDictationStyleIcon: View, AppMenuItemImageDrawable {
    private let item: ContextMenuItem
    private let sticker: InlineStickerItemLayer

    init(context: any AccountContextProtocol, fileId: Int64, item: ContextMenuItem) {
        self.item = item
        self.sticker = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: NSMakeSize(18, 18), playPolicy: .framesCount(1))
        super.init(frame: NSMakeRect(0, 0, 18, 18))
        isEventLess = true
        sticker.frame = bounds
        layer?.addSublayer(sticker)
        sticker.isPlayable = true
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateState(_ controlState: ControlState) {
        if controlState == .Hover {
            sticker.playAgain()
        }
    }

    func setColor(_ color: NSColor) {
    }

    func isEqual(to other: ContextMenuItem) -> Bool {
        return item.id == other.id
    }
}

final class ChatDictationEnhancer {
    private static let visibleDuration: Double = 8

    private weak var chatInteraction: ChatInteraction?
    private weak var host: ChatVoiceTranscriptionHost?
    private weak var textView: NSTextView?
    private let effect: ChatDictationTextEffect?
    private let view = ChatDictationEnhanceView(frame: .zero)
    private let disposable = MetaDisposable()
    private let stylesDisposable = MetaDisposable()
    private var styles: [ChatDictationEnhanceStyle]
    private var isMenuOpen = false
    private let range: NSRange
    private let snapshot: String
    private var expected: String?
    private var readyAt: CFTimeInterval = 0
    private var isEnded = false
    private var hideToken = 0
    var onEnd: (() -> Void)?

    static func canOffer(chatInteraction: ChatInteraction, range: NSRange) -> Bool {
        let presentation = chatInteraction.presentation
        guard presentation.state == .normal, presentation.peer?.isSecretChat != true else {
            return false
        }
        let text = presentation.effectiveInput.inputText as NSString
        guard range.length > 0, NSMaxRange(range) <= text.length else {
            return false
        }
        return ChatInputDictationText.enhanceableText(text.substring(with: range)) != nil
    }

    init(chatInteraction: ChatInteraction, host: ChatVoiceTranscriptionHost, effect: ChatDictationTextEffect?, range: NSRange) {
        self.chatInteraction = chatInteraction
        self.host = host
        self.textView = host.transcriptionTextView
        self.effect = effect
        self.range = range
        self.snapshot = chatInteraction.presentation.effectiveInput.inputText
        self.styles = ChatDictationEnhanceStyle.configured(chatInteraction.interactionContext)
        view.onEnhance = { [weak self] in
            self?.enhance()
        }
        view.onStyles = { [weak self] event in
            self?.showStyles(event)
        }
        stylesDisposable.set((chatInteraction.interactionContext.engine.messages.composeAIMessageStyles() |> deliverOnMainQueue).start(next: { [weak self] cloud in
            let items = cloud.map { ChatDictationEnhanceStyle(cloud: $0) }
            if !items.isEmpty {
                self?.styles = items
            }
        }))
        view.anchor = { [weak self] container in
            self?.anchorX(in: container)
        }
    }

    deinit {
        disposable.dispose()
        stylesDisposable.dispose()
        (view.window as? Window)?.removeAllHandlers(for: view)
    }

    private func showStyles(_ event: NSEvent) {
        guard !isEnded, !view.isWorking else { return }
        let selected = ChatDictationEnhanceStyle.selectedId
        let menu = ContextMenu()
        menu.addItem(ContextMenuItem(strings().chatInputDictationEnhanceFix, handler: { [weak self] in
            self?.choose(ChatDictationEnhanceStyle.fixId)
        }, state: selected == ChatDictationEnhanceStyle.fixId ? .on : nil, itemImage: MenuAnimation.menu_edit.value))
        if !styles.isEmpty, let context = chatInteraction?.interactionContext {
            menu.addItem(ContextSeparatorItem())
            for style in styles {
                let icon: ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)? = style.fileId.flatMap { fileId in
                    fileId == 0 ? nil : { _, item in ChatDictationStyleIcon(context: context, fileId: fileId, item: item) }
                }
                menu.addItem(ContextMenuItem(style.title, handler: { [weak self] in
                    self?.choose(style.id)
                }, state: selected == style.id ? .on : nil, itemImage: icon))
            }
        }
        menu.addItem(ContextSeparatorItem())
        menu.addItem(ContextMenuItem(strings().chatInputDictationEnhanceEditor, handler: { [weak self] in
            self?.openEditor()
        }, itemImage: MenuAnimation.menu_translate.value))
        isMenuOpen = true
        hideToken += 1
        menu.onClose = { [weak self] in
            guard let self, self.isMenuOpen else { return }
            self.isMenuOpen = false
            if !self.isEnded, !self.view.isWorking {
                self.scheduleHide(after: 4)
            }
        }
        AppMenu.show(menu: menu, event: event, for: view)
    }

    private func choose(_ id: String) {
        isMenuOpen = false
        ChatDictationEnhanceStyle.selectedId = id
        enhance()
    }

    private func openEditor() {
        isMenuOpen = false
        let chatInteraction = self.chatInteraction
        end(animated: true)
        chatInteraction?.openAIEditor(morphSource: nil)
    }

    private func selectedStyle() -> TelegramComposeAIMessageMode.CloudStyle.Reference? {
        let id = ChatDictationEnhanceStyle.selectedId
        guard id != ChatDictationEnhanceStyle.fixId else { return nil }
        if let style = styles.first(where: { $0.id == id }) {
            return style.reference
        }
        return id.hasPrefix("custom_") ? nil : .standard(id)
    }

    func show(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isEnded else { return }
            guard let host = self.host, self.chatInteraction?.presentation.effectiveInput.inputText == self.snapshot else {
                self.end(animated: false)
                return
            }
            host.showDictationEnhance(self.view)
            self.installOutsideClick()
            self.scheduleHide(after: Self.visibleDuration)
        }
    }

    func inputDidChange(_ input: ChatTextInputState) {
        guard !isEnded, input.inputText != (expected ?? snapshot) else { return }
        cancel()
    }

    func cancel() {
        guard !isEnded else { return }
        disposable.set(nil)
        if view.isWorking {
            effect?.cancelReveal()
        }
        end(animated: true)
    }

    private func scheduleHide(after delay: Double) {
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, token == self.hideToken, !self.isEnded, !self.view.isWorking else { return }
            if self.view.mouseInside() || self.isMenuOpen {
                self.scheduleHide(after: 1.5)
            } else {
                self.end(animated: true)
            }
        }
    }

    private func installOutsideClick() {
        guard let window = view.window as? Window else { return }
        let handler: (NSEvent) -> KeyHandlerResult = { [weak self] event in
            guard let self, !self.view.isWorking else { return .rejected }
            let point = self.view.convert(event.locationInWindow, from: nil)
            if !NSPointInRect(point, self.view.bounds) {
                self.end(animated: true)
            }
            return .rejected
        }
        window.set(mouseHandler: handler, with: view, for: .leftMouseDown, priority: .supreme)
        window.set(mouseHandler: handler, with: view, for: .rightMouseDown, priority: .supreme)
    }

    private func anchorX(in container: NSView) -> CGFloat? {
        guard let textView, let layout = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        let text = textView.string as NSString
        let range = NSIntersectionRange(self.range, NSMakeRange(0, text.length))
        guard range.length > 0 else { return nil }
        let trimmed = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let end = text.range(of: trimmed, options: .backwards, range: range)
        guard end.location != NSNotFound else { return nil }
        let last = text.rangeOfComposedCharacterSequence(at: NSMaxRange(end) - 1)
        let glyphs = layout.glyphRange(forCharacterRange: last, actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: textContainer).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        return textView.convert(rect, to: container).maxX
    }

    private func enhance() {
        guard !isEnded, !view.isWorking, let chatInteraction else { return }
        let input = chatInteraction.presentation.effectiveInput
        let text = input.inputText as NSString
        guard input.inputText == snapshot, NSMaxRange(range) <= text.length, let segment = ChatInputDictationText.enhanceableText(text.substring(with: range)) else {
            end(animated: true)
            return
        }
        hideToken += 1
        view.setWorking(true)
        let impact = view.superview.flatMap { landingSpot(in: $0) }
        let animated = effect?.canAnimate == true
        let landing = view.flow(into: animated ? impact?.rect : nil)
        if let impact, landing > 0 {
            effect?.ripple(range: range, from: impact.index, after: landing - 0.06, tint: view.accentColor)
        }
        effect?.loopShimmer(range: range, after: landing > 0 ? landing + 0.6 : 0)
        readyAt = CACurrentMediaTime() + (landing > 0 ? landing + 1.0 : 0)
        let context = chatInteraction.interactionContext
        let analyticsContext = chatInteraction.captureAnalyticsContext()
        let style = selectedStyle()
        let signal = context.engine.messages.composeMessageWithAI(text: segment, entities: [], proofread: style == nil, changeStyle: style)
        |> deliverOnMainQueue
        disposable.set(analyticsContext.preservingPresentation(signal).start(next: { [weak self] result in
            self?.whenReady {
                self?.apply(result.0)
            }
        }, error: { [weak self] error in
            self?.whenReady {
                self?.fail(error, analyticsContext: analyticsContext)
            }
        }))
    }

    private func whenReady(_ action: @escaping () -> Void) {
        let wait = readyAt - CACurrentMediaTime()
        if wait > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: action)
        } else {
            action()
        }
    }

    private func landingSpot(in container: NSView) -> (rect: NSRect, index: Int)? {
        guard let textView, let layout = textView.layoutManager, let textContainer = textView.textContainer else { return nil }
        let length = textView.string.utf16.count
        let range = NSIntersectionRange(self.range, NSMakeRange(0, length))
        guard range.length > 0 else { return nil }
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect
        var first: NSRect?
        var union: NSRect?
        layout.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, line, _ in
            let part = NSIntersectionRange(line, glyphs)
            guard part.length > 0 else { return }
            let rect = layout.boundingRect(forGlyphRange: part, in: textContainer).offsetBy(dx: origin.x, dy: origin.y).intersection(visible)
            guard !rect.isEmpty else { return }
            first = first ?? rect
            union = union.map { $0.union(rect) } ?? rect
        }
        guard let first, let union else { return nil }
        let line = textView.convert(first, to: container)
        let x = min(max(view.frame.midX, line.minX + 6), line.maxX - 6)
        let point = textView.convert(NSMakePoint(x, line.midY), from: container)
        var fraction: CGFloat = 0
        let index = layout.characterIndex(for: NSMakePoint(point.x - origin.x, point.y - origin.y), in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        return (textView.convert(union, to: container), min(max(index, range.location), NSMaxRange(range) - 1))
    }

    private func apply(_ improved: String) {
        guard !isEnded, let chatInteraction else { return }
        let input = chatInteraction.presentation.effectiveInput
        guard input.inputText == snapshot, let replaced = ChatInputDictationText.replacingSegment(input.attributedString(), range: range, with: improved) else {
            effect?.settleShimmer(range: range, text: nil)
            end(animated: true)
            return
        }
        let selection = ChatInputDictationText.selection(input.selectionRange, afterReplacing: range, length: replaced.range.length)
        let before = (input.inputText as NSString).substring(with: range)
        let after = (replaced.text.string as NSString).substring(with: replaced.range)
        let changes = ChatInputDictationText.changedCharacters(from: before, to: after).map { NSRange(location: $0.location + replaced.range.location, length: $0.length) }
        expected = replaced.text.string
        effect?.settleShimmer(range: replaced.range, text: replaced.text.string)
        chatInteraction.update({ $0.withUpdatedEffectiveInputState(ChatTextInputState(attributedText: replaced.text, selectionRange: selection)) })
        effect?.arrive(ranges: changes, within: replaced.range, text: replaced.text.string, tint: view.accentColor)
        effect?.redraw()
        end(animated: true)
    }

    private func fail(_ error: TranslationError, analyticsContext: AnalyticsContext) {
        guard !isEnded, let chatInteraction else { return }
        effect?.settleShimmer(range: range, text: nil)
        end(animated: true)
        let context = chatInteraction.interactionContext
        if case .limitExceeded = error {
            FeatureNavigationHooks.shared.showPremiumBoardingObserved(context, context.window, .aiCompose, false, nil, analyticsContext: analyticsContext)
        } else {
            showModalText(for: context.window, text: strings().unknownError)
        }
    }

    private func end(animated: Bool) {
        guard !isEnded else { return }
        isEnded = true
        hideToken += 1
        (view.window as? Window)?.removeAllHandlers(for: view)
        host?.hideDictationEnhance(view, animated: animated)
        let onEnd = self.onEnd
        self.onEnd = nil
        onEnd?()
    }
}
