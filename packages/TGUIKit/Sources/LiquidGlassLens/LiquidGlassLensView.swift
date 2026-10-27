import AppKit
import QuartzCore

private final class LensContentView: NSView {
    override var isFlipped: Bool {
        return true
    }
}

public final class LiquidGlassLensView: NSView {
    private struct SourceState: Equatable {
        let identifier: ObjectIdentifier
        let layerIdentifier: ObjectIdentifier?
        let frame: CGRect
        let bounds: CGRect
        let magnificationCenter: CGPoint
        let isHidden: Bool
        let lensedTintColor: NSColor?
        let unlensedTintColor: NSColor?
        let lensedScale: CGFloat
    }

    private struct State: Equatable {
        let frame: CGRect
        let progress: CGFloat
        let size: CGSize
        let scale: CGFloat
        let appearance: NSAppearance.Name
        let restingBlurRadius: CGFloat
        let restingTintColor: NSColor?
        let sources: [SourceState]
    }

    public let contentView: NSView = LensContentView(frame: .zero)
    private let backdropView = LensContentView(frame: .zero)
    private let contentClipView = LensContentView(frame: .zero)
    private let unlensedView = LensContentView(frame: .zero)
    private let surfaceView = LensContentView(frame: .zero)
    private let contentMask = CAShapeLayer()
    private let runtime: LensRuntime
    private var state: State?
    private var surface: LensSurface?
    private var restingBackdrop: LensRestingBackdrop?
    private var cleanup: DispatchWorkItem?
    private var generation = 0

