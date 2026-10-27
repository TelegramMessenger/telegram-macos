import AppKit
import QuartzCore

final class LensPortal {
    let layer: CALayer
    private let runtime: LensRuntime
    private var tintColor: NSColor?

    init(source: CALayer, runtime: LensRuntime) {
        self.runtime = runtime
        layer = runtime.layer("CAPortalLayer")
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.setValue(source, forKey: "sourceLayer")
        layer.setValue(true, forKey: "hidesSourceLayer")
        layer.setValue(false, forKey: "matchesPosition")
        layer.setValue(false, forKey: "matchesTransform")
    }

    func updateTint(_ color: NSColor?) {
        guard tintColor != color else {
            return
        }
        tintColor = color
        guard let color = color?.usingColorSpace(.sRGB),
              let filter = runtime.makeFilter("colorMatrix", inputs: ["inputColorMatrix", "inputPremultipliedValues"]) else {
            layer.filters = nil
            return
        }
        let alpha = Float(color.alphaComponent)
        let matrix: [Float] = [
            0, 0, 0, Float(color.redComponent) * alpha, 0,
            0, 0, 0, Float(color.greenComponent) * alpha, 0,
            0, 0, 0, Float(color.blueComponent) * alpha, 0,
            0, 0, 0, alpha, 0,
        ]
        let value = matrix.withUnsafeBufferPointer {
            NSValue(bytes: $0.baseAddress!, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
        }
        filter.setValue(value, forKey: "inputColorMatrix")
        filter.setValue(true, forKey: "inputPremultipliedValues")
        layer.filters = [filter]
    }

    func remove() {
        layer.setValue(nil, forKey: "sourceLayer")
        layer.removeFromSuperlayer()
    }
}
