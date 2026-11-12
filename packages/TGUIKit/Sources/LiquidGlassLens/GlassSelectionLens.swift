import AppKit

public final class GlassSelectionLens {
    static let growDuration: TimeInterval = 0.3
    static let travelDelay: TimeInterval = 0.1
    static let travelDuration: TimeInterval = 0.4
    static let minimumLift: TimeInterval = 0.35
    static let dropDuration: TimeInterval = 0.45
    static let restingBlurRadius: CGFloat = 16

    private struct Request {
        let selection: NSRect?
        let clip: NSRect?
        let sources: [NSView]
        let appearance: NSAppearance
    }

    public private(set) var lensView: LiquidGlassLensView?
    public var onCancel: (() -> Void)?
    public var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    public var reduceTransparency: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    var lensFactory: () -> LiquidGlassLensView? = { LiquidGlassLensView.make() }
    var now: () -> CFTimeInterval = { CACurrentMediaTime() }

    private weak var host: NSView?
    private weak var selectionView: NSView?
    private var requestedMode: Bool?
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var request: Request?
    private var liftStartedAt: CFTimeInterval?
    private var restingSelection: NSRect?
    private var travel: DispatchWorkItem?
    private var drop: DispatchWorkItem?

    public init(host: NSView, selectionView: NSView) {
        self.host = host
        self.selectionView = selectionView
    }

    deinit {
        stopTracking()
        travel?.cancel()
        drop?.cancel()
    }

    public var contentView: NSView? {
        return lensView?.contentView
    }

    public var liftsOnPress: Bool {
        return lensView != nil && !reduceMotion()
    }

    var isLifted: Bool {
        return liftStartedAt != nil
    }

    @discardableResult
    public func updateMode(content: [NSView]) -> Bool {
        let enabled: Bool
        if #available(macOS 26.0, *) {
            enabled = System.liquidGlass && !reduceTransparency()
        } else {
            enabled = false
        }
        guard requestedMode != enabled, let host else {
            return false
        }
        requestedMode = enabled
        stopTracking()
        settle()
        if let lensView {
            lensView.reset()
            for view in content {
                host.addSubview(view, positioned: .below, relativeTo: lensView)
            }
            lensView.removeFromSuperview()
            self.lensView = nil
        }
        if enabled, let lens = lensFactory() {
            lensView = lens
            lens.didEnterWindow = { [weak self] in
                self?.refresh()
            }
            host.addSubview(lens)
            lens.frame = host.bounds
            lens.contentView.frame = host.bounds
            for view in content {
                lens.contentView.addSubview(view)
            }
        }
        selectionView?.layer?.removeAnimation(forKey: "opacity")
        selectionView?.layer?.opacity = lensView == nil ? 1 : 0
        return true
    }

    public func update(selection: NSRect?, clip: NSRect? = nil, lifted: Bool, sources: [NSView], appearance: NSAppearance, transition: ContainedViewLayoutTransition) {
        let request = Request(selection: selection, clip: clip, sources: sources, appearance: appearance)
        self.request = request
        let opacity: Float = lensView == nil ? 1 : 0
        if let selectionView, selectionView.layer?.opacity != opacity {
            selectionView.layer?.removeAnimation(forKey: "opacity")
            selectionView.layer?.opacity = opacity
        }
        guard lensView != nil else {
            return
        }
        if lifted && liftsOnPress {
            drop?.cancel()
            drop = nil
            if liftStartedAt == nil {
                liftStartedAt = now()
                if let resting = restingSelection, let target = selection, abs(resting.midX - target.midX) > 1 {
                    render(selection: resting, lifted: true, animation: .spring(duration: Self.growDuration))
                    let travel = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.travel = nil
                        if self.liftStartedAt != nil {
                            self.render(selection: self.request?.selection, lifted: true, animation: .spring(duration: Self.travelDuration))
                        }
                    }
                    self.travel = travel
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.travelDelay, execute: travel)
                    return
                }
            }
            if travel != nil {
                return
            }
            render(selection: selection, lifted: true, animation: Self.animation(transition))
            return
        }
        if let started = liftStartedAt {
            let remaining = Self.minimumLift - (now() - started)
            if remaining > 0 {
                if drop != nil {
                    return
                }
                if travel == nil {
                    render(selection: selection, lifted: true, animation: .spring(duration: Self.travelDuration))
                }
                let drop = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.drop = nil
                    self.liftStartedAt = nil
                    self.render(selection: self.request?.selection, lifted: false, animation: .spring(duration: Self.dropDuration))
                }
                self.drop = drop
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: drop)
                return
            }
            travel?.cancel()
            travel = nil
            liftStartedAt = nil
            render(selection: selection, lifted: false, animation: transition.isAnimated ? Self.animation(transition) : .spring(duration: Self.dropDuration))
            return
        }
        render(selection: selection, lifted: false, animation: Self.animation(transition))
    }

    private static func animation(_ transition: ContainedViewLayoutTransition) -> LiquidGlassLensAnimation {
        switch transition {
        case .immediate:
            return .immediate
        case let .animated(duration, curve):
            if case .spring = curve {
                return .spring(duration: duration)
            } else {
                return .animated(duration: duration, timingFunction: curve.timingFunction)
            }
        }
    }

    private func render(selection: NSRect?, lifted: Bool, animation: LiquidGlassLensAnimation) {
        guard let lensView, let host, let request else {
            return
        }
        lensView.frame = host.bounds
        lensView.contentView.frame = host.bounds
        guard var frame = selection, frame.width > 0, frame.height > 0 else {
            lensView.reset()
            return
        }
        if lifted {
            frame = host.convert(frame, to: lensView.contentView).insetBy(dx: -10, dy: -8)
        } else {
            restingSelection = frame
            if let clip = request.clip {
                frame = frame.intersection(clip)
                guard !frame.isNull, frame.width > 0, frame.height > 0 else {
                    lensView.reset()
                    return
                }
            }
            frame = host.convert(frame, to: lensView.contentView)
        }
        let contentSources = request.sources.map { view -> LiquidGlassLensContentSource in
            let rect = view.convert(view.bounds, to: lensView.contentView)
            return LiquidGlassLensContentSource(view: view, magnificationCenter: NSMakePoint(rect.midX, rect.midY))
        }
        let tint = (selectionView as? View)?.backgroundColor
        lensView.update(lensFrame: frame, interactionProgress: lifted ? 1 : 0, appearance: request.appearance, backingScale: host.window?.backingScaleFactor ?? System.backingScale, animation: animation, restingBlurRadius: Self.restingBlurRadius, restingTintColor: tint, contentSources: contentSources)
    }

    func refresh() {
        guard let request, lensView?.window != nil else {
            return
        }
        render(selection: request.selection, lifted: liftStartedAt != nil, animation: .immediate)
    }

    private func settle() {
        travel?.cancel()
        travel = nil
        drop?.cancel()
        drop = nil
        liftStartedAt = nil
        restingSelection = nil
    }

    public func startTracking() {
        stopTracking()
        guard let host else {
            return
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let host = self.host, event.window === host.window, event.keyCode == 53 else {
                return event
            }
            self.stopTracking()
            self.onCancel?()
            return nil
        }
        if let window = host.window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.stopTracking()
                self?.onCancel?()
            }
        }
    }

    public func stopTracking() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    public func reset() {
        stopTracking()
        settle()
        lensView?.reset()
    }
}
