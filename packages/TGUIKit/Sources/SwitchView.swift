import Cocoa
import AppKit

public struct SwitchViewAppearance : Equatable {
    let backgroundColor: NSColor
    let disabledColor: NSColor
    let stateOnColor: NSColor
    let stateOffColor: NSColor
    let borderColor: NSColor
    public init(backgroundColor: NSColor, stateOnColor: NSColor, stateOffColor: NSColor, disabledColor: NSColor, borderColor: NSColor) {
        self.backgroundColor = backgroundColor
        self.stateOnColor = stateOnColor
        self.stateOffColor = stateOffColor
        self.disabledColor = disabledColor
        self.borderColor = borderColor
        
    }
    
    public init(theme presentation: PresentationTheme) {
        self.init(backgroundColor: presentation.colors.background, stateOnColor: presentation.colors.accent, stateOffColor: presentation.colors.grayForeground, disabledColor: presentation.colors.grayTransparent, borderColor: presentation.colors.border)
    }
}

public var switchViewAppearance: SwitchViewAppearance {
    return SwitchViewAppearance(backgroundColor: presentation.colors.background, stateOnColor: presentation.colors.accent, stateOffColor: presentation.colors.grayForeground, disabledColor: presentation.colors.grayTransparent, borderColor: presentation.colors.border)
}


private final class SwitchContentView: NSView {
    override var isFlipped: Bool { true }
}

struct SwitchGeometry {
    let bounds: CGRect

    var scale: CGFloat {
        return max(0, min(bounds.width / 36, bounds.height / 20))
    }

    var track: CGRect {
        return CGRect(x: bounds.midX - 18 * scale, y: bounds.midY - 8 * scale, width: 36 * scale, height: 16 * scale)
    }

    var travel: CGFloat { 13 * scale }

    func thumb(position: CGFloat, lifted: Bool) -> CGRect {
        let size = CGSize(width: (lifted ? 32 : 20) * scale, height: (lifted ? 20 : 13) * scale)
        let center = CGPoint(x: track.minX + 11.5 * scale + travel * position, y: track.midY)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

enum SwitchMotion {
    static let response = 0.47
    static let dampingFraction = 0.7
    static let settlingDuration = 0.9879858824571184
    static let interactionDuration = 0.2

    static func spring(from: AnyObject, to: AnyObject, keyPath: String) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        let frequency = 2 * Double.pi / response
        animation.mass = 1
        animation.stiffness = frequency * frequency
        animation.damping = 2 * dampingFraction * frequency
        animation.duration = settlingDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fromValue = from
        animation.toValue = to
        return animation
    }

    static func interaction(from: AnyObject, to: AnyObject, keyPath: String) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.duration = interactionDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fromValue = from
        animation.toValue = to
        return animation
    }

    static func sample(_ animation: CASpringAnimation, elapsed: TimeInterval) -> (position: CGPoint, velocity: CGPoint)? {
        guard let from = (animation.fromValue as? NSValue)?.pointValue,
              let to = (animation.toValue as? NSValue)?.pointValue else { return nil }
        let rate = animation.damping / (2 * animation.mass)
        let frequency = sqrt(animation.stiffness / animation.mass - rate * rate)
        let time = max(0, elapsed)
        let decay = exp(-rate * time)
        func component(_ from: CGFloat, _ to: CGFloat) -> (CGFloat, CGFloat) {
            let displacement = Double(from - to)
            let initialVelocity = Double(to - from) * animation.initialVelocity
            let coefficient = (initialVelocity + rate * displacement) / frequency
            let value = displacement * cos(frequency * time) + coefficient * sin(frequency * time)
            let velocity = frequency * (-displacement * sin(frequency * time) + coefficient * cos(frequency * time)) - rate * value
            return (to + decay * value, decay * velocity)
        }
        let x = component(from.x, to.x)
        let y = component(from.y, to.y)
        return (CGPoint(x: x.0, y: y.0), CGPoint(x: x.1, y: y.1))
    }
}

public class SwitchView: Control {
    public static let preferredSize = CGSize(width: 36, height: 20)

    public var autoswitch = true
    public var presentation: SwitchViewAppearance = switchViewAppearance {
        didSet {
            if !updatingDefaultAppearance {
                usesDefaultAppearance = false
            }
            guard initialized else { return }
            updateColors()
            updateLens(animation: .immediate)
        }
    }
    public private(set) var isOn = false
    public var stateChanged: (() -> Void)?

