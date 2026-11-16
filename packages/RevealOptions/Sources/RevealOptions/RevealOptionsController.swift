import AppKit
import TGUIKit

public final class RevealOptionsController {
    private weak var hostView: NSView?
    private let configuration: RevealOptionsConfiguration
    private let animationFactory: RevealOptionAnimationFactory?
    private var surfaceLayer: CALayer?

    private var leftView: RevealOptionsView?
    private var rightView: RevealOptionsView?
    private var options: (left: [RevealOption], right: [RevealOption]) = ([], [])

    private var motion = RevealMotion()
    private var revealDirection: CGFloat = -1
    private var animator: ConstantDisplayLinkAnimator?
    private var previousAnimationTime: CFTimeInterval = 0
    private var animationCompletion: (() -> Void)?
    private var deliveringAction = false
    private var size: NSSize?
    private var lastSurface: (progress: CGFloat, opacity: CGFloat) = (0, 0)
    private var translationSamples: [(time: CFTimeInterval, translation: CGFloat)] = []
    private var lastTranslation: CGFloat = 0

    public private(set) var revealOffset: CGFloat = 0
    public private(set) var isActive: Bool = false

    public var offsetUpdated: ((CGFloat) -> Void)?
    public var surfaceUpdated: ((_ progress: CGFloat, _ opacity: CGFloat) -> Void)?
    public var activeStateUpdated: ((Bool) -> Void)?
    public var optionSelected: ((_ option: RevealOption, _ animated: Bool) -> Void)?
    public var interactivelyOpened: (() -> Void)?
    public var interactivelyClosed: (() -> Void)?

    public weak var surfaceHost: NSView? {
        didSet {
            if oldValue !== self.surfaceHost {
                self.surfaceLayer?.removeFromSuperlayer()
                self.surfaceLayer = nil
                self.applySurface()
            }
        }
    }

    public var surface: RevealOptionsSurface? {
        didSet {
            self.applySurface()
        }
    }

    public init(hostView: NSView, configuration: RevealOptionsConfiguration = .chatList, animationFactory: RevealOptionAnimationFactory? = nil) {
        self.hostView = hostView
        self.configuration = configuration
        self.animationFactory = animationFactory
    }

    deinit {
        self.animator?.invalidate()
    }

    public var isDragging: Bool {
        return self.motion.state == .dragging
    }

    public var isFilling: Bool {
        return self.motion.state == .filling
    }

    public var isOpen: Bool {
        return self.motion.wantsOpen
    }

    public var surfaceProgress: CGFloat {
        return CGFloat(min(1, max(0, self.motion.surface.value)))
    }

    public var surfaceOpacity: CGFloat {
        return CGFloat(min(1, max(0, self.motion.surfaceOpacity.value)))
    }

