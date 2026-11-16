import Cocoa
import QuartzCore
import TGUIKit

final class ChatDictationBubble {
    private static let inset: CGFloat = 8
    private static let samples = 40
    private static let settleDuration: CFTimeInterval = 0.24

    private let view: View
    private let shape = CAShapeLayer()
    private let sheen = CALayer()
    private let sheenMask = CAShapeLayer()
    private let gloss = CAGradientLayer()
    private var ticker: ChatDictationRevealTicker?
    private var level: CGFloat = 0
    private var target: CGFloat = 0
    private var energy: CGFloat = 0
    private var lastStep: CFTimeInterval = 0
    private let origin = CACurrentMediaTime()
    private var stopping: CFTimeInterval?
    private var onStopped: (() -> Void)?
    private var keepAlive: ChatDictationBubble?

    init(host: NSView) {
        view = View(frame: host.bounds.insetBy(dx: -Self.inset, dy: -Self.inset))
        view.isEventLess = true
        view.layer?.masksToBounds = false
        host.addSubview(view, positioned: .below, relativeTo: nil)
        shape.frame = view.bounds
        gloss.colors = [NSColor.white.withAlphaComponent(0.24).cgColor, NSColor.white.withAlphaComponent(0.07).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        gloss.locations = [0, 0.38, 0.66]
        gloss.startPoint = CGPoint(x: 0.5, y: 0)
        gloss.endPoint = CGPoint(x: 0.5, y: 1)
        sheen.frame = view.bounds
        sheenMask.frame = view.bounds
        sheen.mask = sheenMask
        sheen.addSublayer(gloss)
        view.layer?.addSublayer(shape)
        view.layer?.addSublayer(sheen)
    }

    deinit {
        ticker?.invalidate()
        view.removeFromSuperview()
    }

    func start(color: NSColor) {
        shape.fillColor = color.cgColor
        stopping = nil
        onStopped = nil
        energy = 1
        lastStep = CACurrentMediaTime()
        if ticker == nil {
            ticker = ChatDictationRevealTicker(view: view, tick: { [weak self] in
                self?.step()
            })
        }
        step()
    }

    func setColor(_ color: NSColor) {
        shape.fillColor = color.cgColor
    }

    func update(level: CGFloat) {
        let clamped = min(1, max(0, level))
        if clamped - target > 0.22 {
            energy = min(1, energy + 0.3 * (clamped - target))
        }
        target = clamped
    }

    func stop(completion: @escaping () -> Void) {
        guard stopping == nil else { return }
        stopping = CACurrentMediaTime()
        onStopped = completion
        keepAlive = self
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDuration + 0.05) { [weak self] in
            self?.step()
        }
    }

    static func offset(at fraction: Double, time: Double, level: CGFloat, energy: CGFloat) -> CGFloat {
        let phi = fraction * 2 * .pi
        let ripple = 0.5 * sin(2 * phi + 2.1 * time) + 0.32 * sin(3 * phi - 2.9 * time + 1.3) + 0.22 * sin(5 * phi + 4.3 * time + 0.7)
        let jelly = cos(2 * phi) * sin(time * 15)
        return (0.45 + 1.7 * level + 1.2 * energy) * CGFloat(ripple) + 2.2 * energy * CGFloat(jelly)
    }

    private func step() {
        let now = CACurrentMediaTime()
        let delta = CGFloat(min(0.05, max(0, now - lastStep)))
        lastStep = now
        let rate: CGFloat = target > level ? 18 : 5
        level += (target - level) * min(1, rate * delta)
        energy *= exp(-delta * 3.2)
        var calm: CGFloat = 1
        if let stopping {
            calm = max(0, 1 - CGFloat((now - stopping) / Self.settleDuration))
            if calm <= 0 {
                finish()
                return
            }
            calm = calm * calm * (3 - 2 * calm)
        }
        let time = now - origin
        let size = NSMakeSize(view.bounds.width - Self.inset * 2, view.bounds.height - Self.inset * 2)
        let swell = 1 + (0.035 * level + 0.03 * energy * CGFloat(sin(time * 15))) * calm
        let points = Self.outline(size: size, swell: swell) { fraction in
            Self.offset(at: fraction, time: time, level: self.level, energy: self.energy) * calm
        }
        let path = Self.smoothPath(points.map { NSMakePoint($0.x + Self.inset, $0.y + Self.inset) })
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = view.bounds
        shape.path = path
        sheen.frame = view.bounds
        sheenMask.frame = view.bounds
        sheenMask.path = path
        gloss.frame = path.boundingBoxOfPath
        CATransaction.commit()
    }

    private func finish() {
        ticker?.invalidate()
        ticker = nil
        let completion = onStopped
        onStopped = nil
        view.removeFromSuperview()
        completion?()
        keepAlive = nil
    }

    static func outline(size: NSSize, swell: CGFloat, offset: (Double) -> CGFloat) -> [NSPoint] {
        let radius = min(size.width, size.height) / 2
        let straight = max(0, size.width - radius * 2)
        let perimeter = straight * 2 + 2 * .pi * radius
        let center = NSMakePoint(size.width / 2, size.height / 2)
        return (0 ..< samples).map { index in
            let fraction = Double(index) / Double(samples)
            let distance = CGFloat(fraction) * perimeter
            let point: NSPoint
            let normal: NSPoint
            if distance < straight {
                point = NSMakePoint(radius + distance, 0)
                normal = NSMakePoint(0, -1)
            } else if distance < straight + .pi * radius {
                let angle = -CGFloat.pi / 2 + (distance - straight) / radius
                normal = NSMakePoint(cos(angle), sin(angle))
                point = NSMakePoint(size.width - radius + radius * normal.x, radius + radius * normal.y)
            } else if distance < straight * 2 + .pi * radius {
                point = NSMakePoint(size.width - radius - (distance - straight - .pi * radius), size.height)
                normal = NSMakePoint(0, 1)
            } else {
                let angle = CGFloat.pi / 2 + (distance - straight * 2 - .pi * radius) / radius
                normal = NSMakePoint(cos(angle), sin(angle))
                point = NSMakePoint(radius + radius * normal.x, radius + radius * normal.y)
            }
            let push = offset(fraction)
            let moved = NSMakePoint(point.x + normal.x * push, point.y + normal.y * push)
            return NSMakePoint(center.x + (moved.x - center.x) * swell, center.y + (moved.y - center.y) * swell)
        }
    }

    static func smoothPath(_ points: [NSPoint]) -> CGPath {
        let path = CGMutablePath()
        let count = points.count
        guard count > 2 else { return path }
        path.move(to: points[0])
        for index in 0 ..< count {
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            let control1 = NSMakePoint(p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6)
            let control2 = NSMakePoint(p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }
}