    private struct Gesture {
        let start: CGPoint
        let initialPosition: CGFloat
        var dragged = false
    }

    private struct PendingChange {
        let target: Bool
        let notify: Bool
        let autoswitch: Bool
        let action: (() -> Void)?
    }

    private let trackView = SwitchContentView(frame: .zero)
    private let positionView = SwitchContentView(frame: .zero)
    private let thumbView = SwitchContentView(frame: .zero)
    private let thumbLayer = CALayer()
    private var gesture: Gesture?
    private var pendingChange: PendingChange?
    private var animationGeneration = 0
    private var activeMotions: [String: Int] = [:]
    private var initialized = false
    private var usesDefaultAppearance = true
    private var updatingDefaultAppearance = false
    private var ownsMouseSequence = false
    private var sendingPointerClick = false
    private var escapeMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    private var lensAppearance: NSAppearance?
    private var lifted = false
    private var dragOffset: CGFloat = 0
    private(set) var visualPosition: CGFloat = 0
    private(set) var nativeLens: LiquidGlassLensView?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var reduceTransparency: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    var lensFactory: () -> LiquidGlassLensView? = { LiquidGlassLensView.make() }

    var isTracking: Bool { gesture != nil }
    var isSettling: Bool { pendingChange != nil }
    var trackLayer: CALayer { trackView.layer! }
    var currentThumbFrame: CGRect { thumbLayer.frame.offsetBy(dx: positionView.frame.minX - bounds.minX + thumbView.frame.minX, dy: 0) }
    var appearanceAnimation: CAAnimationGroup? { thumbLayer.animation(forKey: "switchThumb") as? CAAnimationGroup }
    var positionAnimation: CASpringAnimation? { positionView.layer?.animation(forKey: "switchPosition") as? CASpringAnimation }
    private var geometry: SwitchGeometry { SwitchGeometry(bounds: bounds) }
    private var canInteract: Bool { isEnabled && userInteractionEnabled && !isHiddenOrHasHiddenAncestor }

