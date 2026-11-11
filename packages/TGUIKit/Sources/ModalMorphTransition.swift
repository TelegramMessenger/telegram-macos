import Cocoa

// A reusable "morph a modal from / to its triggering control" transition, built on the same
// spring-driven bubble technique as the call-window and story morphs (not a crossfade dissolve):
// a single rounded bubble springs its frame and corner radius between the control and the modal,
// the modal image fills it, and the control snapshot fades out as it grows. Open bounces out from
// the control; close settles back onto it.
public final class ModalMorphTransition {
    public static var reduceMotion: () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // Debug/lab seam: multiplies the played duration (motion profile unchanged). 1 = ship speed.
    public static var durationScale: () -> Double = { 1 }

    static let sampleRate: Double = 120
    static let maximumDuration: Double = 1.5
    static let geometryTolerance: CGFloat = 0.2
    static let unitTolerance: CGFloat = 0.002
    static let shadowOpacity: Float = 0.26
    static let shadowRadius: CGFloat = 20

    struct Spring {
        let omega: Double
        let damping: Double

        // Open: underdamped position/size for a visible bounce out of the control.
        static let openPosition = Spring(omega: 20.5, damping: 0.82)
        static let openWidth = Spring(omega: 22.0, damping: 0.74)
        static let openHeight = Spring(omega: 19.0, damping: 0.76)
        static let openFade = Spring(omega: 21.0, damping: 1.0)
        static let closePosition = Spring(omega: 22.0, damping: 1.0)
        static let closeWidth = Spring(omega: 23.0, damping: 1.0)
        static let closeHeight = Spring(omega: 21.0, damping: 1.0)
        static let closeFade = Spring(omega: 23.5, damping: 1.0)

        func remaining(at time: Double) -> CGFloat {
            if self.damping < 1 {
                let dampedOmega = self.omega * sqrt(1 - self.damping * self.damping)
                return CGFloat(exp(-self.damping * self.omega * time) * (cos(dampedOmega * time) + self.damping * self.omega / dampedOmega * sin(dampedOmega * time)))
            }
            return CGFloat((1 + self.omega * time) * exp(-self.omega * time))
        }

        func remainingVelocity(at time: Double) -> CGFloat {
            if self.damping < 1 {
                let dampedOmega = self.omega * sqrt(1 - self.damping * self.damping)
                return CGFloat(-exp(-self.damping * self.omega * time) * self.omega * self.omega / dampedOmega * sin(dampedOmega * time))
            }
            return CGFloat(-self.omega * self.omega * time * exp(-self.omega * time))
        }

        func impulse(at time: Double) -> CGFloat {
            if self.damping < 1 {
                let dampedOmega = self.omega * sqrt(1 - self.damping * self.damping)
                return CGFloat(exp(-self.damping * self.omega * time) * sin(dampedOmega * time) / dampedOmega)
            }
            return CGFloat(time * exp(-self.omega * time))
        }

        func impulseVelocity(at time: Double) -> CGFloat {
            if self.damping < 1 {
                let dampedOmega = self.omega * sqrt(1 - self.damping * self.damping)
                return CGFloat(exp(-self.damping * self.omega * time) * (cos(dampedOmega * time) - self.damping * self.omega / dampedOmega * sin(dampedOmega * time)))
            }
            return CGFloat((1 - self.omega * time) * exp(-self.omega * time))
        }
    }

    struct Channel {
        let from: CGFloat
        let to: CGFloat
        let spring: Spring
        let tolerance: CGFloat
        let initialVelocity: CGFloat

        init(from: CGFloat, to: CGFloat, spring: Spring, tolerance: CGFloat, initialVelocity: CGFloat = 0) {
            self.from = from
            self.to = to
            self.spring = spring
            self.tolerance = tolerance
            self.initialVelocity = initialVelocity
        }

        func value(at time: Double) -> CGFloat {
            return self.to + (self.from - self.to) * self.spring.remaining(at: time) + self.initialVelocity * self.spring.impulse(at: time)
        }

        func velocity(at time: Double) -> CGFloat {
            return (self.from - self.to) * self.spring.remainingVelocity(at: time) + self.initialVelocity * self.spring.impulseVelocity(at: time)
        }

