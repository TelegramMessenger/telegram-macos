import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import AvatarUI
import TelegramUtils

final class ChatFloatingAvatarScene: ChatLayerSceneView {
    private let containerFlipped: Bool
    private var registered: [ObjectIdentifier: ChatFloatingAvatarNode] = [:]
    var recycle: ((ChatFloatingAvatarNode) -> Void)?

    init(frame frameRect: NSRect, flipped: Bool) {
        self.containerFlipped = flipped
        super.init(frame: frameRect, deferred: true)
        tracksPointer = false
    }

    required init(frame frameRect: NSRect) {
        self.containerFlipped = true
        super.init(frame: frameRect, deferred: true)
        tracksPointer = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { containerFlipped }

    var avatars: [ChatFloatingAvatarNode] {
        guard hasLayerContent else { return [] }
        return root.children.compactMap { registered[ObjectIdentifier($0)] }
    }

    func contains(_ node: ChatFloatingAvatarNode) -> Bool {
        return hasLayerContent && node.control.parent === root
    }

    var avatarCount: Int {
        return registered.count
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hasLayerContent, !isHidden, let superview else { return nil }
        return hitNode(at: convert(point, from: superview)) != nil ? self : nil
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let window, let superview, hasLayerContent else { return super.accessibilityHitTest(point) }
        let location = window.convertPoint(fromScreen: point)
        if hitNode(at: convert(location, from: nil)) != nil {
            return super.accessibilityHitTest(point)
        }
        let local = superview.convert(location, from: nil)
        if let index = superview.subviews.firstIndex(where: { $0 === self }) {
            for sibling in superview.subviews[..<index].reversed() where !sibling.isHidden && sibling.frame.contains(local) {
                return sibling.accessibilityHitTest(point)
            }
        }
        return NSAccessibility.unignoredAncestor(of: superview)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for node in avatars {
            node.avatar.updateScale(backingScaleFactor)
            node.avatar.hostDidMoveToWindow()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for node in avatars {
            node.avatar.updateScale(backingScaleFactor)
        }
    }

    func detach(_ node: ChatFloatingAvatarNode) {
        guard contains(node) else { return }
        do { try root.setChildren(root.children.filter { $0 !== node.control }) }
        catch { assertionFailure("Invalid floating avatar tree") }
        registered[ObjectIdentifier(node.control)] = nil
        node.avatar.displayView = nil
    }

    func place(_ nodes: [ChatFloatingAvatarNode]) {
        if hasLayerContent {
            let children = root.children
            if children.count == nodes.count {
                var same = true
                for index in 0 ..< nodes.count where children[index] !== nodes[index].control {
                    same = false
                    break
                }
                if same {
                    return
                }
            }
        } else if nodes.isEmpty {
            return
        }
        let wanted = Set(nodes.map { ObjectIdentifier($0.control) })
        let others = hasLayerContent ? root.children.filter { !wanted.contains(ObjectIdentifier($0)) } : []
        let next: [ChatLayerNode] = others + nodes.map { $0.control as ChatLayerNode }
        guard hasLayerContent || !next.isEmpty else { return }
        if root.children.count == next.count && zip(root.children, next).allSatisfy({ $0 === $1 }) {
            return
        }
        let added = nodes.filter { registered[ObjectIdentifier($0.control)] == nil }
        for node in nodes {
            registered[ObjectIdentifier(node.control)] = node
        }
        do { try root.setChildren(next) }
        catch { assertionFailure("Invalid floating avatar tree") }
        for node in added {
            node.avatar.updateScale(backingScaleFactor)
            node.avatar.displayView = self
        }
    }

    func remove(_ node: ChatFloatingAvatarNode, animated: Bool) {
        guard contains(node) else { return }
        guard animated else {
            detach(node)
            releaseEmptyLayerContent()
            recycle?(node)
            return
        }
        let layer = node.control.layer
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.animateAlpha(from: CGFloat(from), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak self, weak node] finish in
            guard finish, let self, let node, self.contains(node) else { return }
            self.detach(node)
            self.releaseEmptyLayerContent()
            self.recycle?(node)
        })
    }

