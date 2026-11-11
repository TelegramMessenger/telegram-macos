import Cocoa
import TGUIKit
import TwidgetRenderer

enum HTMLBubbleMenus {
    static let installed: Void = {
        WidgetRendererEnvironment.presentMenu = { items, anchor, view, event, completion in
            present(items, anchor: anchor, view: view, event: event, completion: completion)
        }
    }()

    private static func present(_ items: [WidgetMenuItem], anchor: CGRect, view: NSView, event: NSEvent?, completion: @escaping (Int?) -> Void) {
        guard let window = view.window else {
            completion(nil)
            return
        }
        var finished = false
        let finish: (Int?) -> Void = { choice in
            if !finished {
                finished = true
                completion(choice)
            }
        }
        let menu = ContextMenu(betterInside: true)
        for (index, item) in items.enumerated() {
            switch item.kind {
            case .separator:
                menu.addItem(ContextSeparatorItem())
            case .header:
                let header = ContextMenuItem(item.title)
                header.isEnabled = false
                menu.addItem(header)
            case .option:
                let entry = ContextMenuItem(item.title, handler: {
                    finish(index)
                }, state: item.selected ? .on : nil)
                entry.isEnabled = item.enabled
                menu.addItem(entry)
            }
        }
        menu.onClose = {
            DispatchQueue.main.async {
                finish(nil)
            }
        }
        let point = view.convert(CGPoint(x: anchor.minX, y: view.isFlipped ? anchor.maxY : anchor.minY), to: nil)
        guard let anchored = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: event?.timestamp ?? ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
            finish(nil)
            return
        }
        AppMenu.show(menu: menu, event: anchored, for: view)
    }
}
