import Cocoa
import TGUIKit

final class BeforeForwardNameRowView: ChatLayerSceneView {
    private(set) var forwardHeader: ChatLayerTextNode?
    private(set) var senderName: ChatLayerTextNode?
    private var senderBindingVersion: UInt64 = 0
    weak var layerHitBackground: NSView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect, deferred: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateForwardHeader(_ layout: TextViewLayout?, frame: NSRect, animated: Bool) {
        guard let layout else {
            guard let previous = forwardHeader else { return }
            forwardHeader = nil
            do { try root.setChildren(root.children.filter { $0 !== previous }) }
            catch { assertionFailure("Invalid row header tree") }
            if animated && window != nil && !visibleRect.isEmpty {
                let layer = previous.layer
                root.layer.addSublayer(layer)
                layer.animateAlpha(from: CGFloat(layer.presentation()?.opacity ?? layer.opacity), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak self, weak layer] _ in
                    layer?.removeFromSuperlayer()
                    self?.releaseEmptyLayerContent()
                })
            } else {
                releaseEmptyLayerContent()
            }
            return
        }
        let current: ChatLayerTextNode
        if let forwardHeader {
            current = forwardHeader
        } else {
            current = ChatLayerTextNode(id: "forward-header", selectable: false)
            current.frame = frame
            forwardHeader = current
            root.layer.zPosition = 1
            do { try root.setChildren(root.children + [current]) }
            catch { assertionFailure("Invalid row header tree") }
        }
        current.update(layout, knownHasLinks: false)
        current.acceptsPointerEvents = false
        current.acceptsKeyboardFocus = false
    }

    func layoutForwardHeader(frame: NSRect, transition: ContainedViewLayoutTransition) {
        forwardHeader?.updateFrame(frame, transition: transition)
    }

    override func hitNode(at point: NSPoint) -> ChatLayerNode? {
        guard mayHitNode(at: point) else { return nil }
        guard let native = super.hitTest(convert(point, to: superview)) else { return nil }
        guard native === self || native === layerHitBackground else { return nil }
        return super.hitNode(at: point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let native = super.hitTest(point)
        guard let native, hasLayerContent, native === self || native === layerHitBackground,
              super.hitNode(at: convert(point, from: superview)) != nil else { return native }
        return self
    }

    override func updatePointerCursor(_ cursor: NSCursor, at point: NSPoint?) {
        if let point, let native = super.hitTest(convert(point, to: superview)), native !== self, native !== layerHitBackground { return }
        super.updatePointerCursor(cursor, at: point)
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        if let window {
            let local = convert(window.convertPoint(fromScreen: point), from: nil)
            if let native = super.hitTest(convert(local, to: superview)), native !== self, native !== layerHitBackground {
                return native.accessibilityHitTest(point)
            }
        }
        return super.accessibilityHitTest(point)
    }

    func updateSenderName(_ layout: TextViewLayout?, toolTip: String?, frame: NSRect, animated: Bool) {
        senderBindingVersion &+= 1
        let version = senderBindingVersion
        guard let layout else {
            guard let previous = senderName else { return }
            restoreSenderName(previous)
            previous.resetInteraction()
            guard senderBindingVersion == version else { return }
            senderName = nil
            do { try root.setChildren(root.children.filter { $0 !== previous }) }
            catch { assertionFailure("Invalid sender name tree") }
            if animated && window != nil && !visibleRect.isEmpty {
                root.layer.addSublayer(previous.layer)
                let layer = previous.layer
                layer.animateAlpha(from: CGFloat(layer.opacity), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak self, weak layer] _ in
                    layer?.removeFromSuperlayer()
                    self?.releaseEmptyLayerContent()
                })
                layer.animateScaleCenter(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false, timingFunction: .easeOut)
            } else {
                releaseEmptyLayerContent()
            }
            return
        }
        let current: ChatLayerTextNode
        if let senderName {
            current = senderName
        } else {
            current = ChatLayerTextNode(id: "sender-name", selectable: false)
            current.frame = frame
            senderName = current
            root.layer.zPosition = 1
            do { try root.setChildren(root.children + [current]) }
            catch { assertionFailure("Invalid sender name tree") }
        }
        current.update(layout)
        guard senderBindingVersion == version else { return }
        current.toolTip = toolTip
    }

    func layoutSenderName(origin: NSPoint, transition: ContainedViewLayoutTransition) {
        guard let senderName else { return }
        var frame = NSRect(origin: origin, size: senderName.frame.size)
        if let background = layerHitBackground, senderName.layer.superlayer === background.layer {
            frame = background.convert(frame, from: self)
        }
        senderName.updateFrame(frame, transition: transition)
    }

    func moveSenderNameForShake(into background: NSView) -> (() -> Void)? {
        guard let node = senderName, let layer = background.layer else { return nil }
        let frame = background.convert(node.frame, from: self)
        layer.addSublayer(node.layer)
        node.frame = frame
        return { [weak self, weak node] in
            guard let self, let node, self.senderName === node else { return }
            self.restoreSenderName(node)
        }
    }

    private func restoreSenderName(_ node: ChatLayerTextNode) {
        guard let background = layerHitBackground, node.layer.superlayer === background.layer else { return }
        let frame = convert(node.frame, from: background)
        root.layer.addSublayer(node.layer)
        node.frame = frame
    }
}