    public static func make(frame: CGRect = .zero) -> LiquidGlassLensView? {
        guard #available(macOS 26.0, *), let runtime = LensRuntime.shared else {
            return nil
        }
        return LiquidGlassLensView(frame: frame, runtime: runtime)
    }

    private init(frame: CGRect, runtime: LensRuntime) {
        self.runtime = runtime
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        autoresizesSubviews = false
        for view in [backdropView, contentClipView, contentView, unlensedView, surfaceView] {
            view.wantsLayer = true
            view.layer?.masksToBounds = false
            view.autoresizesSubviews = false
            if #available(macOS 14.0, *) {
                view.clipsToBounds = false
            }
        }
        if #available(macOS 14.0, *) {
            clipsToBounds = false
        }
        for view in [backdropView, contentClipView, unlensedView, surfaceView] {
            addSubview(view)
        }
        contentClipView.addSubview(contentView)
        contentMask.anchorPoint = .zero
        contentMask.fillRule = .evenOdd
        contentMask.fillColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        cleanup?.cancel()
        surface?.remove()
    }

    public override var isFlipped: Bool {
        return true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            reset()
        }
    }

    public func update(lensFrame: CGRect, interactionProgress: CGFloat, appearance: NSAppearance, backingScale: CGFloat, animation: LiquidGlassLensAnimation, restingBlurRadius: CGFloat = 0, restingTintColor: NSColor? = nil, contentSources: [LiquidGlassLensContentSource]? = nil) {
        guard lensFrame.width.isFinite, lensFrame.height.isFinite, lensFrame.minX.isFinite, lensFrame.minY.isFinite,
              interactionProgress.isFinite, backingScale.isFinite, restingBlurRadius.isFinite else {
            reset()
            return
        }
        let sources = (contentSources ?? contentView.subviews.map { LiquidGlassLensContentSource(view: $0) }).filter {
            $0.view !== contentView && $0.view.isDescendant(of: contentView)
        }
        let sourceStates = sources.map { source -> SourceState in
            let view = source.view
            var root = view
            while let parent = root.superview, parent !== contentView {
                root = parent
            }
            let rootFrame = root.convert(root.bounds, to: contentView)
            return SourceState(identifier: ObjectIdentifier(view), layerIdentifier: view.layer.map(ObjectIdentifier.init), frame: view.convert(view.bounds, to: contentView), bounds: view.bounds, magnificationCenter: CGPoint(x: rootFrame.midX, y: rootFrame.midY), isHidden: view.isHiddenOrHasHiddenAncestor, lensedTintColor: source.lensedTintColor?.usingColorSpace(.sRGB), unlensedTintColor: source.unlensedTintColor?.usingColorSpace(.sRGB), lensedScale: source.lensedScale)
        }
        let next = State(
            frame: lensFrame,
            progress: min(1, max(0, interactionProgress)),
            size: bounds.size,
            scale: max(1, backingScale),
            appearance: appearance.name,
            restingBlurRadius: max(0, restingBlurRadius),
            restingTintColor: restingTintColor,
            sources: sourceStates
        )
        guard next != state else {
            return
        }
        let previous = state
        state = next
        let visibleSources = zip(sources, sourceStates).compactMap { source, state -> LensContentSource? in
            guard !state.isHidden, let layer = source.view.layer else {
                return nil
            }
            return LensContentSource(layer: layer, frame: state.frame, bounds: state.bounds, magnificationCenter: state.magnificationCenter, lensedTintColor: state.lensedTintColor, unlensedTintColor: state.unlensedTintColor, lensedScale: state.lensedScale)
        }
        generation += 1
        cleanup?.cancel()
        cleanup = nil
        self.appearance = appearance
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in [contentClipView, unlensedView] {
            view.frame = bounds
        }
        let renderBounds = bounds.union(next.frame).insetBy(dx: -LensSurface.renderOutset, dy: -LensSurface.renderOutset)
        for view in [backdropView, surfaceView] {
            view.frame = renderBounds
            view.bounds = renderBounds
        }
        contentView.frame = bounds
        contentMask.frame = bounds
        contentMask.contentsScale = next.scale
        if next.restingBlurRadius > 0, next.frame.width > 0, next.frame.height > 0 {
            if restingBackdrop == nil, let backdrop = LensRestingBackdrop(runtime: runtime) {
                restingBackdrop = backdrop
                backdropView.layer?.insertSublayer(backdrop.layer, at: 0)
                backdrop.update(frame: previous?.frame ?? next.frame, progress: previous?.progress ?? next.progress, blurRadius: next.restingBlurRadius, tintColor: next.restingTintColor, scale: next.scale, animation: .immediate)
            }
            restingBackdrop?.update(frame: next.frame, progress: next.progress, blurRadius: next.restingBlurRadius, tintColor: next.restingTintColor, scale: next.scale, animation: animation)
        } else {
            restingBackdrop?.remove()
            restingBackdrop = nil
        }
        if next.progress > 0, surface == nil, next.frame.width > 0, next.frame.height > 0,
           let surface = LensSurface(runtime: runtime) {
            self.surface = surface
            backdropView.layer?.addSublayer(surface.backdrop)
            unlensedView.layer?.addSublayer(surface.unlensedContent)
            surfaceView.layer?.addSublayer(surface.surface)
            let initialFrame = previous?.frame ?? next.frame
            surface.update(frame: initialFrame, progress: 0, canvasSize: next.size, sources: visibleSources, scale: next.scale, animation: .immediate)
            contentMask.path = maskPath(frame: initialFrame)
            surface.unlensedContent.mask = contentMask
        }
        if let surface {
            surface.update(frame: next.frame, progress: next.progress, canvasSize: next.size, sources: visibleSources, scale: next.scale, animation: animation)
            animation.update(contentMask, key: "path", value: maskPath(frame: next.frame))
        }
        CATransaction.commit()
        if next.progress == 0 {
            if animation.duration > 0, surface != nil {
                let generation = self.generation
                let cleanup = DispatchWorkItem { [weak self] in
                    guard let self, self.generation == generation, self.state?.progress == 0 else {
                        return
                    }
                    self.removeSurface()
                }
                self.cleanup = cleanup
                DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration, execute: cleanup)
            } else {
                removeSurface()
            }
        }
    }

    private func maskPath(frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.addRect(bounds.union(frame).insetBy(dx: -128, dy: -128))
        path.addRoundedRect(in: frame, cornerWidth: frame.height / 2, cornerHeight: frame.height / 2)
        return path
    }

    public func reset() {
        cleanup?.cancel()
        cleanup = nil
        generation += 1
        state = nil
        removeSurface()
        restingBackdrop?.remove()
        restingBackdrop = nil
    }

    private func removeSurface() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentClipView.layer?.mask = nil
        contentMask.removeAllAnimations()
        surface?.remove()
        surface = nil
        cleanup = nil
        CATransaction.commit()
    }

    var activePortalCount: Int {
        return surface?.portalCount ?? 0
    }

    var hasActiveSurface: Bool {
        return surface != nil
    }
}