        var settlingTime: Double {
            let step = 1 / ModalMorphTransition.sampleRate
            var time = ModalMorphTransition.maximumDuration
            while time > 0, abs(self.value(at: time) - self.to) <= self.tolerance {
                time -= step
            }
            return min(ModalMorphTransition.maximumDuration, max(0, time + step))
        }
    }

    private struct Segment {
        let channels: [Channel]
        let modal: NSRect
        let contentSize: CGSize
        let startSize: CGSize
        let startFraction: CGFloat
        let duration: Double

        init(channels: [Channel], modal: NSRect, contentSize: CGSize, startSize: CGSize, startFraction: CGFloat) {
            self.channels = channels
            self.modal = modal
            self.contentSize = contentSize
            self.startSize = startSize
            self.startFraction = startFraction
            self.duration = channels.map { $0.settlingTime }.max() ?? 0
        }

        func sizeFraction(width: CGFloat, height: CGFloat) -> CGFloat {
            let growth = [(width - self.startSize.width, self.modal.width - self.startSize.width), (height - self.startSize.height, self.modal.height - self.startSize.height)].filter { abs($0.1) >= 1 }
            let progress = growth.isEmpty ? 1 : max(0, min(1, growth.reduce(0) { $0 + $1.0 / $1.1 } / CGFloat(growth.count)))
            return self.startFraction + (1 - self.startFraction) * progress
        }
    }

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else {
            return x < edge0 ? 0 : 1
        }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private let host: NSView
    private let bubbleView: NSView
    private let maskLayer: CAShapeLayer
    private let controlLayer: CALayer
    private weak var realView: NSView?
    private let opening: Bool
    private let control: NSRect
    private let cornerRadius: CGFloat
    private let controlCornerRadius: CGFloat
    private let controlCorners: CACornerMask
    private let hasControl: Bool
    private let borderWidth: CGFloat
    private let backgroundColor: CGColor?
    private let contentAnchor: CGPoint
    private let completion: () -> Void
    private var finished = false
    fileprivate var autoFinishOnComplete = true
    private var segment: Segment?
    private var segmentBeginTime: CFTimeInterval = 0
    private var generation = 0

    var isOpening: Bool {
        return self.opening && !self.finished
    }

    private init(host: NSView, bubbleView: NSView, shadowView: NSView, maskLayer: CAShapeLayer, controlLayer: CALayer, realView: NSView?, opening: Bool, control: NSRect, cornerRadius: CGFloat, controlCornerRadius: CGFloat, controlCorners: CACornerMask, hasControl: Bool, borderWidth: CGFloat, backgroundColor: CGColor?, contentAnchor: CGPoint, completion: @escaping () -> Void) {
        self.host = host
        self.bubbleView = bubbleView
        self.extraView = shadowView
        self.maskLayer = maskLayer
        self.controlLayer = controlLayer
        self.realView = realView
        self.opening = opening
        self.control = control
        self.cornerRadius = cornerRadius
        self.controlCornerRadius = controlCornerRadius
        self.controlCorners = controlCorners
        self.hasControl = hasControl
        self.borderWidth = borderWidth
        self.backgroundColor = backgroundColor
        self.contentAnchor = contentAnchor
        self.completion = completion
    }

    @discardableResult
    public static func open(host: NSView, realView: NSView?, liveContent: NSView?, restoreLiveContent: ((NSView) -> Void)? = nil, controlImage: CGImage?, modalImage: CGImage?, backgroundColor: CGColor?, borderWidth: CGFloat = 0, borderColor: CGColor? = nil, cornerRadius: CGFloat, controlCornerRadius: CGFloat, controlCorners: CACornerMask = morphAllCorners, from controlRect: NSRect, to modalRect: NSRect, completion: @escaping () -> Void) -> ModalMorphTransition? {
        return run(host: host, realView: realView, liveContent: liveContent, restoreLiveContent: restoreLiveContent, controlImage: controlImage, modalImage: modalImage, backgroundColor: backgroundColor, borderWidth: borderWidth, borderColor: borderColor, cornerRadius: cornerRadius, controlCornerRadius: controlCornerRadius, controlCorners: controlCorners, control: controlRect, modal: modalRect, opening: true, completion: completion)
    }

