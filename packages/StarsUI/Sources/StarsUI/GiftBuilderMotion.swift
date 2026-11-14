import Cocoa
import TGUIKit
import TelegramContext
import UniqueGiftBackground

enum GiftBuilderMotion {
    static var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func updateText(_ view: TextView, layout: TextViewLayout, animated: Bool) {
        if animated, let previousLayout = view.textLayout,
           !previousLayout.attributedString.isEqual(to: layout.attributedString), let parent = view.superview {
            let previous = TextView()
            previous.userInteractionEnabled = false
            previous.isSelectable = false
            previous.update(previousLayout)
            previous.frame = view.frame
            parent.addSubview(previous, positioned: .above, relativeTo: view)
            previous.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak previous] _ in
                previous?.removeFromSuperview()
            })
            view.layer?.animateAlpha(from: 0, to: 1, duration: 0.25)
        }
        view.update(layout)
    }

    static func fade(_ view: NSView) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = reduceMotion ? 0.15 : 0.25
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(transition, forKey: "giftBuilder.contents")
    }
}

final class GiftBuilderAnimatedText: View {
    private let text = DynamicCounterTextView(frame: .zero)
    var padding: NSSize = .zero

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        userInteractionEnabled = false
        layer?.masksToBounds = false
        text.layer?.masksToBounds = false
        addSubview(text)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ layout: TextViewLayout, animated: Bool) {
        let attributes = layout.attributedString.length > 0 ? layout.attributedString.attributes(at: 0, effectiveRange: nil) : [:]
        let font = attributes[.font] as? NSFont ?? .normal(.text)
        let string = Self.fittedText(layout.attributedString.string, font: font, width: layout.constrainedWidth)
        let value = DynamicCounterTextView.make(for: string, count: string.utf16.count == string.count ? string : "", font: font, textColor: attributes[.foregroundColor] as? NSColor ?? .white, width: layout.constrainedWidth, onlyFade: GiftBuilderMotion.reduceMotion, kerned: true, rolling: !GiftBuilderMotion.reduceMotion)
        text.update(value, animated: animated)
        text.setFrameSize(value.size)
        setFrameSize(NSMakeSize(value.size.width + padding.width * 2, value.size.height + padding.height * 2))
        self.layout()
    }

    private static func fittedText(_ string: String, font: NSFont, width: CGFloat) -> String {
        func fits(_ value: String) -> Bool {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font]))
            return ceil(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)) <= width
        }
        guard !fits(string) else { return string }
        var prefix = string
        while !prefix.isEmpty {
            prefix.removeLast()
            let value = prefix + "…"
            if fits(value) { return value }
        }
        return ""
    }

    override func layout() {
        super.layout()
        text.center()
    }
}

struct GiftBuilderAppearanceReveal {
    static let duration: Double = 0.9
    static let feather: CGFloat = 70
    let center: CGPoint
    let size: CGSize
    let startTime: CFTimeInterval

    func makeMask(frame: CGRect, completion: @escaping () -> Void) -> CALayer {
        let localCenter = CGPoint(x: center.x - frame.minX, y: center.y - frame.minY)
        let far = hypot(max(center.x, size.width - center.x), max(center.y, size.height - center.y))
        let mask = CALayer()
        mask.contents = Self.revealDisc
        mask.position = localCenter
        let radius = (far + Self.feather) / 0.78
        mask.bounds = NSMakeRect(0, 0, radius * 2, radius * 2)
        let animation = CAKeyframeAnimation(keyPath: "bounds")
        animation.values = (0...30).map { step -> NSValue in
            let progress = 1 - pow(1 - Double(step) / 30, 2)
            let radius = max(0.01, (far + Self.feather) * CGFloat(progress)) / 0.78
            return NSValue(rect: NSMakeRect(0, 0, radius * 2, radius * 2))
        }
        animation.duration = Self.duration
        animation.beginTime = mask.convertTime(startTime, from: nil)
        animation.fillMode = .backwards
        animation.calculationMode = .linear
        animation.delegate = CALayerAnimationDelegate(completion: { _ in completion() })
        mask.add(animation, forKey: "giftBuilder.reveal")
        return mask
    }

    private static let revealDisc: CGImage? = {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: [NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor] as CFArray, locations: [0, 0.78, 1]) else { return nil }
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        return context.makeImage()
    }()
}

final class GiftBuilderGlassView: View {
    private var visuals: [LiquidGlassView] = []
    private var tint: NSColor?
    private var previousSize: NSSize = .zero
    var radius: CGFloat = 16

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(tint: NSColor, coordinateView: NSView, reveal: GiftBuilderAppearanceReveal?, animated: Bool) {
        guard self.tint != tint else { return }
        self.tint = tint
        let visual = LiquidGlassView(frame: bounds, cornerRadius: radius, hasShadow: true, hasBorder: true, forceAppearance: .forceLight, customTint: tint)
        addSubview(visual)
        visuals.append(visual)
        visual.updateLayout(size: bounds.size, transition: .immediate)
        while visuals.count > 3 { visuals.removeFirst().removeFromSuperview() }
        guard visuals.count > 1 else { return }
        if let reveal, let layer = visual.layer {
            layer.mask = reveal.makeMask(frame: coordinateView.convert(bounds, from: self), completion: { [weak self, weak visual] in
                if let visual { self?.finish(visual) }
            })
        } else if animated {
            visual.layer?.animateAlpha(from: 0, to: 1, duration: 0.2, completion: { [weak self, weak visual] _ in
                if let visual { self?.finish(visual) }
            })
        } else {
            finish(visual)
        }
    }