    private var reduceMotion: Bool {
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var activeView: RevealOptionsView? {
        return self.revealDirection > 0 ? self.leftView : self.rightView
    }

    private var activeOptions: [RevealOption] {
        return self.revealDirection > 0 ? self.options.left : self.options.right
    }

    public func containsAction(atWindowPoint point: NSPoint) -> Bool {
        return self.activeView?.containsAction(atWindowPoint: point) ?? false
    }

    @discardableResult
    public func setOptions(left: [RevealOption], right: [RevealOption]) -> Bool {
        guard self.options.left != left || self.options.right != right else {
            return false
        }
        let previous = self.activeOptions
        let updated = self.revealDirection > 0 ? left : right
        let structuralChange = previous.map(\.animationKey) != updated.map(\.animationKey) || previous.map(\.isDestructive) != updated.map(\.isDestructive)
        if structuralChange && self.isActive {
            self.reset(notify: true)
        }
        self.options = (left, right)
        if let view = self.activeView {
            view.setOptions(self.activeOptions)
            self.updateActiveMetrics()
            if self.motion.state == .open || self.motion.state == .settling(open: true) {
                self.motion.settle(to: self.motion.parameters.openDistance, velocity: self.motion.body.velocity, animated: true)
            }
            self.render()
            self.startAnimation()
        }
        return true
    }

    public func updateLayout(size: NSSize) {
        if let previous = self.size, previous != size {
            self.reset(notify: true)
        }
        self.size = size
        if self.isActive {
            self.updateActiveMetrics()
            self.render()
        }
    }

    public func canBegin(direction: CGFloat) -> Bool {
        guard self.size != nil, self.motion.state != .filling, !self.deliveringAction else {
            return false
        }
        if self.isActive && (abs(self.motion.body.value) >= 0.1 || abs(self.motion.body.velocity) >= 5) {
            return true
        }
        return direction > 0 ? !self.options.left.isEmpty : !self.options.right.isEmpty
    }

    @discardableResult
    public func begin(direction: CGFloat) -> Bool {
        guard self.canBegin(direction: direction) else {
            return false
        }
        self.advanceAnimation()
        let atClosedPosition = abs(self.motion.body.value) < 0.1 && abs(self.motion.body.velocity) < 5
        if !self.isActive || atClosedPosition {
            let newDirection: CGFloat = direction > 0 ? 1 : -1
            if self.revealDirection != newDirection {
                self.removeViews()
                self.motion.reset()
            }
            guard self.setupRevealView(direction: newDirection) else {
                return false
            }
        }
        self.animationCompletion = nil
        self.motion.begin(highlightAlpha: 0)
        self.translationSamples = []
        self.lastTranslation = 0
        self.render()
        self.interactivelyOpened?()
        self.update(translation: 0)
        return true
    }

    public func update(translation: CGFloat) {
        guard self.motion.state == .dragging else {
            return
        }
        self.recordTranslation(translation)
        let velocity = self.currentVelocity()
        let wasArmed = self.motion.isArmed
        self.motion.change(translation: Double(translation * self.revealDirection), velocity: Double(velocity * self.revealDirection), distanceFromCommitEdge: .greatestFiniteMagnitude, reduceMotion: self.reduceMotion)
        if wasArmed != self.motion.isArmed {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        self.render()
        self.startAnimation()
    }

    public func end(translation: CGFloat, cancelled: Bool) {
        guard self.motion.state == .dragging else {
            return
        }
        let velocity = self.currentVelocity()
        self.translationSamples = []
        let commit = self.motion.end(translation: Double(translation * self.revealDirection), velocity: Double(velocity * self.revealDirection), cancelled: cancelled, animated: !self.reduceMotion)
        self.render()
        self.startAnimation()
        if commit, let option = self.revealDirection > 0 ? self.activeOptions.first : self.activeOptions.last {
            self.deliver(option, animated: true)
        } else if !self.motion.wantsOpen {
            self.interactivelyClosed?()
        }
    }

    @discardableResult
    public func handle(swipe direction: SwipeDirection, cancelled: Bool = false) -> Bool {
        switch direction {
        case let .left(state):
            return self.handle(state: state, sign: 1, cancelled: cancelled)
        case let .right(state):
            return self.handle(state: state, sign: -1, cancelled: cancelled)
        case .none:
            self.end(translation: self.lastTranslation, cancelled: true)
            return false
        }
    }

    private func handle(state: SwipeState, sign: CGFloat, cancelled: Bool) -> Bool {
        switch state {
        case .start:
            return self.begin(direction: sign)
        case let .swiping(delta, _):
            self.update(translation: delta * sign)
            return true
        case let .success(delta, _), let .failed(delta, _):
            self.end(translation: delta * sign, cancelled: cancelled)
            return true
        }
    }

    public func setOpened(_ value: Bool, animated: Bool) {
        guard self.motion.state != .filling, value != self.motion.wantsOpen else {
            return
        }
        if value {
            guard self.setupRevealView(direction: -1) else {
                return
            }
        }
        self.animationCompletion = nil
        self.motion.settle(to: value ? self.motion.parameters.openDistance : 0, velocity: self.motion.body.velocity, animated: animated && !self.reduceMotion)
        self.render()
        self.startAnimation()
    }

    public func animateFill(completion: (() -> Void)? = nil) {
        guard let size = self.size, self.activeView != nil else {
            completion?()
            return
        }
        self.animationCompletion = completion
        self.motion.settle(to: Double(size.width + 74), velocity: self.motion.body.velocity, animated: !self.reduceMotion, filling: true)
        self.render()
        self.startAnimation()
    }

    public func settleClosed(animated: Bool) {
        guard self.isActive else {
            return
        }
        self.animationCompletion = nil
        self.motion.settle(to: 0, velocity: 0, animated: animated && !self.reduceMotion)
        self.render()
        self.startAnimation()
    }

    public func reset(notify: Bool = false) {
        let wasActive = self.isActive
        self.animator?.invalidate()
        self.animator = nil
        self.previousAnimationTime = 0
        self.animationCompletion = nil
        self.translationSamples = []
        self.motion.reset()
        self.render()
        if notify && wasActive {
            self.interactivelyClosed?()
        }
    }

    private func deliver(_ option: RevealOption, animated: Bool) {
        guard !self.deliveringAction, self.motion.state != .filling else {
            return
        }
        self.deliveringAction = true
        self.optionSelected?(option, animated)
        self.deliveringAction = false
    }

    @discardableResult
    private func setupRevealView(direction: CGFloat) -> Bool {
        guard self.size != nil, let hostView = self.hostView else {
            return false
        }
        let options = direction > 0 ? self.options.left : self.options.right
        guard !options.isEmpty else {
            return false
        }
        self.revealDirection = direction
        if self.activeView == nil {
            let view = RevealOptionsView(isLeft: direction > 0, configuration: self.configuration, animationFactory: self.animationFactory)
            view.setOptions(options)
            view.optionSelected = { [weak self] option in
                self?.deliver(option, animated: false)
            }
            if direction > 0 {
                self.leftView = view
            } else {
                self.rightView = view
            }
            hostView.addSubview(view)
        }
        self.updateActiveMetrics()
        return true
    }

    private func updateActiveMetrics() {
        guard let size = self.size, let view = self.activeView else {
            return
        }
        let displayScale = self.hostView?.window?.backingScaleFactor ?? System.backingScale
        self.motion.configure(view.motionParameters(width: size.width, height: size.height, displayScale: displayScale))
    }

    private func removeViews() {
        self.leftView?.removeFromSuperview()
        self.rightView?.removeFromSuperview()
        self.leftView = nil
        self.rightView = nil
    }

    private func updateActive(_ isActive: Bool) {
        if self.isActive != isActive {
            self.isActive = isActive
            self.activeStateUpdated?(isActive)
        }
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }
        let displayScale = max(1, self.hostView?.window?.backingScaleFactor ?? System.backingScale)
        let value = (CGFloat(self.motion.body.value) * displayScale).rounded() / displayScale
        self.revealOffset = self.revealDirection * value
        self.updateActive(self.motion.state != .closed)
        if let size = self.size, let view = self.activeView {
            let distance = max(0, value)
            if self.revealDirection > 0 {
                view.frame = NSMakeRect(0, 0, distance, size.height)
            } else {
                view.frame = NSMakeRect(size.width - distance, 0, distance, size.height)
            }
            view.render(motion: self.motion)
        }
        self.offsetUpdated?(self.revealOffset)
        self.applySurface()
        let surface = (progress: self.surfaceProgress, opacity: self.surfaceOpacity)
        if surface != self.lastSurface {
            self.lastSurface = surface
            self.surfaceUpdated?(surface.progress, surface.opacity)
        }
        if self.motion.state == .closed {
            self.removeViews()
        }
    }

    private func applySurface() {
        let opacity = self.surfaceOpacity
        guard let surface = self.surface, let container = self.surfaceHost?.layer, opacity > 0 else {
            self.surfaceLayer?.removeFromSuperlayer()
            self.surfaceLayer = nil
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let layer: CALayer
        if let current = self.surfaceLayer, current.superlayer === container {
            layer = current
        } else {
            self.surfaceLayer?.removeFromSuperlayer()
            layer = CALayer()
            layer.zPosition = -2
            if #available(macOS 10.15, *) {
                layer.cornerCurve = .continuous
            }
            container.insertSublayer(layer, at: 0)
            self.surfaceLayer = layer
        }
        layer.frame = surface.frame
        layer.cornerRadius = surface.cornerRadius
        layer.backgroundColor = surface.color.cgColor
        layer.opacity = Float(opacity)
        CATransaction.commit()
    }

    private func startAnimation() {
        if self.motion.isAtRest {
            self.animator?.invalidate()
            self.animator = nil
            self.previousAnimationTime = 0
            let completion = self.animationCompletion
            self.animationCompletion = nil
            completion?()
            return
        }
        guard self.animator == nil else {
            return
        }
        self.previousAnimationTime = CACurrentMediaTime()
        let animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] _ in
            self?.advanceAnimation()
        })
        self.animator = animator
        animator.isPaused = false
    }

    private func advanceAnimation() {
        guard self.previousAnimationTime > 0 else {
            return
        }
        let now = CACurrentMediaTime()
        let dt = max(0, now - self.previousAnimationTime)
        self.previousAnimationTime = now
        if self.reduceMotion {
            self.motion.snapToTargets()
        }
        self.motion.advance(by: dt)
        self.render()
        self.startAnimation()
    }

    private func recordTranslation(_ translation: CGFloat) {
        let now = CACurrentMediaTime()
        self.lastTranslation = translation
        self.translationSamples.append((now, translation))
        self.translationSamples.removeAll(where: { now - $0.time > 0.1 })
    }

    private func currentVelocity() -> CGFloat {
        guard let first = self.translationSamples.first, let last = self.translationSamples.last else {
            return 0
        }
        let now = CACurrentMediaTime()
        guard now - last.time <= 0.1 else {
            return 0
        }
        let dt = last.time - first.time
        guard dt > 0.008 else {
            return 0
        }
        return (last.translation - first.translation) / CGFloat(dt)
    }
}
