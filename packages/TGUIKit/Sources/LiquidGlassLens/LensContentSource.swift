import AppKit
import QuartzCore

public struct LiquidGlassLensContentSource {
    public let view: NSView
    public let lensedTintColor: NSColor?
    public let unlensedTintColor: NSColor?
    public let lensedScale: CGFloat
    public let magnificationCenter: CGPoint?
    public let magnifies: Bool

    public init(view: NSView, lensedTintColor: NSColor? = nil, unlensedTintColor: NSColor? = nil, lensedScale: CGFloat = 1, magnificationCenter: CGPoint? = nil, magnifies: Bool = true) {
        self.view = view
        self.lensedTintColor = lensedTintColor
        self.unlensedTintColor = unlensedTintColor
        self.lensedScale = lensedScale.isFinite ? max(0, lensedScale) : 1
        self.magnificationCenter = magnificationCenter.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        self.magnifies = magnifies
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
    let magnifies: Bool
}
