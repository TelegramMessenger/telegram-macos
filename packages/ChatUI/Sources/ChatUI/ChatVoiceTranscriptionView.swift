import Cocoa
import TGUIKit
import TelegramTheme
import TelegramContext

final class ChatVoiceTranscriptionView: View {
    enum Action {
        case edit
        case cancel
    }

    private let context: any AccountContextProtocol
    private let aura = CALayer()
    private let exterior = CAShapeLayer()
    private let glows = (0 ..< 4).map { _ in CAGradientLayer() }
    private let ribbon = CAGradientLayer()
    private let filament = CAGradientLayer()
    private let glowMasks = (0 ..< 4).map { _ in CAShapeLayer() }
    private let ripples = (0 ..< 4).map { _ in CAGradientLayer() }
    private let rippleMasks = (0 ..< 4).map { _ in CAShapeLayer() }
    private let ribbonMask = CAShapeLayer()
    private let filamentMask = CAShapeLayer()
    private var animator: ConstantDisplayLinkAnimator?
    private var targetLevel: CGFloat = 0
    private var audioLevel: CGFloat = 0
    private var animationTime: Double = 0
    private var isListening = false
    private var pulses: [ChatDictationAuraPulse] = []
    private var emissionClock: CGFloat = 0.36

    private var gradients: [CAGradientLayer] {
        return glows + ripples + [ribbon, filament]
    }

    private var masks: [CAShapeLayer] {
        return glowMasks + rippleMasks + [ribbonMask, filamentMask]
    }

    static var composerTransition: ContainedViewLayoutTransition {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .immediate
            : .animated(duration: 0.22, curve: .easeOut)
    }

