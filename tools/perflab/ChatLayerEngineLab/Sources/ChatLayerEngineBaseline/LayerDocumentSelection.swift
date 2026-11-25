import Cocoa
import TGUIKit

final class LayerDocumentSelection: NSResponder {
    private weak var document: NSView?
    private weak var hostWindow: Window?
    private let scenes: [ChatLayerSceneView]
    private var anchor: NSPoint?
    private weak var anchorScene: ChatLayerSceneView?
    private var dragging = false
    private(set) var selectedText = NSAttributedString()
    var onCopy: ((NSAttributedString) -> Void)?

    init(document: NSView, scenes: [ChatLayerSceneView]) {
        self.document = document
        self.scenes = scenes
        super.init()
        nextResponder = document
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { hostWindow?.removeAllHandlers(for: self) }
    override var acceptsFirstResponder: Bool { true }

    func bind(to window: Window?) {
        hostWindow?.removeAllHandlers(for: self)
        hostWindow = window
        clear()
        window?.set(mouseHandler: { [weak self] event in
            guard let self, let document = self.document else { return .invokeNext }
            _ = self.begin(at: document.convert(event.locationInWindow, from: nil))
            return .invokeNext
        }, with: self, for: .leftMouseDown, priority: .medium)
        window?.set(mouseHandler: { [weak self] event in
            guard let self, let document = self.document, self.anchor != nil else { return .invokeNext }
            document.enclosingScrollView?.contentView.autoscroll(with: event)
            return self.extend(to: document.convert(event.locationInWindow, from: nil)) ? .invoked : .invokeNext
        }, with: self, for: .leftMouseDragged, priority: .medium)
        window?.set(mouseHandler: { [weak self] _ in
            return self?.finish() == true ? .invoked : .invokeNext
        }, with: self, for: .leftMouseUp, priority: .medium)
        window?.set(handler: { [weak self] _ in
            guard let self, self.hostWindow?.firstResponder === self, self.selectedText.length > 0 else { return .invokeNext }
            self.copy(nil)
            return .invoked
        }, with: self, for: .C, priority: .medium, modifierFlags: [.command])
    }

    @discardableResult func begin(at point: NSPoint) -> Bool {
        clear()
        guard let document, document.visibleRect.contains(point), let scene = scenes.first(where: { $0.frame.contains(point) }),
              let text = scene.hitNode(at: scene.convert(point, from: document)) as? ChatLayerTextNode,
              text.isSelectable, text.textLayout?.mayItems == true else { return false }
        anchor = point
        anchorScene = scene
        return true
    }

    @discardableResult func extend(to point: NSPoint) -> Bool {
        guard let anchor, let document else { return false }
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        if !dragging {
            guard dx * dx + dy * dy > 16 else { return false }
            anchorScene?.cancelInput(preservingFocus: true)
            dragging = true
        }
        let selected = NSMutableAttributedString()
        for scene in scenes {
            let fragments = scene.applyBubbleSelection(begin: scene.convert(anchor, from: document), end: scene.convert(point, from: document), isStartRow: scene === anchorScene, isEndRow: scene.frame.contains(point), reversed: point.y < anchor.y)
            for fragment in fragments {
                if selected.length > 0 { selected.append(NSAttributedString(string: "\n\n")) }
                selected.append(fragment.attributedString.attributedSubstring(from: fragment.range))
            }
        }
        selectedText = selected
        hostWindow?.makeFirstResponder(self)
        return true
    }

    @discardableResult func finish() -> Bool {
        let consumed = dragging
        anchor = nil
        anchorScene = nil
        dragging = false
        return consumed
    }

    func clear() {
        _ = finish()
        for scene in scenes { scene.clearBubbleSelection() }
        selectedText = NSAttributedString()
    }

    @objc func copy(_ sender: Any?) {
        guard selectedText.length > 0 else { return }
        if let onCopy { onCopy(selectedText) }
        else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText.string, forType: .string)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { clear() }
        else { super.keyDown(with: event) }
    }
}