    private func finish(_ visual: LiquidGlassView) {
        guard let index = visuals.firstIndex(where: { $0 === visual }) else { return }
        visual.layer?.mask = nil
        let removed = Array(visuals.prefix(index))
        visuals.removeFirst(index)
        for view in removed { view.removeFromSuperview() }
    }

    override func layout() {
        super.layout()
        if previousSize != bounds.size {
            previousSize = bounds.size
            if let last = visuals.last { finish(last) }
        }
        for visual in visuals {
            visual.frame = bounds
            visual.updateLayout(size: bounds.size, transition: .immediate)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { return nil }
}

final class GiftBuilderButton: Control {
    let glass = GiftBuilderGlassView(frame: .zero)
    private let icon = ImageView()
    private var iconSize = NSSize(width: 16, height: 16)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        glass.radius = 18
        addSubview(glass)
        addSubview(icon)
        icon.isEventLess = true
        icon.isAccessibilityDecorative = true
        icon.contentGravity = .resizeAspect
        interactiveGlassView = glass
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateIcon(_ image: CGImage, size: NSSize, animated: Bool) {
        if animated { GiftBuilderMotion.fade(icon) }
        icon.image = image
        iconSize = size
        layout()
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        glass.layout()
        icon.frame = NSMakeRect(floor((bounds.width - iconSize.width) / 2), floor((bounds.height - iconSize.height) / 2), iconSize.width, iconSize.height)
    }
}

final class GiftBuilderBackgroundView: View {
    var onReveal: ((UniqueGiftBackgroundContent, GiftBuilderAppearanceReveal?, Bool) -> Void)?
    private var content: UniqueGiftBackgroundContent?
    private var displayedContent: UniqueGiftBackgroundContent?
    private var backgrounds: [UniqueGiftBackgroundView] = []
    private var pendingBackground: UniqueGiftBackgroundView?
    private var previousSize: NSSize = .zero

    func update(context: any AccountContextProtocol, content: UniqueGiftBackgroundContent, center: NSPoint, animated: Bool) {
        guard self.content != content else { return }
        let animate = animated && self.content != nil && bounds.width > 0 && bounds.height > 0
        self.content = content
        pendingBackground?.onContentReady = nil
        pendingBackground?.removeFromSuperview()
        pendingBackground = nil
        let background = UniqueGiftBackgroundView(frame: bounds)
        addSubview(background)
        if animate {
            pendingBackground = background
            background.layer?.opacity = 0
            background.onContentReady = { [weak self, weak background] in
                guard let self, let background, self.pendingBackground === background else { return }
                background.onContentReady = nil
                self.pendingBackground = nil
                self.reveal(background, content: content, center: center, animated: true)
            }
        } else {
            reveal(background, content: content, center: center, animated: false)
        }
        background.update(context: context, content: content, style: .animatedHeader(patternCenterY: center.y), animated: false)
        background.layer?.layoutIfNeeded()
    }

    private func reveal(_ background: UniqueGiftBackgroundView, content: UniqueGiftBackgroundContent, center: NSPoint, animated: Bool) {
        let changesColors = displayedContent?.colors != content.colors
        let changesPattern = displayedContent?.pattern != content.pattern
        displayedContent = content
        background.layer?.opacity = 1
        backgrounds.append(background)
        while backgrounds.count > 3 { backgrounds.removeFirst().removeFromSuperview() }
        let reveal = animated && changesColors && !GiftBuilderMotion.reduceMotion ? GiftBuilderAppearanceReveal(center: center, size: bounds.size, startTime: CACurrentMediaTime()) : nil
        onReveal?(content, reveal, animated)
        guard animated, let layer = background.layer else {
            finish(background)
            return
        }
        if let reveal {
            layer.mask = reveal.makeMask(frame: bounds, completion: { [weak self, weak background] in
                if let background { self?.finish(background) }
            })
        } else {
            layer.animateAlpha(from: 0, to: 1, duration: 0.25, completion: { [weak self, weak background] _ in
                if let background { self?.finish(background) }
            })
        }
        if changesPattern && !GiftBuilderMotion.reduceMotion {
            background.animatePatternTransition()
        }
    }

    private func finish(_ background: UniqueGiftBackgroundView) {
        guard let index = backgrounds.firstIndex(where: { $0 === background }) else { return }
        background.layer?.mask = nil
        let removed = Array(backgrounds.prefix(index))
        backgrounds.removeFirst(index)
        for view in removed { view.removeFromSuperview() }
    }

    override func layout() {
        super.layout()
        if previousSize != bounds.size {
            previousSize = bounds.size
            if let last = backgrounds.last {
                finish(last)
                last.frame = bounds
            }
            pendingBackground?.frame = bounds
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { return nil }
}
