import Cocoa
import TGUIKit

protocol ChatLayerHostedVisibility: AnyObject {
    var visibilityView: NSView? { get set }
    func hostDidMoveToWindow()
}

final class ChatLayerRowView: ChatLayerSceneView {
    private(set) var forwardHeader: ChatLayerTextNode?
    private(set) var senderName: ChatLayerTextNode?
    private var senderBindingVersion: UInt64 = 0
    private(set) var forwardName: ChatLayerTextNode?
    private var forwardBindingVersion: UInt64 = 0
    private(set) var statusNode: ChatLayerButtonNode?
    weak var layerHitBackground: NSView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (statusNode?.layer as? ChatLayerHostedVisibility)?.hostDidMoveToWindow()
    }

    func updateStatus(_ layer: (SimpleLayer & ChatLayerHostedVisibility)?, origin: NSPoint, animated: Bool, action: @escaping () -> Void) {
        guard let layer else {
            guard let previous = statusNode else { return }
            restoreStatus(previous)
            previous.resetInteraction()
            statusNode = nil
            do { try root.setChildren(root.children.filter { $0 !== previous }) }
            catch { assertionFailure("Invalid status tree") }
            if animated {
                root.layer.addSublayer(previous.layer)
                let layer = previous.layer
                layer.animateAlpha(from: CGFloat(layer.opacity), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak self, weak layer] _ in
                    layer?.removeFromSuperlayer()
                    self?.releaseEmptyLayerContent()
                })
            } else {
                releaseEmptyLayerContent()
            }
            return
        }
        if let statusNode, statusNode.layer === layer {
            statusNode.action = action
        } else {
            if let previous = statusNode {
                restoreStatus(previous)
                previous.resetInteraction()
                statusNode = nil
                do { try root.setChildren(root.children.filter { $0 !== previous }) }
                catch { assertionFailure("Invalid status tree") }
            }
            let node = ChatLayerButtonNode(id: "status", label: "", layer: layer, action: action)
            node.cursor = nil
            node.acceptsKeyboardFocus = false
            node.accessibilityRole = .button
            node.accessibilityLabel = nil
            node.frame = NSRect(origin: origin, size: layer.bounds.size)
            statusNode = node
            root.layer.zPosition = 1
            do { try root.setChildren(root.children + [node]) }
            catch { assertionFailure("Invalid status tree") }
        }
        layer.visibilityView = self
    }

    private(set) var adminBadgeNode: ChatLayerControlNode?
    private var adminBadgeText: ChatLayerTextNode?
    private var adminBadgeBackground: ChatLayerNode?

    var hasAdminBadgeNode: Bool { adminBadgeNode != nil }

    #if DEBUG
    var debugAdminBadgeHit: Bool? {
        guard let node = adminBadgeNode, node.userInteractionEnabled, let window else { return nil }
        let center = NSPoint(x: node.frame.midX, y: node.frame.midY)
        guard window.contentView?.hitTest(convert(center, to: nil)) === self else { return false }
        var current = hitNode(at: center)
        while let candidate = current {
            if candidate === node { return true }
            current = candidate.parent
        }
        return false
    }
    #endif

    func updateAdminBadge(_ layout: TextViewLayout?, origin: NSPoint, background: NSColor?, backgroundFrame: NSRect, interactive: Bool, animated: Bool, action: @escaping () -> Void) {
        guard let layout else {
            removeAdminBadgeBackground(animated: animated)
            if let node = adminBadgeNode {
                adminBadgeNode = nil
                adminBadgeText = nil
                removeAdminBadgeNode(node, animated: animated)
            }
            return
        }
        let size = layout.layoutSize
        let node: ChatLayerControlNode
        let text: ChatLayerTextNode
        if let current = adminBadgeNode, let currentText = adminBadgeText {
            node = current
            text = currentText
        } else {
            node = ChatLayerControlNode(id: "admin-badge")
            node.frame = NSRect(origin: origin, size: size)
            text = ChatLayerTextNode(id: "admin-badge-text", selectable: false)
            text.frame = NSRect(origin: .zero, size: size)
            do { try node.setChildren([text]) }
            catch { assertionFailure("Invalid admin badge tree") }
            adminBadgeNode = node
            adminBadgeText = text
            root.layer.zPosition = 1
            do { try root.setChildren(root.children + [node]) }
            catch { assertionFailure("Invalid admin badge tree") }
        }
        text.update(layout, knownHasFormattedDates: false)
        if text.frame.size != size {
            text.frame = NSRect(origin: .zero, size: size)
        }
        if node.frame.size != size {
            node.frame = NSRect(origin: node.frame.origin, size: size)
        }
        node.removeAllHandlers()
        node.cursor = nil
        node.scaleOnClick = interactive
        node.userInteractionEnabled = interactive
        node.accessibilityRole = interactive ? .button : nil
        node.accessibilityLabel = interactive ? layout.attributedString.string : nil
        if interactive {
            node.set(handler: { _ in action() }, for: .Click)
        }
        if let background {
            let current: ChatLayerNode
            if let existing = adminBadgeBackground {
                current = existing
            } else {
                current = ChatLayerNode(id: "admin-badge-background")
                current.layer.masksToBounds = true
                current.layer.isOpaque = true
                if #available(macOS 10.15, *) { current.layer.cornerCurve = .continuous }
                adminBadgeBackground = current
                var children = root.children
                let index = children.firstIndex(where: { $0 === node }) ?? children.count
                children.insert(current, at: index)
                do { try root.setChildren(children) }
                catch { assertionFailure("Invalid admin badge tree") }
            }
            current.layer.backgroundColor = background.withAlphaComponent(0.2).cgColor
            current.frame = backgroundFrame
            current.layer.cornerRadius = backgroundFrame.height / 2
        } else {
            removeAdminBadgeBackground(animated: animated)
        }
    }

    func layoutAdminBadge(origin: NSPoint, backgroundFrame: NSRect, transition: ContainedViewLayoutTransition) {
        if let node = adminBadgeNode {
            var frame = NSRect(origin: origin, size: node.frame.size)
            if let background = layerHitBackground, node.layer.superlayer === background.layer {
                frame = background.convert(frame, from: self)
            }
            node.updateFrame(frame, transition: transition)
        }
        if let current = adminBadgeBackground {
            var frame = backgroundFrame
            if let background = layerHitBackground, current.layer.superlayer === background.layer {
                frame = background.convert(frame, from: self)
            }
            current.updateFrame(frame, transition: transition)
            current.layer.cornerRadius = backgroundFrame.height / 2
        }
    }

    func moveAdminBadgeForShake(into background: NSView) -> (() -> Void)? {
        guard let layer = background.layer else { return nil }
        let nodes: [ChatLayerNode] = [adminBadgeBackground, adminBadgeNode].compactMap { $0 }
        guard !nodes.isEmpty else { return nil }
        for node in nodes {
            let frame = background.convert(node.frame, from: self)
            layer.addSublayer(node.layer)
            node.frame = frame
        }
        return { [weak self] in
            guard let self else { return }
            for node in nodes where node === self.adminBadgeNode || node === self.adminBadgeBackground {
                self.restoreStatus(node)
            }
        }
    }

    private func removeAdminBadgeBackground(animated: Bool) {
        guard let node = adminBadgeBackground else { return }
        adminBadgeBackground = nil
        removeAdminBadgeNode(node, animated: animated)
    }

    private func removeAdminBadgeNode(_ node: ChatLayerNode, animated: Bool) {
        restoreStatus(node)
        (node as? ChatLayerControlNode)?.removeAllHandlers()
        do { try root.setChildren(root.children.filter { $0 !== node }) }
        catch { assertionFailure("Invalid admin badge tree") }
        if animated {
            root.layer.addSublayer(node.layer)
            let layer = node.layer
            let from = layer.presentation()?.opacity ?? layer.opacity
            layer.animateAlpha(from: CGFloat(from), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak self, weak layer] _ in
                layer?.removeFromSuperlayer()
                self?.releaseEmptyLayerContent()
            })
            layer.animateScaleCenter(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false, timingFunction: .easeOut)
        } else {
            releaseEmptyLayerContent()
        }
    }

    func addChromeNode(_ node: ChatLayerNode) {
        root.layer.zPosition = 1
        do { try root.setChildren(root.children + [node]) }
        catch { assertionFailure("Invalid row chrome tree") }
    }

    func removeChromeNode(_ node: ChatLayerNode, animated: Bool) {
        removeAdminBadgeNode(node, animated: animated)
    }

    func layoutChromeNode(_ node: ChatLayerNode, frame: NSRect, transition: ContainedViewLayoutTransition) {
        var frame = frame
        if let background = layerHitBackground, node.layer.superlayer === background.layer {
            frame = background.convert(frame, from: self)
        }
        node.updateFrame(frame, transition: transition)
    }

    func moveChromeNodeForShake(_ node: ChatLayerNode, into background: NSView) -> (() -> Void)? {
        guard let layer = background.layer, node.parent === root else { return nil }
        let frame = background.convert(node.frame, from: self)
        layer.addSublayer(node.layer)
        node.frame = frame
        return { [weak self, weak node] in
            guard let self, let node, node.parent === self.root else { return }
            self.restoreStatus(node)
        }
    }

    func layoutStatus(origin: NSPoint, transition: ContainedViewLayoutTransition) {
        guard let statusNode else { return }
        var frame = NSRect(origin: origin, size: statusNode.layer.bounds.size)
        if let background = layerHitBackground, statusNode.layer.superlayer === background.layer {
            frame = background.convert(frame, from: self)
        }
        statusNode.updateFrame(frame, transition: transition)
    }

    func moveStatusForShake(into background: NSView) -> (() -> Void)? {
        guard let node = statusNode, let layer = background.layer else { return nil }
        let frame = background.convert(node.frame, from: self)
        layer.addSublayer(node.layer)
        node.frame = frame
        return { [weak self, weak node] in
            guard let self, let node, self.statusNode === node else { return }
            self.restoreStatus(node)
        }
    }

    private func restoreStatus(_ node: ChatLayerNode) {
        guard let background = layerHitBackground, node.layer.superlayer === background.layer else { return }
        let frame = convert(node.frame, from: background)
        root.layer.addSublayer(node.layer)
        node.frame = frame
    }

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
        current.update(layout, knownHasLinks: false, knownHasFormattedDates: false)
        current.acceptsPointerEvents = false
        current.acceptsKeyboardFocus = false
    }

    override func layout() {
        if let senderName, senderName.layer.superlayer !== root.layer {
            invalidateHitIndex()
        } else if let forwardName, forwardName.layer.superlayer !== root.layer {
            invalidateHitIndex()
        }
        super.layout()
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
            restoreName(previous)
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
        current.update(layout, knownHasFormattedDates: false)
        guard senderBindingVersion == version else { return }
        current.toolTip = toolTip
    }

    @discardableResult
    func updateForwardName(_ layout: TextViewLayout?, frame: NSRect, animated: Bool) -> Bool {
        forwardBindingVersion &+= 1
        let version = forwardBindingVersion
        guard let layout else {
            guard let previous = forwardName else { return true }
            restoreName(previous)
            previous.resetInteraction()
            guard forwardBindingVersion == version else { return false }
            forwardName = nil
            dismissTooltip(for: self)
            do { try root.setChildren(root.children.filter { $0 !== previous }) }
            catch { assertionFailure("Invalid forwarded name tree") }
            guard forwardBindingVersion == version else { return false }
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
            return true
        }
        let current: ChatLayerTextNode
        if let forwardName {
            current = forwardName
        } else {
            current = ChatLayerTextNode(id: "forward-name", selectable: false)
            current.frame = frame
            forwardName = current
            root.layer.zPosition = 1
            do { try root.setChildren(root.children + [current]) }
            catch { assertionFailure("Invalid forwarded name tree") }
        }
        current.update(layout, knownHasFormattedDates: false)
        return forwardBindingVersion == version
    }

    func layoutSenderName(origin: NSPoint, transition: ContainedViewLayoutTransition) {
        guard let senderName else { return }
        var frame = NSRect(origin: origin, size: senderName.frame.size)
        if let background = layerHitBackground, senderName.layer.superlayer === background.layer {
            frame = background.convert(frame, from: self)
        }
        senderName.updateFrame(frame, transition: transition)
    }

    func layoutForwardName(origin: NSPoint, transition: ContainedViewLayoutTransition) {
        guard let forwardName else { return }
        var frame = NSRect(origin: origin, size: forwardName.frame.size)
        if let background = layerHitBackground, forwardName.layer.superlayer === background.layer {
            frame = background.convert(frame, from: self)
        }
        forwardName.updateFrame(frame, transition: transition)
    }

    func moveSenderNameForShake(into background: NSView) -> (() -> Void)? {
        guard let node = senderName, let layer = background.layer else { return nil }
        let frame = background.convert(node.frame, from: self)
        layer.addSublayer(node.layer)
        node.frame = frame
        return { [weak self, weak node] in
            guard let self, let node, self.senderName === node else { return }
            self.restoreName(node)
        }
    }

    func moveForwardNameForShake(into background: NSView) -> (() -> Void)? {
        guard let node = forwardName, let layer = background.layer else { return nil }
        let frame = background.convert(node.frame, from: self)
        layer.addSublayer(node.layer)
        node.frame = frame
        return { [weak self, weak node] in
            guard let self, let node, self.forwardName === node else { return }
            self.restoreName(node)
        }
    }

    var forwardNameFrame: NSRect? {
        guard let node = forwardName else { return nil }
        if let background = layerHitBackground, node.layer.superlayer === background.layer {
            return convert(node.frame, from: background)
        }
        return node.frame
    }

    private func restoreName(_ node: ChatLayerTextNode) {
        guard let background = layerHitBackground, node.layer.superlayer === background.layer else { return }
        let frame = convert(node.frame, from: background)
        root.layer.addSublayer(node.layer)
        node.frame = frame
    }
}