    #if DEBUG
    func debugAvatarHitChecks() -> (ok: Int, total: Int) {
        var ok = 0, total = 0
        guard let window else { return (0, 0) }
        for node in avatars where node.control.layer.animation(forKey: "opacity") == nil {
            total += 1
            let frame = node.control.frame
            let center = NSPoint(x: frame.midX, y: frame.midY)
            if window.contentView?.hitTest(convert(center, to: nil)) === self, hitNode(at: center) === node.control {
                ok += 1
            }
        }
        return (ok, total)
    }
    #endif
}

final class ChatFloatingAvatarNode {
    static let size = NSMakeSize(36, 36)

    let control: ChatLayerControlNode
    let avatar = AvatarImageLayer(font: .avatar(.title))

    init() {
        let container = SimpleLayer()
        container.anchorPoint = .zero
        control = ChatLayerControlNode(id: AnyHashable(UUID()), layer: container)
        avatar.anchorPoint = .zero
        avatar.updateScale(System.backingScale)
        avatar.frame = ChatFloatingAvatarNode.size.bounds
        container.addSublayer(avatar)
        control.frame = ChatFloatingAvatarNode.size.bounds
        control.scaleOnClick = true
        control.accessibilityRole = .button
    }

    var layer: CALayer { control.layer }
    var frame: NSRect { control.frame }
    var scene: ChatLayerSceneView? { control.scene }

    func setPeer(item: ChatRowItem, peer: Peer, message: Message?) {
        let context = item.chatInteraction.interactionContext
        if let table = item.table, table.window == nil {
            avatar.attemptLoadNextSynchronous = true
        }
        avatar.setPeer(account: context.account, peer: peer, message: message, size: nil, disableForum: false)
        avatar.attemptLoadNextSynchronous = false
        control.removeAllHandlers()
        control.set(handler: { [weak item] _ in
            if item?.chatInteraction.presentation.state == .selecting {
                item?.chatInteraction.toggleUnderMouseMessage()
            } else {
                item?.openInfo()
            }
        }, for: .Click)
        control.toolTip = item.nameHide
        control.accessibilityLabel = item.nameHide.flatMap { $0.isEmpty ? nil : $0 }
    }
}

final class ChatFloatingAvatar {
    static var usesNodes: Bool = true
    #if DEBUG
    static var parityMutation: CGFloat = 0
    #endif

    let view: ChatAvatarView?
    let node: ChatFloatingAvatarNode?

    init(_ item: ChatRowItem, reusing reusable: ChatFloatingAvatarNode? = nil) {
        if ChatFloatingAvatar.prefersNode(item), let peer = item.peer {
            let node = reusable ?? ChatFloatingAvatarNode()
            node.setPeer(item: item, peer: peer, message: item.message)
            if peer.id.id._internalGetInt64Value() != 0 {
                node.control.contextMenu = ChatRowView.photoContextMenu(item, peer: peer, setOpenProgress: { _ in })
            } else {
                node.control.contextMenu = nil
            }
            self.node = node
            self.view = nil
        } else {
            self.view = ChatRowView.makePhotoView(item)
            self.node = nil
        }
    }

    static func prefersNode(_ item: ChatRowItem) -> Bool {
        guard usesNodes, let peer = item.peer else { return false }
        if item.entry.additionalData.authorStoryStats != nil {
            return false
        }
        if peer.isPremium, peer.hasVideo, !TelegramUtilsHooks.shared.isLite(.animations) {
            return false
        }
        return true
    }

    func canPresent(_ item: ChatRowItem) -> Bool {
        return (node != nil) == ChatFloatingAvatar.prefersNode(item)
    }

    func setPeer(item: ChatRowItem, peer: Peer) {
        if let node {
            node.setPeer(item: item, peer: peer, message: item.message)
        } else {
            view?.setPeer(item: item, peer: peer, storyStats: item.entry.additionalData.authorStoryStats, message: item.message)
        }
    }

    var storyControl: NSView? {
        return view?.storyControl
    }
}
