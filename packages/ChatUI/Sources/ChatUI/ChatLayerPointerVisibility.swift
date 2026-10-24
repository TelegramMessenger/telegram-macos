import Cocoa

func chatLayerPointerIsExposed(_ view: NSView, at point: NSPoint) -> Bool {
    guard !view.isHiddenOrHasHiddenAncestor, let contentView = view.window?.contentView,
          let hit = contentView.hitTest(view.convert(point, to: contentView.superview)) else {
        return false
    }
    return hit === view || hit.isDescendant(of: view)
}
