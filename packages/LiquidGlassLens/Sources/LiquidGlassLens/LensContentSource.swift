import AppKit
import QuartzCore

public struct LiquidGlassLensContentSource {
    public let view: NSView
    public let lensedTintColor: NSColor?
    public let unlensedTintColor: NSColor?

    public init(view: NSView, lensedTintColor: NSColor? = nil, unlensedTintColor: NSColor? = nil) {
        self.view = view
        self.lensedTintColor = lensedTintColor
        self.unlensedTintColor = unlensedTintColor
    }
}

struct LensContentSource {
    let layer: CALayer
    let frame: CGRect
    let bounds: CGRect
    let magnificationCenter: CGPoint
    let lensedTintColor: NSColor?
    let unlensedTintColor: NSColor?
}
