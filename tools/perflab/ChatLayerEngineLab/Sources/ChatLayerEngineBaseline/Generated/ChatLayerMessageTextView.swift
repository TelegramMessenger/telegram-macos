import Cocoa
import TGUIKit

final class ChatLayerMessageTextView: ChatLayerSceneView {
    struct Identity: Hashable {
        let messageId: AnyHashable
        let accountId: ObjectIdentifier
    }

    let body = ChatLayerMessageTextNode(id: "message-text")
    private var identity: Identity?
    private var bindingVersion: UInt64 = 0

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect, ownedRoot: body)
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func supports(_ presentation: ChatLayerMessageTextPresentation) -> Bool {
        return !presentation.blocks.isEmpty && presentation.nativeFeatures.isEmpty && !presentation.requiresRevealAction && presentation.blocks.allSatisfy {
            $0.folding == nil
        }
    }

    @discardableResult
    func update(_ presentation: ChatLayerMessageTextPresentation, identity: Identity) -> Bool {
        guard Self.supports(presentation) else { return false }
        bindingVersion &+= 1
        let version = bindingVersion
        let sameMessage = self.identity == identity
        if !sameMessage, hasActiveInput {
            cancelInput()
            guard bindingVersion == version else { return false }
        }
        if let previous = self.identity, previous.accountId != identity.accountId {
            for node in body.textNodes {
                node.resetInteraction()
                guard bindingVersion == version else { return false }
            }
        }
        var externallySelected: [Int] = []
        if sameMessage {
            for (index, pair) in zip(body.textNodes, presentation.blocks).enumerated() {
                let (node, block) = pair
                if let previous = node.textLayout, previous !== block.layout,
                   previous.attributedString.string == block.layout.attributedString.string,
                   block.layout.selectedRange.range.location == NSNotFound {
                    block.layout.selectedRange = previous.selectedRange
                    if node.hasExternalTextSelection { externallySelected.append(index) }
                }
            }
        }
        self.identity = identity
        do {
            guard try body.update(presentation, messageId: identity.messageId, selectable: true, preservingSelectionGesture: sameMessage), bindingVersion == version else { return false }
        } catch {
            return false
        }
        if selectableTextNodeIds.count != body.textNodes.count { selectableTextNodeIds = body.selectableTextNodeIds }
        guard bindingVersion == version else { return false }
        for index in externallySelected {
            let node = body.textNodes[index]
            if let range = node.textLayout?.selectedRange.range { node.setExternalSelection(range) }
            guard bindingVersion == version else { return false }
        }
        isEventLess = false
        return true
    }

    @discardableResult
    func prepareForRemoval() -> Bool {
        bindingVersion &+= 1
        let version = bindingVersion
        cancelInput()
        guard bindingVersion == version else { return false }
        for node in body.textNodes {
            node.resetInteraction()
            guard bindingVersion == version else { return false }
        }
        selectableTextNodeIds = []
        guard bindingVersion == version else { return false }
        isEventLess = true
        return true
    }

    func firstTextBaseline(in view: NSView) -> NSPoint? {
        guard let node = body.textNodes.first, let line = node.textLayout?.lines.first else { return nil }
        let point = node.layer.convert(NSPoint(x: line.frame.minX, y: line.frame.minY), to: root.layer)
        return convert(point, to: view)
    }

    func clickInContent(point: NSPoint) -> Bool {
        for node in body.textNodes {
            let point = node.layer.convert(point, from: root.layer)
            if node.layer.bounds.contains(point), let layout = node.textLayout, !layout.lines.isEmpty {
                let index = layout.findIndex(location: point)
                return index >= 0 && point.x < layout.lines[index].frame.maxX
            }
        }
        return false
    }
}
