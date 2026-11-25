import Cocoa

func performInlineStickerPlayback<Layers: Collection>(_ layers: Layers, window: NSWindow?, isLite: Bool) where Layers.Element: CALayer {
    guard !layers.isEmpty else {
        return
    }
    let canPlay = !isLite && window?.isKeyWindow == true
    var previousSuperview: NSView?
    var visibleRect = NSRect.zero
    for layer in layers {
        guard let layer = layer as? InlineStickerItemLayer else {
            continue
        }
        guard canPlay, let superview = layer.superview else {
            layer.isPlayable = false
            continue
        }
        if previousSuperview !== superview {
            previousSuperview = superview
            visibleRect = superview.visibleRect
        }
        layer.isPlayable = NSIntersectsRect(layer.frame, visibleRect)
    }
}
