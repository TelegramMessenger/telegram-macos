import AppKit
import QuartzCore

public struct LiquidGlassLensContentSource {
    public let view: NSView
    public let lensedTintColor: NSColor?
    public let unlensedTintColor: NSColor?
    public let lensedScale: CGFloat

    public init(view: NSView, lensedTintColor: NSColor? = nil, unlensedTintColor: NSColor? = nil, lensedScale: CGFloat = 1) {
        self.view = view
        self.lensedTintColor = lensedTintColor
        self.unlensedTintColor = unlensedTintColor
        self.lensedScale = lensedScale.isFinite ? max(0, lensedScale) : 1
    }
}

struct LensContentSource {
    let layer: CALayer
    let frame: CGRect
    let bounds: CGRect
    let magnificationCenter: CGPoint
    let lensedTintColor: NSColor?
    let unlensedTintColor: NSColor?
    let lensedScale: CGFloat
}
