import Cocoa
import TGUIKit

protocol ChatTextSelectionProvider {
    var textSelectionSources: ChatTextSelectionSources { get }
}

enum ChatTextSelectionSources {
    case views([TextView])
    case mixed([ChatTextSelectionSource])

    var count: Int {
        switch self {
        case let .views(views): return views.count
        case let .mixed(sources): return sources.count
        }
    }

    subscript(index: Int) -> ChatTextSelectionSource {
        switch self {
        case let .views(views): return .view(views[index])
        case let .mixed(sources): return sources[index]
        }
    }

    func restoreFocus(in window: Window) {
        for index in 0..<count where self[index].isFirstResponder(in: window) {
            self[index].focus(in: window)
            return
        }
        if count > 0 {
            self[0].focus(in: window)
        } else {
            _ = window.makeFirstResponder(nil)
        }
    }
}

enum ChatTextSelectionSource {
    case view(TextView)
    case layer(ChatLayerTextNode, ChatLayerSceneView)

    var textLayout: TextViewLayout? {
        switch self {
        case let .view(view): return view.textLayout
        case let .layer(node, scene):
            guard node.scene === scene, node.isSelectable, node.isVisible, node.isEffectivelyEnabled,
                  !scene.isHiddenOrHasHiddenAncestor, node.textLayout?.mayItems == true else { return nil }
            return node.textLayout
        }
    }

    func selectionFrame(in document: NSView?) -> NSRect {
        switch self {
        case let .view(view):
            if let parent = view.superview, parent.frame.height < view.frame.height {
                return parent.convert(NSRect(origin: .zero, size: parent.frame.size), to: document)
            }
            return view.convert(NSRect(origin: .zero, size: view.frame.size), to: document)
        case let .layer(node, scene):
            return scene.convert(node.layer.convert(node.layer.bounds, to: scene.root.layer), to: document)
        }
    }

    func convert(_ point: NSPoint, from document: NSView?) -> NSPoint {
        switch self {
        case let .view(view): return view.convert(point, from: document)
        case let .layer(node, scene):
            return node.layer.convert(scene.convert(point, from: document), from: scene.root.layer)
        }
    }

    func select(layout: TextViewLayout, start: NSPoint, end: NSPoint, manager: SelectManager, header: String?, stableId: AnyHashable, index: Int) {
        let range = layout.selectedRange(startPoint: start, currentPoint: end)
        switch self {
        case let .view(view):
            view.canBeResponder = false
            layout.selectedRange.range = range
            layout.selectedRange.cursorAlignment = start.x > end.x ? .min(range.max) : .max(range.min)
            manager.add(range: range, textView: view, layout: layout, text: layout.attributedString, header: header, stableId: stableId, index: index)
            view.setNeedsDisplayLayer()
        case let .layer(node, scene):
            guard textLayout === layout else { return }
            node.setExternalSelection(range)
            guard textLayout === layout, layout.selectedRange.range == range else { return }
            layout.selectedRange.cursorAlignment = start.x > end.x ? .min(range.max) : .max(range.min)
            manager.addBubble(fragment: ChatBubbleSelectionFragment(attributedString: layout.attributedString, range: range, index: index), source: scene, header: header, stableId: stableId)
        }
    }

    func isFirstResponder(in window: Window) -> Bool {
        switch self {
        case let .view(view): return window.firstResponder === view
        case let .layer(node, scene): return window.firstResponder === scene && scene.focusedNode === node
        }
    }

    func focus(in window: Window) {
        switch self {
        case let .view(view): _ = window.makeFirstResponder(view)
        case let .layer(node, scene):
            guard textLayout != nil, scene.window === window else { return }
            scene.focus(node)
            if scene.focusedNode === node { _ = window.makeFirstResponder(scene) }
        }
    }
}