    @discardableResult
    public static func close(host: NSView, realView: NSView?, liveContent: NSView?, restoreLiveContent: ((NSView) -> Void)? = nil, controlImage: CGImage?, modalImage: CGImage?, backgroundColor: CGColor?, borderWidth: CGFloat = 0, borderColor: CGColor? = nil, cornerRadius: CGFloat, controlCornerRadius: CGFloat, controlCorners: CACornerMask = morphAllCorners, to controlRect: NSRect, from modalRect: NSRect, completion: @escaping () -> Void) -> ModalMorphTransition? {
        return run(host: host, realView: realView, liveContent: liveContent, restoreLiveContent: restoreLiveContent, controlImage: controlImage, modalImage: modalImage, backgroundColor: backgroundColor, borderWidth: borderWidth, borderColor: borderColor, cornerRadius: cornerRadius, controlCornerRadius: controlCornerRadius, controlCorners: controlCorners, control: controlRect, modal: modalRect, opening: false, completion: completion)
    }

    private static func run(host: NSView, realView: NSView?, liveContent: NSView?, restoreLiveContent: ((NSView) -> Void)?, controlImage: CGImage?, modalImage: CGImage?, backgroundColor: CGColor?, borderWidth: CGFloat, borderColor: CGColor?, cornerRadius: CGFloat, controlCornerRadius: CGFloat, controlCorners: CACornerMask, control: NSRect, modal: NSRect, opening: Bool, completion: @escaping () -> Void) -> ModalMorphTransition? {
        let liveView: NSView? = (liveContent?.frame.width ?? 0) >= 1 && (liveContent?.frame.height ?? 0) >= 1 ? liveContent : nil
        let modalImg = liveView != nil ? nil : (modalImage ?? realView.flatMap { snapshotImage($0) })
        guard !reduceMotion(), liveView != nil || modalImg != nil, control.width >= 1, control.height >= 1, modal.width >= 1, modal.height >= 1 else {
            completion()
            return nil
        }
        let scale = host.window?.backingScaleFactor ?? 2

        let bubbleView = NSView(frame: modal)
        bubbleView.wantsLayer = true
        guard let bubble = bubbleView.layer else {
            completion()
            return nil
        }
        bubble.masksToBounds = true
        bubble.backgroundColor = backgroundColor
        bubble.borderWidth = borderWidth
        bubble.borderColor = borderColor
        bubble.contents = modalImg
        bubble.contentsGravity = .resizeAspectFill
        bubble.contentsScale = scale
        if #available(macOS 10.15, *) {
            bubble.cornerCurve = .continuous
        }

        let maskLayer = CAShapeLayer()
        maskLayer.anchorPoint = .zero
        maskLayer.position = .zero
        maskLayer.contentsScale = scale
        maskLayer.disableActions()

        let shadowView = NSView(frame: modal)
        shadowView.wantsLayer = true
        guard let shadow = shadowView.layer else {
            completion()
            return nil
        }
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowRadius = shadowRadius
        shadow.shadowOffset = .zero

        let controlLayer = CALayer()
        controlLayer.contents = controlImage
        controlLayer.contentsGravity = .resize
        controlLayer.contentsScale = scale
        controlLayer.masksToBounds = true
        controlLayer.zPosition = 1

        let contentSize: CGSize
        let contentAnchor: CGPoint
        if let liveView = liveView {
            contentSize = NSMakeSize(max(1, liveView.frame.width), max(1, liveView.frame.height))
            contentAnchor = liveView.layer?.anchorPoint ?? NSMakePoint(0, 0)
        } else {
            contentSize = NSMakeSize(max(1, modal.width), max(1, modal.height))
            contentAnchor = NSMakePoint(0, 0)
        }

        let transition = ModalMorphTransition(host: host, bubbleView: bubbleView, shadowView: shadowView, maskLayer: maskLayer, controlLayer: controlLayer, realView: realView, opening: opening, control: control, cornerRadius: cornerRadius, controlCornerRadius: controlCornerRadius, controlCorners: controlCorners, hasControl: controlImage != nil, borderWidth: borderWidth, backgroundColor: backgroundColor, contentAnchor: contentAnchor, completion: completion)
        transition.autoFinishOnComplete = opening

        if let liveView = liveView {
            transition.liveContent = liveView
            transition.restoreLiveContent = restoreLiveContent
            transition.liveContentSuperview = liveView.superview
            transition.liveContentFrame = liveView.frame
            transition.liveContentAutoresizing = liveView.autoresizingMask
            liveView.autoresizingMask = []
            liveView.frame = CGRect(origin: .zero, size: contentSize)
        }