    init(context: any AccountContextProtocol) {
        self.context = context
        super.init(frame: .zero)
        isEventLess = true
        layer?.opacity = 0
        layer?.masksToBounds = false
        layer?.addSublayer(aura)
        aura.mask = exterior
        exterior.fillRule = .evenOdd
        exterior.fillColor = NSColor.white.cgColor
        for (gradient, mask) in zip(gradients, masks) {
            if #available(macOS 10.14, *) {
                gradient.type = .conic
            }
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            gradient.mask = mask
            mask.fillColor = nil
            mask.strokeColor = NSColor.white.cgColor
            mask.lineCap = .round
            mask.lineJoin = .round
            mask.contentsScale = 2
            aura.addSublayer(gradient)
        }
        ribbonMask.lineWidth = 1.8
        filamentMask.lineWidth = 1
        filament.opacity = 0.12
        for ripple in ripples {
            ripple.opacity = 0
            if !context.isLite(.blur), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
               let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8]) {
                ripple.filters = [blur]
            }
        }
        for (index, glow) in glows.enumerated() {
            if context.isLite(.blur) || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                glow.isHidden = true
            } else if index < 2, let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: index == 0 ? 3 : 1.5]) {
                glow.filters = [blur]
            }
        }
        updateLocalizationAndTheme(theme: theme)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    deinit {
        animator?.invalidate()
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || context.isLite(.animations)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let accent = theme.colors.accent.usingColorSpace(.deviceRGB) ?? NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 1)
        let dark = theme.colors.isDark
        let highlight = accent.blended(withFraction: dark ? 0.42 : 0.18, of: .white) ?? accent
        let shadow = accent.blended(withFraction: dark ? 0.04 : 0.2, of: .black) ?? accent
        let hue = accent.hueComponent
        let saturation = accent.saturationComponent
        let brightness = max(dark ? 0.5 : 0.25, accent.brightnessComponent)
        let cool = NSColor(calibratedHue: (hue - 0.035 + 1).truncatingRemainder(dividingBy: 1), saturation: saturation * 0.9, brightness: brightness, alpha: 1)
        let warm = NSColor(calibratedHue: (hue + 0.035).truncatingRemainder(dividingBy: 1), saturation: saturation * 0.9, brightness: brightness, alpha: 1)
        let colors = [shadow.cgColor, cool.cgColor, accent.cgColor, highlight.cgColor, warm.cgColor, shadow.cgColor]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for gradient in gradients {
            gradient.removeAnimation(forKey: "auroraFlow")
            gradient.colors = colors
        }
        CATransaction.commit()
        updateAnimation()
    }

    func setListening(_ listening: Bool, animated: Bool) {
        isListening = listening
        let transition: ContainedViewLayoutTransition = animated && !reduceMotion
            ? .animated(duration: 0.22, curve: .easeOut)
            : .immediate
        transition.updateAlpha(view: self, alpha: listening ? 1 : 0)
        if !listening {
            targetLevel = 0
            audioLevel = 0
            pulses.removeAll()
            emissionClock = 0.36
        }
        updateAnimation()
        renderAura()
    }

    func updateLevel(_ level: CGFloat) {
        guard isListening else { return }
        targetLevel = pow(max(0, min(1, level.isFinite ? level : 0)), 0.65)
        if animator?.isPaused != false {
            audioLevel = targetLevel
            renderAura()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for mask in masks {
            mask.contentsScale = window?.backingScaleFactor ?? 2
        }
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let padding = ChatDictationAura.padding
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        aura.frame = size.bounds.insetBy(dx: -padding, dy: -padding)
        for gradient in gradients {
            gradient.frame = aura.bounds
            gradient.mask?.frame = aura.bounds
        }
        exterior.frame = aura.bounds
        let cutout = CGMutablePath()
        cutout.addRect(aura.bounds)
        let field = CGRect(x: padding, y: padding, width: size.width, height: size.height)
        let radius = min(20, min(size.width, size.height) / 2)
        if radius > 0 {
            cutout.addRoundedRect(in: field, cornerWidth: radius, cornerHeight: radius)
        }
        exterior.path = cutout
        CATransaction.commit()
        renderAura()
    }

    private func updateAnimation() {
        let running = isListening && window != nil && !reduceMotion
        if running, animator == nil {
            animator = ConstantDisplayLinkAnimator(framesPerSecond: .fps(30), update: { [weak self] duration in
                self?.advance(by: duration)
            })
        }
        animator?.isPaused = !running
        for gradient in gradients {
            if running, gradient.animation(forKey: "auroraFlow") == nil, let colors = gradient.colors {
                let flow = CAKeyframeAnimation(keyPath: "colors")
                let count = colors.count - 1
                flow.values = (0 ... count).map { offset in
                    let shifted = (0 ..< count).map { colors[($0 + offset) % count] }
                    return shifted + [shifted[0]]
                }
                flow.duration = 9
                flow.repeatCount = .infinity
                gradient.add(flow, forKey: "auroraFlow")
            } else if !running {
                gradient.removeAnimation(forKey: "auroraFlow")
            }
        }
    }

    private func advance(by duration: CGFloat) {
        guard isListening, window != nil, !reduceMotion else {
            updateAnimation()
            return
        }
        let delta = max(0, min(0.05, duration))
        animationTime += Double(delta)
        let rate: CGFloat = targetLevel > audioLevel ? 22 : 8
        audioLevel += (targetLevel - audioLevel) * (1 - exp(-delta * rate))
        pulses.removeAll(where: { animationTime - $0.born >= ChatDictationAuraPulse.lifetime })
        emissionClock += delta
        if targetLevel > 0.12, audioLevel > 0.18, emissionClock >= 0.36 {
            emissionClock = 0
            if pulses.count == ripples.count {
                pulses.removeFirst()
            }
            pulses.append(ChatDictationAuraPulse(born: animationTime, energy: audioLevel))
        }
        renderAura()
    }

    private func renderAura() {
        let padding = ChatDictationAura.padding
        let field = CGRect(x: padding, y: padding, width: frame.width, height: frame.height)
        let radius = min(20, min(field.width, field.height) / 2)
        let path = CGPath(roundedRect: field, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let echo = ChatDictationAura.path(around: field, level: audioLevel, time: animationTime, band: 1, motion: !reduceMotion)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let widths: [CGFloat] = [20, 13, 8, 4]
        let expansion: [CGFloat] = [6, 5, 3, 1]
        let opacity: [Float] = [0.05, 0.09, 0.18, 0.32]
        for index in glows.indices {
            glowMasks[index].path = path
            glowMasks[index].lineWidth = widths[index] + audioLevel * expansion[index]
            glows[index].opacity = opacity[index] * Float(0.7 + audioLevel * 0.7)
        }
        ribbonMask.path = path
        filamentMask.path = echo
        filament.opacity = Float(0.12 + audioLevel * 0.08)
        ribbonMask.lineWidth = 1.8 + audioLevel * 0.5
        for index in ripples.indices {
            guard !reduceMotion, index < pulses.count else {
                ripples[index].opacity = 0
                continue
            }
            let pulse = pulses[index]
            let progress = pulse.progress(at: animationTime)
            rippleMasks[index].path = ChatDictationAura.path(around: field, level: pulse.energy * (1 - progress) * 0.35, time: animationTime, band: pulse.energy * 0.8, motion: true, expansion: pulse.expansion(at: animationTime))
            rippleMasks[index].lineWidth = 1.5 + (1 - progress) * 1.5
            ripples[index].opacity = pulse.opacity(at: animationTime) * 0.65
        }
        CATransaction.commit()
    }

    func animateOut(completion: @escaping () -> Void) {
        let opacity = layer?.presentation()?.opacity ?? layer?.opacity ?? 0
        setListening(false, animated: false)
        guard !reduceMotion, window != nil, let layer else {
            completion()
            return
        }
        layer.animateAlpha(from: CGFloat(opacity), to: 0, duration: 0.22, completion: { _ in completion() })
    }
}
