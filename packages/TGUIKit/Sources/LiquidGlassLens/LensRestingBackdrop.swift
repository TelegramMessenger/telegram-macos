import AppKit
import QuartzCore

final class LensRestingBackdrop {
    let layer = CALayer()
    private let backdrop: CALayer
    private let tint = CALayer()

    init?(runtime: LensRuntime) {
        guard let blur = runtime.makeFilter("gaussianBlur", inputs: ["inputRadius", "inputNormalizeEdges"]) else {
            return nil
        }
        blur.setValue("lensRestingBlur", forKey: "name")
        blur.setValue(true, forKey: "inputNormalizeEdges")
        backdrop = runtime.layer("CABackdropLayer")
        backdrop.filters = [blur]
        layer.name = "lensRestingBackground"
        layer.anchorPoint = .zero
        layer.masksToBounds = true
        tint.anchorPoint = .zero
        layer.addSublayer(backdrop)
        layer.addSublayer(tint)
    }

    func update(frame: CGRect, progress: CGFloat, blurRadius: CGFloat, tintColor: NSColor?, scale: CGFloat, animation: LiquidGlassLensAnimation) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        animation.frame(layer, frame)
        animation.update(layer, key: "cornerRadius", value: frame.height / 2)
        animation.update(layer, key: "opacity", value: Float(1 - progress))
        for child in [backdrop, tint] {
            animation.frame(child, bounds)
            child.contentsScale = scale
        }
        layer.contentsScale = scale
        backdrop.setValue(scale, forKey: "scale")
        backdrop.setValue(blurRadius, forKeyPath: "filters.lensRestingBlur.inputRadius")
        tint.backgroundColor = tintColor?.cgColor
    }

    func remove() {
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
    }
}
