import AppKit
import QuartzCore

public enum LiquidGlassLensAnimation {
    case immediate
    case animated(duration: TimeInterval, timingFunction: CAMediaTimingFunctionName)
    case spring(duration: TimeInterval)

    var duration: TimeInterval {
        switch self {
        case .immediate:
            return 0
        case let .animated(duration, _), let .spring(duration):
            return max(0, duration)
        }
    }

    func update(_ layer: CALayer, key: String, value: Any) {
        if let current = layer.value(forKeyPath: key) as? NSObject, let next = value as? NSObject, current.isEqual(next) {
            if case .immediate = self {
                layer.removeAnimation(forKey: key)
            }
            return
        }
        let existing = layer.animation(forKey: key) as? CABasicAnimation
        let previous = existing.map { layer.presentation()?.value(forKeyPath: key) ?? $0.fromValue } ?? layer.value(forKeyPath: key)
        layer.setValue(value, forKeyPath: key)
        layer.removeAnimation(forKey: key)
        guard duration > 0, let previous else {
            return
        }
        let animation: CABasicAnimation
        switch self {
        case .immediate:
            return
        case let .animated(duration, timingFunction):
            animation = CABasicAnimation(keyPath: key)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: timingFunction)
        case let .spring(duration):
            let spring = CASpringAnimation(keyPath: key)
            spring.mass = 3
            spring.stiffness = 1000
            spring.damping = 500
            spring.duration = 0.5
            spring.speed = Float(0.5 / duration)
            spring.timingFunction = CAMediaTimingFunction(name: .linear)
            animation = spring
        }
        animation.fromValue = previous
        animation.toValue = value
        layer.add(animation, forKey: key)
    }

    func frame(_ layer: CALayer, _ frame: CGRect, boundsOrigin: CGPoint = .zero) {
        update(layer, key: "position", value: NSValue(point: frame.origin))
        update(layer, key: "bounds", value: NSValue(rect: CGRect(origin: boundsOrigin, size: frame.size)))
    }
}