        if opening {
            realView?.isHidden = true
        }
        let revealBubble = prepareLayerAnimation([shadowView, bubbleView]) {
            host.addSubview(shadowView)
            host.addSubview(bubbleView)
            if let liveView {
                bubbleView.addSubview(liveView)
            }
            bubble.addSublayer(controlLayer)
        }

        let start = opening ? control : modal
        let end = opening ? modal : control
        let positionSpring = opening ? Spring.openPosition : Spring.closePosition
        let widthSpring = opening ? Spring.openWidth : Spring.closeWidth
        let heightSpring = opening ? Spring.openHeight : Spring.closeHeight
        let channels = [
            Channel(from: start.midX, to: end.midX, spring: positionSpring, tolerance: geometryTolerance),
            Channel(from: start.midY, to: end.midY, spring: positionSpring, tolerance: geometryTolerance),
            Channel(from: start.width, to: end.width, spring: widthSpring, tolerance: geometryTolerance),
            Channel(from: start.height, to: end.height, spring: heightSpring, tolerance: geometryTolerance)
        ]
        transition.animate(Segment(channels: channels, modal: modal, contentSize: contentSize, startSize: control.size, startFraction: 0))
        revealBubble()
        realView?.isHidden = true
        return transition
    }

    func retarget(to modal: NSRect, contentSize: CGSize) {
        guard self.opening, !self.finished, let segment = self.segment, modal != segment.modal, modal.width >= 1, modal.height >= 1 else {
            return
        }
        let elapsed = max(0, (CACurrentMediaTime() - self.segmentBeginTime) / max(0.0001, ModalMorphTransition.durationScale()))
        let settled = elapsed >= segment.duration
        let values = segment.channels.map { settled ? $0.to : $0.value(at: elapsed) }
        let velocities = segment.channels.map { settled ? 0 : $0.velocity(at: elapsed) }
        let width = max(1, values[2])
        let height = max(1, values[3])
        let targets = [modal.midX, modal.midY, modal.width, modal.height]
        let springs = [Spring.openPosition, Spring.openPosition, Spring.openWidth, Spring.openHeight]
        let channels = (0 ..< targets.count).map {
            Channel(from: values[$0], to: targets[$0], spring: springs[$0], tolerance: ModalMorphTransition.geometryTolerance, initialVelocity: velocities[$0])
        }
        self.bubbleView.frame = modal
        self.extraView?.frame = modal
        let size: CGSize
        if let liveView = self.liveContent {
            size = NSMakeSize(max(1, contentSize.width), max(1, contentSize.height))
            liveView.frame = CGRect(origin: .zero, size: size)
            self.liveContentFrame.size = size
            liveView.layoutSubtreeIfNeeded()
        } else {
            size = NSMakeSize(max(1, modal.width), max(1, modal.height))
        }
        self.animate(Segment(channels: channels, modal: modal, contentSize: size, startSize: NSMakeSize(width, height), startFraction: segment.sizeFraction(width: width, height: height)))
    }

    private func animate(_ segment: Segment) {
        guard let bubble = self.bubbleView.layer, let shadow = self.extraView?.layer else {
            return
        }
        self.segment = segment
        self.generation += 1
        let generation = self.generation
        let control = self.control
        let modal = segment.modal
        let contentSize = segment.contentSize
        let cornerRadius = self.cornerRadius
        let controlCornerRadius = self.controlCornerRadius
        let controlCorners = self.controlCorners
        let perCorner = controlCorners != morphAllCorners
        let hasControl = self.hasControl
        let borderWidth = self.borderWidth
        let backgroundColor = self.backgroundColor
        let bubbleAnchor = bubble.anchorPoint
        let contentAnchor = self.contentAnchor
        let maskLayer = self.maskLayer
        let controlLayer = self.controlLayer
        let duration = segment.duration
        let play = max(0.0001, duration * ModalMorphTransition.durationScale())
        let count = max(2, Int(ceil(play * ModalMorphTransition.sampleRate)) + 1)

        var keyTimes: [NSNumber] = []
        var positions: [Any] = []
        var bounds: [Any] = []
        var radii: [Any] = []
        var maskPaths: [Any] = []
        var shadowPaths: [Any] = []
        var shadowOpacities: [Any] = []
        var controlPositions: [Any] = []
        var controlBounds: [Any] = []
        var controlOpacities: [Any] = []
        var contentPositions: [Any] = []
        var contentTransforms: [Any] = []
        var contentOpacities: [Any] = []
        var borderWidths: [Any] = []
        var backgroundColors: [CGColor] = []
        for index in 0 ..< count {
            let fraction = Double(index) / Double(count - 1)
            let values = index == count - 1 ? segment.channels.map { $0.to } : segment.channels.map { $0.value(at: fraction * duration) }
            let width = max(1, values[2])
            let height = max(1, values[3])
            let rect = NSMakeRect(values[0] - width / 2, values[1] - height / 2, width, height)
            let sizeFraction = segment.sizeFraction(width: width, height: height)
            let radius = min(min(width, height) / 2, controlCornerRadius + (cornerRadius - controlCornerRadius) * sizeFraction)
            let controlAlpha = hasControl ? 1 - ModalMorphTransition.smoothstep(0.05, 0.4, sizeFraction) : 0
            let paperAlpha = hasControl ? ModalMorphTransition.smoothstep(0.05, 0.2, sizeFraction) : 1
            let controlWidth = min(control.width, width)
            let controlHeight = min(control.height, height)
            let boundsRect = NSMakeRect(0, 0, width, height)

            keyTimes.append(NSNumber(value: fraction))
            positions.append(NSValue(point: NSMakePoint(rect.minX + bubbleAnchor.x * width, rect.minY + bubbleAnchor.y * height)))
            bounds.append(NSValue(rect: boundsRect))
            if perCorner {
                let square = max(0, min(min(width, height) / 2, cornerRadius * sizeFraction))
                let bottomLeft = controlCorners.contains(.layerMinXMinYCorner) ? radius : square
                let bottomRight = controlCorners.contains(.layerMaxXMinYCorner) ? radius : square
                let topRight = controlCorners.contains(.layerMaxXMaxYCorner) ? radius : square
                let topLeft = controlCorners.contains(.layerMinXMaxYCorner) ? radius : square
                let path = ModalMorphTransition.cornerPath(boundsRect, bottomLeft: bottomLeft, bottomRight: bottomRight, topRight: topRight, topLeft: topLeft)
                maskPaths.append(path)
                shadowPaths.append(path)
            } else {
                radii.append(NSNumber(value: Double(radius)))
                shadowPaths.append(CGPath(roundedRect: boundsRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            shadowOpacities.append(NSNumber(value: Double(CGFloat(ModalMorphTransition.shadowOpacity) * (backgroundColor?.alpha ?? 1) * ModalMorphTransition.smoothstep(0, 0.2, sizeFraction) * paperAlpha)))
            borderWidths.append(NSNumber(value: Double(borderWidth * ModalMorphTransition.smoothstep(0, 0.3, sizeFraction) * paperAlpha)))
            if let backgroundColor {
                backgroundColors.append(backgroundColor.copy(alpha: backgroundColor.alpha * paperAlpha) ?? backgroundColor)
            }
            controlPositions.append(NSValue(point: NSMakePoint(width / 2, height / 2)))
            controlBounds.append(NSValue(rect: NSMakeRect(0, 0, controlWidth, controlHeight)))
            controlOpacities.append(NSNumber(value: Double(controlAlpha)))
            let contentAlpha = hasControl ? ModalMorphTransition.smoothstep(0.05, 0.4, sizeFraction) : 1
            contentOpacities.append(NSNumber(value: Double(contentAlpha)))

            let contentScale: CGFloat
            if backgroundColor?.alpha == 0 {
                contentScale = min(width / contentSize.width, height / contentSize.height)
            } else {
                contentScale = max(width / modal.width, height / modal.height)
            }
            let contentOriginX = (width - contentSize.width * contentScale) / 2
            let contentOriginY = (height - contentSize.height * contentScale) / 2
            contentPositions.append(NSValue(point: NSMakePoint(contentOriginX + contentAnchor.x * contentSize.width * contentScale, contentOriginY + contentAnchor.y * contentSize.height * contentScale)))
            contentTransforms.append(NSValue(caTransform3D: CATransform3DMakeScale(contentScale, contentScale, 1)))
        }

        let contentLayer = self.liveContent?.layer
        let end = self.opening ? modal : control
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bubble.position = (positions.last as? NSValue)?.pointValue ?? NSMakePoint(end.midX, end.midY)
        bubble.bounds = (bounds.last as? NSValue)?.rectValue ?? NSMakeRect(0, 0, end.width, end.height)
        if perCorner {
            bubble.cornerRadius = 0
            maskLayer.bounds = (bounds.last as? NSValue)?.rectValue ?? NSMakeRect(0, 0, end.width, end.height)
            maskLayer.path = maskPaths.last.map { $0 as! CGPath }
            bubble.mask = maskLayer
        } else {
            bubble.cornerRadius = CGFloat((radii.last as? NSNumber)?.doubleValue ?? 0)
        }
        bubble.borderWidth = CGFloat((borderWidths.last as? NSNumber)?.doubleValue ?? 0)
        bubble.backgroundColor = backgroundColors.last ?? backgroundColor
        shadow.position = bubble.position
        shadow.bounds = bubble.bounds
        shadow.shadowPath = shadowPaths.last.map { $0 as! CGPath }
        shadow.shadowOpacity = (shadowOpacities.last as? NSNumber)?.floatValue ?? 0
        controlLayer.position = (controlPositions.last as? NSValue)?.pointValue ?? .zero
        controlLayer.bounds = (controlBounds.last as? NSValue)?.rectValue ?? .zero
        controlLayer.opacity = (controlOpacities.last as? NSNumber)?.floatValue ?? 0
        if let contentLayer = contentLayer {
            contentLayer.position = (contentPositions.last as? NSValue)?.pointValue ?? .zero
            contentLayer.transform = (contentTransforms.last as? NSValue)?.caTransform3DValue ?? CATransform3DIdentity
            contentLayer.opacity = (contentOpacities.last as? NSNumber)?.floatValue ?? 1
        }
        CATransaction.commit()

        let completion = self.completion
        let move = ModalMorphTransition.keyframe("position", positions, keyTimes, play)
        move.delegate = CALayerAnimationDelegate(completion: { [weak self] _ in
            if let self = self {
                guard self.generation == generation else {
                    return
                }
                if self.autoFinishOnComplete {
                    self.finish()
                }
            }
            completion()
        })
        bubble.add(move, forKey: "modalMorph.position")
        bubble.add(ModalMorphTransition.keyframe("bounds", bounds, keyTimes, play), forKey: "modalMorph.bounds")
        if perCorner {
            maskLayer.add(ModalMorphTransition.keyframe("path", maskPaths, keyTimes, play), forKey: "modalMorph.maskPath")
            maskLayer.add(ModalMorphTransition.keyframe("bounds", bounds, keyTimes, play), forKey: "modalMorph.bounds")
        } else {
            bubble.add(ModalMorphTransition.keyframe("cornerRadius", radii, keyTimes, play), forKey: "modalMorph.cornerRadius")
        }
        bubble.add(ModalMorphTransition.keyframe("borderWidth", borderWidths, keyTimes, play), forKey: "modalMorph.borderWidth")
        if !backgroundColors.isEmpty {
            bubble.add(ModalMorphTransition.keyframe("backgroundColor", backgroundColors, keyTimes, play), forKey: "modalMorph.backgroundColor")
        }
        shadow.add(ModalMorphTransition.keyframe("position", positions, keyTimes, play), forKey: "modalMorph.position")
        shadow.add(ModalMorphTransition.keyframe("bounds", bounds, keyTimes, play), forKey: "modalMorph.bounds")
        shadow.add(ModalMorphTransition.keyframe("shadowPath", shadowPaths, keyTimes, play), forKey: "modalMorph.shadowPath")
        shadow.add(ModalMorphTransition.keyframe("shadowOpacity", shadowOpacities, keyTimes, play), forKey: "modalMorph.shadowOpacity")
        if hasControl {
            controlLayer.add(ModalMorphTransition.keyframe("position", controlPositions, keyTimes, play), forKey: "modalMorph.position")
            controlLayer.add(ModalMorphTransition.keyframe("bounds", controlBounds, keyTimes, play), forKey: "modalMorph.bounds")
            controlLayer.add(ModalMorphTransition.keyframe("opacity", controlOpacities, keyTimes, play), forKey: "modalMorph.opacity")
        }
        if let contentLayer = contentLayer {
            contentLayer.add(ModalMorphTransition.keyframe("position", contentPositions, keyTimes, play), forKey: "modalMorph.position")
            contentLayer.add(ModalMorphTransition.keyframe("transform", contentTransforms, keyTimes, play), forKey: "modalMorph.transform")
            contentLayer.add(ModalMorphTransition.keyframe("opacity", contentOpacities, keyTimes, play), forKey: "modalMorph.opacity")
        }
        self.segmentBeginTime = CACurrentMediaTime()
    }

    private var extraView: NSView?
    private var liveContent: NSView?
    private var restoreLiveContent: ((NSView) -> Void)?
    private var liveContentSuperview: NSView?
    private var liveContentFrame: NSRect = .zero
    private var liveContentAutoresizing: NSView.AutoresizingMask = []

    static func displayedBounds(_ view: NSView) -> NSRect {
        let bounds = view.bounds
        guard let layer = view.layer else {
            return bounds
        }
        let transform = (layer.presentation() ?? layer).transform
        guard CATransform3DIsAffine(transform) else {
            return bounds
        }
        let affine = CATransform3DGetAffineTransform(transform)
        let center = NSMakePoint(layer.bounds.width * (0.5 - layer.anchorPoint.x), layer.bounds.height * (0.5 - layer.anchorPoint.y))
        let displayedCenter = center.applying(affine)
        guard abs(affine.b) < 0.001, abs(affine.c) < 0.001, affine.a > 0, affine.d > 0, abs(displayedCenter.x - center.x) < 1, abs(displayedCenter.y - center.y) < 1 else {
            return bounds
        }
        return bounds.insetBy(dx: bounds.width * (1 - affine.a) / 2, dy: bounds.height * (1 - affine.d) / 2)
    }

    public static func controlImage(_ view: NSView) -> CGImage? {
        guard let window = view.window, view.bounds.width >= 1, view.bounds.height >= 1 else {
            return nil
        }
        if view.subviews.isEmpty, let contents = view.layer?.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            return (contents as! CGImage)
        }
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return nil
        }
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let create = unsafeBitCast(symbol, to: Fn.self)
        let ns = window.convertToScreen(view.convert(displayedBounds(view), to: nil))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? ns.maxY
        let cg = CGRect(x: ns.minX, y: primaryHeight - ns.maxY, width: ns.width, height: ns.height)
        guard let image = create(cg, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue(), image.width > 0 else {
            return nil
        }
        return image
    }

    // Snapshot a sub-rect of a view's on-screen region (rect in the view's own coordinates), for
    // morphing out of a tapped text link whose rect is a slice of the enclosing TextView.
    public static func controlImage(_ view: NSView, rect: NSRect) -> CGImage? {
        guard let window = view.window, rect.width >= 1, rect.height >= 1 else {
            return nil
        }
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return nil
        }
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        let create = unsafeBitCast(symbol, to: Fn.self)
        let ns = window.convertToScreen(view.convert(rect, to: nil))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? ns.maxY
        let cg = CGRect(x: ns.minX, y: primaryHeight - ns.maxY, width: ns.width, height: ns.height)
        guard let image = create(cg, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue(), image.width > 0 else {
            return nil
        }
        return image
    }

    // An upright bitmap of a view's layer tree, captured off-screen (no window flush, no flash).
    // cacheDisplay forces a synchronous draw of the subtree — essential for a modal captured the
    // instant it is built, before the window's first display cycle has populated its backing store.
    // If cacheDisplay comes back blank (some pure layer-content views), fall back to render(in:).
    public static func snapshotImage(_ view: NSView) -> CGImage? {
        guard view.bounds.width >= 1, view.bounds.height >= 1 else {
            return nil
        }
        view.layoutSubtreeIfNeeded()
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let image = rep.cgImage, !isMostlyBlank(image) {
                return image
            }
        }
        return renderToImage(view)
    }

    private static func renderToImage(_ view: NSView) -> CGImage? {
        guard let layer = view.layer else {
            return nil
        }
        let scale = view.window?.backingScaleFactor ?? 2
        let width = Int((view.bounds.width * scale).rounded())
        let height = Int((view.bounds.height * scale).rounded())
        guard width > 0, height > 0, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        forceLayerDisplay(view)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    private static func forceLayerDisplay(_ view: NSView) {
        view.layer?.setNeedsDisplay()
        view.layer?.displayIfNeeded()
        for subview in view.subviews {
            forceLayerDisplay(subview)
        }
    }

    private static func isMostlyBlank(_ image: CGImage) -> Bool {
        let side = 8
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else {
            return false
        }
        let ptr = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var maxAlpha: UInt8 = 0
        for pixel in 0 ..< (side * side) {
            maxAlpha = max(maxAlpha, ptr[pixel * 4 + 3])
        }
        return maxAlpha < 8
    }

    // A rounded-rect path with an independent radius per corner, laid out like GeneralRowContainerView's own
    // mask (anti-clockwise from mid-left) so a list row's partial rounding morphs without a corner snap.
    private static func cornerPath(_ rect: CGRect, bottomLeft: CGFloat, bottomRight: CGFloat, topRight: CGFloat, topLeft: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let minx = rect.minX, midx = rect.midX, maxx = rect.maxX
        let miny = rect.minY, midy = rect.midY, maxy = rect.maxY
        path.move(to: CGPoint(x: minx, y: midy))
        path.addArc(tangent1End: CGPoint(x: minx, y: miny), tangent2End: CGPoint(x: midx, y: miny), radius: bottomLeft)
        path.addArc(tangent1End: CGPoint(x: maxx, y: miny), tangent2End: CGPoint(x: maxx, y: midy), radius: bottomRight)
        path.addArc(tangent1End: CGPoint(x: maxx, y: maxy), tangent2End: CGPoint(x: midx, y: maxy), radius: topRight)
        path.addArc(tangent1End: CGPoint(x: minx, y: maxy), tangent2End: CGPoint(x: minx, y: midy), radius: topLeft)
        path.closeSubpath()
        return path
    }

    private static func keyframe(_ keyPath: String, _ values: [Any], _ keyTimes: [NSNumber], _ duration: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.calculationMode = .linear
        // Hold the final value instead of reverting to the layer's model (which a layer-backed
        // NSView re-syncs to its frame — the modal rect — flickering the full modal for a frame
        // before finish() removes the view). finish() tears the views down while this still holds.
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        return animation
    }

    private func finish() {
        guard !self.finished else {
            return
        }
        self.finished = true
        if self.opening {
            self.realView?.isHidden = false
        }
        if let content = self.liveContent {
            content.layer?.removeAnimation(forKey: "modalMorph.position")
            content.layer?.removeAnimation(forKey: "modalMorph.transform")
            content.layer?.removeAnimation(forKey: "modalMorph.opacity")
            content.layer?.transform = CATransform3DIdentity
            content.layer?.opacity = 1
            content.autoresizingMask = self.liveContentAutoresizing
            content.frame = self.liveContentFrame
            if let restore = self.restoreLiveContent {
                restore(content)
            } else {
                self.liveContentSuperview?.addSubview(content)
            }
            self.liveContent = nil
            self.restoreLiveContent = nil
            self.liveContentSuperview = nil
        }
        if self.opening {
            self.bubbleView.removeFromSuperview()
            self.extraView?.removeFromSuperview()
            self.extraView = nil
        }
    }

    // Close hand-off: the bubble has settled on the control; the caller has revealed the LIVE control
    // underneath. Fade the bubble (control snapshot) out over it instead of swapping instantly — a Lottie
    // or other animating control needs a frame to render, and a sub-pixel content mismatch crossfades
    // smoothly rather than snapping. Then tear everything down.
    public func fadeOutAndFinish(duration: Double, completion: @escaping () -> Void) {
        guard !self.finished, let layer = self.bubbleView.layer else {
            finish()
            completion()
            return
        }
        layer.opacity = 0
        layer.animateAlpha(from: 1, to: 0, duration: duration, removeOnCompletion: false)
        if let shadow = self.extraView?.layer {
            shadow.opacity = 0
            shadow.animateAlpha(from: 1, to: 0, duration: duration, removeOnCompletion: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.finish()
            completion()
        }
    }

    public func cancel() {
        self.bubbleView.layer?.removeAnimation(forKey: "modalMorph.position")
        self.finish()
    }
}