    override convenience init() {
        self.init(frame: CGRect(origin: .zero, size: SwitchView.preferredSize))
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        if #available(macOS 14.0, *) {
            clipsToBounds = false
        }
        for view in [trackView, positionView, thumbView] {
            view.wantsLayer = true
            view.layer?.masksToBounds = false
            if #available(macOS 14.0, *) {
                view.clipsToBounds = false
            }
            view.setAccessibilityElement(false)
            view.layer?.disableActions()
        }
        addSubview(trackView)
        addSubview(positionView)
        positionView.addSubview(thumbView)
        thumbLayer.disableActions()
        thumbLayer.zPosition = 1
        thumbLayer.backgroundColor = NSColor.white.cgColor
        thumbLayer.shadowColor = NSColor.black.cgColor
        thumbLayer.shadowOpacity = 0.12
        thumbLayer.shadowRadius = 0.5
        thumbLayer.shadowOffset = CGSize(width: 0, height: -0.5)
        thumbView.layer?.addSublayer(thumbLayer)
        set(handler: { [weak self] _ in
            guard let self, !self.sendingPointerClick else { return }
            self.performToggle()
        }, for: .Click)
        initialized = true
        render(animated: false)
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelInteraction()
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setIsOn(_ isOn: Bool, animated: Bool = true) {
        invalidateInteraction()
        let changed = self.isOn != isOn
        self.isOn = isOn
        visualPosition = isOn ? 1 : 0
        render(animated: animated && !reduceMotion())
        if changed {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    public func performToggle() {
        let previousWindow = window
        finishPendingChange()
        guard canInteract, window === previousWindow else { return }
        invalidateInteraction()
        settle(to: !isOn)
    }

    func beginInteraction(at point: CGPoint) {
        let previousWindow = window
        finishPendingChange()
        guard canInteract, window === previousWindow, bounds.contains(point) else { return }
        invalidateInteraction()
        visualPosition = isOn ? 1 : 0
        gesture = Gesture(start: point, initialPosition: visualPosition)
        lifted = !reduceMotion()
        installEscapeMonitor()
        render(animated: !reduceMotion())
    }

    func dragInteraction(to point: CGPoint) {
        guard canInteract, var gesture else { return }
        let delta = CGPoint(x: point.x - gesture.start.x, y: point.y - gesture.start.y)
        gesture.dragged = gesture.dragged || hypot(delta.x, delta.y) >= 3
        self.gesture = gesture
        guard gesture.dragged else { return }
        let position = gesture.initialPosition + delta.x / max(geometry.travel, 0.001)
        let snappedPosition: CGFloat = position == 0.5 ? gesture.initialPosition : (position > 0.5 ? 1 : 0)
        let displacement = (position - snappedPosition) * geometry.travel
        let limit = 3 * geometry.scale
        dragOffset = limit > 0 ? displacement / (abs(displacement) + limit) * limit : 0
        guard snappedPosition != visualPosition else {
            activeMotions.removeValue(forKey: "switchOffset")
            thumbView.layer?.removeAnimation(forKey: "switchOffset")
            thumbView.frame = positionView.bounds.offsetBy(dx: dragOffset, dy: 0)
            return
        }
        visualPosition = snappedPosition
        render(animated: !reduceMotion())
    }

    func endInteraction(at point: CGPoint) {
        guard gesture != nil else { return }
        dragInteraction(to: point)
        guard let gesture, canInteract else {
            cancelInteraction()
            return
        }
        self.gesture = nil
        let target: Bool
        if gesture.dragged {
            target = visualPosition == 0.5 ? isOn : visualPosition > 0.5
        } else {
            target = bounds.contains(point) ? !isOn : isOn
        }
        settle(to: target)
    }

    func cancelInteraction() {
        invalidateInteraction()
        visualPosition = isOn ? 1 : 0
        render(animated: false)
        updateState()
    }

    private func invalidateInteraction() {
        activeMotions.removeAll()
        pendingChange = nil
        gesture = nil
        lifted = false
        dragOffset = 0
        let frame = thumbLayer.presentation()?.frame ?? thumbLayer.frame
        let radius = thumbLayer.presentation()?.cornerRadius ?? thumbLayer.cornerRadius
        let opacity = thumbLayer.presentation()?.opacity ?? thumbLayer.opacity
        thumbLayer.removeAllAnimations()
        thumbLayer.frame = frame
        thumbLayer.cornerRadius = radius
        thumbLayer.opacity = opacity
        for view in [positionView, thumbView] {
            let frame = view.layer?.presentation()?.frame ?? view.frame
            view.layer?.removeAllAnimations()
            view.frame = frame
        }
        trackLayer.removeAllAnimations()
        removeEscapeMonitor()
    }

    private func settle(to target: Bool) {
        pendingChange = PendingChange(target: target, notify: target != isOn, autoswitch: autoswitch, action: stateChanged)
        visualPosition = (autoswitch ? target : isOn) ? 1 : 0
        lifted = false
        dragOffset = 0
        installEscapeMonitor()
        render(animated: !reduceMotion() && window != nil)
    }

    private func finishPendingChange() {
        guard let pendingChange else { return }
        self.pendingChange = nil
        activeMotions.removeAll()
        thumbLayer.removeAllAnimations()
        trackLayer.removeAllAnimations()
        removeEscapeMonitor()
        render(animated: false)
        guard pendingChange.notify, canInteract else { return }
        if pendingChange.autoswitch {
            isOn = pendingChange.target
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
        pendingChange.action?()
    }

    private func updateColors() {
        let color: NSColor
        if visualPosition == 0 {
            color = presentation.stateOffColor
        } else if visualPosition == 1 {
            color = presentation.stateOnColor
        } else {
            color = presentation.stateOffColor.blended(withFraction: visualPosition, of: presentation.stateOnColor) ?? presentation.stateOffColor
        }
        trackLayer.backgroundColor = (isEnabled ? color : presentation.disabledColor).cgColor
        thumbLayer.backgroundColor = NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.6).cgColor
    }

    private func addMotion(_ animation: CAAnimation, to layer: CALayer, key: String) {
        animationGeneration += 1
        let generation = animationGeneration
        activeMotions[key] = generation
        if animation is CASpringAnimation {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        }
        animation.delegate = CALayerAnimationDelegate(completion: { [weak self] finished in
            guard let self, self.activeMotions[key] == generation else { return }
            self.activeMotions.removeValue(forKey: key)
            if !finished {
                self.cancelInteraction()
            } else if self.activeMotions.isEmpty {
                self.finishPendingChange()
            }
        })
        layer.add(animation, forKey: key)
    }

    private func render(animated: Bool) {
        guard initialized else { return }
        let previousFrame = thumbLayer.presentation()?.frame ?? thumbLayer.frame
        let previousRadius = thumbLayer.presentation()?.cornerRadius ?? thumbLayer.cornerRadius
        let previousOpacity = thumbLayer.presentation()?.opacity ?? thumbLayer.opacity
        let previousColor = trackLayer.presentation()?.backgroundColor ?? trackLayer.backgroundColor
        let previousTargetColor = trackLayer.backgroundColor
        let previousPosition = positionView.layer?.presentation()?.position ?? positionView.layer?.position ?? .zero
        let previousTargetPosition = positionView.layer?.position
        let previousOffset = thumbView.layer?.presentation()?.position ?? thumbView.layer?.position ?? .zero
        let previousTargetOffset = thumbView.layer?.position
        positionView.frame = bounds.offsetBy(dx: geometry.travel * visualPosition, dy: 0)
        thumbView.frame = positionView.bounds.offsetBy(dx: dragOffset, dy: 0)
        trackView.frame = geometry.track
        trackLayer.cornerRadius = geometry.track.height / 2
        updateColors()
        let frame = geometry.thumb(position: 0, lifted: lifted)
        thumbLayer.frame = frame
        thumbLayer.cornerRadius = frame.height / 2
        updateLens(animation: animated ? .animated(duration: SwitchMotion.interactionDuration, timingFunction: .easeInEaseOut) : .immediate)
        if animated {
            if let layer = positionView.layer, previousTargetPosition != layer.position {
                var position = previousPosition
                var velocity = CGPoint.zero
                if let previous = layer.animation(forKey: "switchPosition") as? CASpringAnimation,
                   let sample = SwitchMotion.sample(previous, elapsed: (layer.convertTime(CACurrentMediaTime(), from: nil) - previous.beginTime) * Double(previous.speed)) {
                    position = sample.position
                    velocity = sample.velocity
                }
                let animation = SwitchMotion.spring(from: NSValue(point: position), to: NSValue(point: layer.position), keyPath: "position")
                let distance = layer.position.x - position.x
                if abs(distance) > 0.0001 {
                    animation.initialVelocity = velocity.x / distance
                }
                addMotion(animation, to: layer, key: "switchPosition")
            }
            if let layer = thumbView.layer, previousTargetOffset != layer.position {
                addMotion(SwitchMotion.spring(from: NSValue(point: previousOffset), to: NSValue(point: layer.position), keyPath: "position"), to: layer, key: "switchOffset")
            }
            if let previousColor, let color = trackLayer.backgroundColor, previousTargetColor != color {
                addMotion(SwitchMotion.spring(from: previousColor, to: color, keyPath: "backgroundColor"), to: trackLayer, key: "switchTrack")
            }
            let animation = CAAnimationGroup()
            animation.duration = SwitchMotion.interactionDuration
            animation.animations = [
                SwitchMotion.interaction(from: NSValue(point: CGPoint(x: previousFrame.midX, y: previousFrame.midY)), to: NSValue(point: CGPoint(x: frame.midX, y: frame.midY)), keyPath: "position"),
                SwitchMotion.interaction(from: NSValue(rect: CGRect(origin: .zero, size: previousFrame.size)), to: NSValue(rect: CGRect(origin: .zero, size: frame.size)), keyPath: "bounds"),
                SwitchMotion.interaction(from: NSNumber(value: previousRadius), to: NSNumber(value: thumbLayer.cornerRadius), keyPath: "cornerRadius"),
                SwitchMotion.interaction(from: NSNumber(value: previousOpacity), to: NSNumber(value: thumbLayer.opacity), keyPath: "opacity")
            ]
            addMotion(animation, to: thumbLayer, key: "switchThumb")
        } else {
            activeMotions.removeAll()
            for layer in [thumbLayer, trackLayer, positionView.layer, thumbView.layer].compactMap({ $0 }) {
                layer.removeAllAnimations()
            }
            finishPendingChange()
        }
    }

    private func updateLens(animation: LiquidGlassLensAnimation) {
        let enabled = System.liquidGlass && !reduceTransparency() && (lifted || animation.duration > 0)
        if !enabled, let nativeLens {
            self.nativeLens = nil
            nativeLens.reset()
            nativeLens.removeFromSuperview()
        } else if enabled, nativeLens == nil, let lens = lensFactory() {
            nativeLens = lens
            lens.setAccessibilityElement(false)
            thumbView.addSubview(lens)
            lens.frame = bounds
            lens.update(lensFrame: geometry.thumb(position: 0, lifted: false), interactionProgress: 0, appearance: lensAppearance ?? effectiveAppearance, backingScale: window?.backingScaleFactor ?? System.backingScale, animation: .immediate, contentSources: [])
        }
        if let nativeLens {
            nativeLens.frame = bounds
            nativeLens.update(lensFrame: geometry.thumb(position: 0, lifted: lifted), interactionProgress: lifted ? 1 : 0, appearance: lensAppearance ?? effectiveAppearance, backingScale: window?.backingScaleFactor ?? System.backingScale, animation: animation, contentSources: [])
        }
        thumbLayer.opacity = nativeLens?.hasActiveSurface == true && lifted ? 0 : 1
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil, window != nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.keyCode == 53 else { return event }
            self.cancelInteraction()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    public override var isEnabled: Bool {
        didSet {
            guard initialized else { return }
            if !isEnabled {
                cancelInteraction()
            } else {
                updateColors()
            }
        }
    }

    public override var userInteractionEnabled: Bool {
        didSet {
            if initialized, !userInteractionEnabled {
                cancelInteraction()
            }
        }
    }

    public override func apply(state: ControlState) {
        super.apply(state: state)
        if initialized {
            updateColors()
        }
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        lensAppearance = theme.appearance
        if usesDefaultAppearance {
            updatingDefaultAppearance = true
            presentation = SwitchViewAppearance(theme: theme)
            updatingDefaultAppearance = false
        }
        updateLens(animation: .immediate)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard canInteract, !isEventLess, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    public override func mouseDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.control), canInteract else {
            super.mouseDown(with: event)
            return
        }
        beginInteraction(at: convert(event.locationInWindow, from: nil))
        ownsMouseSequence = isTracking
        if ownsMouseSequence {
            controlState = .Highlight
            send(event: .Down)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard ownsMouseSequence else {
            super.mouseDragged(with: event)
            return
        }
        dragInteraction(to: convert(event.locationInWindow, from: nil))
        send(event: .MouseDragging)
    }

    public override func mouseUp(with event: NSEvent) {
        guard ownsMouseSequence else {
            super.mouseUp(with: event)
            return
        }
        ownsMouseSequence = false
        guard let gesture else { return }
        let point = convert(event.locationInWindow, from: nil)
        let click = !gesture.dragged && hypot(point.x - gesture.start.x, point.y - gesture.start.y) < 3 && bounds.contains(point)
        endInteraction(at: point)
        send(event: .Up)
        if click {
            sendingPointerClick = true
            send(event: .SingleClick)
            send(event: .Click)
            sendingPointerClick = false
        }
        Control.lastHandledClickTimestamp = CACurrentMediaTime()
        updateState()
    }

    public override var acceptsFirstResponder: Bool { canInteract }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, isTracking || isSettling {
            cancelInteraction()
        } else if event.keyCode == 49, !event.isARepeat, canInteract {
            performToggle()
        } else {
            super.keyDown(with: event)
        }
    }

    public override func viewDidHide() {
        super.viewDidHide()
        if initialized { cancelInteraction() }
    }

    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        if initialized, newSuperview == nil { cancelInteraction() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        guard initialized else { return }
        cancelInteraction()
        if let window {
            for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: name == NSWindow.didResignKeyNotification ? window : nil, queue: .main) { [weak self] _ in
                    self?.cancelInteraction()
                })
            }
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if initialized, changed { cancelInteraction() }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if initialized { updateLens(animation: .immediate) }
    }

    public override func isAccessibilityElement() -> Bool {
        return TGUIKitAccessibility.isEnabled && !isAccessibilityDecorative && !isHidden
    }

    public override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }

    public override func accessibilityValue() -> Any? { NSNumber(value: isOn ? 1 : 0) }

    public override func accessibilityChildren() -> [Any]? { [] }

    deinit {
        removeEscapeMonitor()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let displayObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayObserver)
        }
        nativeLens?.reset()
    }
}
