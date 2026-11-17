import Cocoa
import TGUIKit
import TelegramTheme

final class InstantPageFindScrollView: ScrollView {
    var pageFindBar: PageFindBarView? {
        didSet {
            if oldValue !== pageFindBar {
                oldValue?.removeFromSuperview()
            }
            if let pageFindBar {
                addSubview(pageFindBar)
            }
            tile()
        }
    }

    override func tile() {
        super.tile()
        guard let pageFindBar else { return }
        let height = min(46, bounds.height)
        var frame = contentView.frame
        frame.size.height = max(0, frame.height - height)
        if isFlipped {
            frame.origin.y += height
        }
        contentView.frame = frame
        if let scroller = verticalScroller {
            var frame = scroller.frame
            frame.size.height = max(0, frame.height - height)
            if isFlipped {
                frame.origin.y += height
            }
            scroller.frame = frame
        }
        pageFindBar.frame = NSRect(x: bounds.minX, y: isFlipped ? bounds.minY : bounds.maxY - height, width: bounds.width, height: height)
    }
}

private final class InstantPageFindHighlightView: View {
    var rects: [CGRect] = []
    var selected: [CGRect] = []

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? { [] }

    override func draw(_ layer: CALayer, in context: CGContext) {
        context.setFillColor(theme.colors.accent.withAlphaComponent(0.18).cgColor)
        context.fill(rects)
        context.setFillColor(theme.colors.accent.withAlphaComponent(0.4).cgColor)
        context.fill(selected)
    }
}

final class InstantPageFindHighlights {
    private var overlays: [ObjectIdentifier: InstantPageFindHighlightView] = [:]

    func update(_ highlights: [(view: NSView, rects: [CGRect], selected: [CGRect])]) {
        var retained = Set<ObjectIdentifier>()
        for highlight in highlights {
            let key = ObjectIdentifier(highlight.view)
            retained.insert(key)
            let overlay: InstantPageFindHighlightView
            if let current = overlays[key] {
                overlay = current
            } else {
                overlay = InstantPageFindHighlightView(frame: highlight.view.bounds)
                overlay.isEventLess = true
                overlay.userInteractionEnabled = false
                overlay.layer?.isOpaque = false
                overlays[key] = overlay
            }
            if highlight.view.subviews.last !== overlay {
                highlight.view.addSubview(overlay, positioned: .above, relativeTo: nil)
            }
            overlay.frame = highlight.view.visibleRect
            overlay.bounds = highlight.view.visibleRect
            overlay.rects = highlight.rects
            overlay.selected = highlight.selected
            overlay.needsDisplay = true
        }
        for key in Array(overlays.keys) where !retained.contains(key) {
            overlays.removeValue(forKey: key)?.removeFromSuperview()
        }
    }

    deinit {
        for overlay in overlays.values { overlay.removeFromSuperview() }
    }
}
