import AppKit
import TGUIKit

final class ChatLayerTextNode: ChatLayerNode {
    let drawingLayer = TextViewLayer()
    init(id: AnyHashable, layout: TextViewLayout) {
        super.init(id: id)
        acceptsPointerEvents = true
        acceptsKeyboardFocus = true
        drawingLayer.isTextSelectable = true
        drawingLayer.isKeyWindow = true
        drawingLayer.frame = NSRect(origin: .zero, size: layout.layoutSize)
        drawingLayer.update(layout)
        layer.addSublayer(drawingLayer)
    }
    func refreshLinkHover(at point: NSPoint) {}
    func synchronizeLinkToolTips(force: Bool) {}
    func didRemoveLinkToolTips() {}
    override func updateOwnScale(_ scale: CGFloat) {
        super.updateOwnScale(scale)
        drawingLayer.contentsScale = scale
    }
}

extension ChatLayerSceneView {
    func clearBubbleSelection() {
        for node in root.children.compactMap({ $0 as? ChatLayerTextNode }) {
            node.drawingLayer.textLayout?.clearSelect()
            node.drawingLayer.setNeedsDisplay()
        }
    }
}

final class SelectionFixture: NSResponder {
    let node: ChatLayerTextNode
    var clears = 0
    init(_ node: ChatLayerTextNode) { self.node = node; super.init() }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    __RESIGN__
    func removeAll() {
        clears += 1
        node.drawingLayer.textLayout?.clearSelect()
        node.drawingLayer.setNeedsDisplay()
    }
}
