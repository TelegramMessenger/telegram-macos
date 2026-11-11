import Cocoa
import TGUIKit
import InputTextView

final class ReferenceMessageBindingNode: ChatLayerNode {
    private struct BlockId: Hashable {
        let parent: AnyHashable
        let index: Int
    }

    var revealBlockAtIndex: ((Int) -> Void)?
    private var messageId: AnyHashable?
    private(set) var textNodes: [ChatLayerTextNode] = []
    var selectableTextNodeIds: [AnyHashable] {
        return textNodes.compactMap { $0.isSelectable ? $0.id : nil }
    }

    func highlight(text: String, color: NSColor, range: NSRange? = nil, in layout: FoldingTextLayout) {
        guard textNodes.count == layout.blocks.count, zip(textNodes, layout.blocks).allSatisfy({ $0.textLayout === $1.text }) else { return }
        let string = layout.attributedString.string as NSString
        if let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= string.length, range.length <= string.length - range.location, string.substring(with: range) == text {
            var highlighted = false
            for (node, pair) in zip(textNodes, zip(layout.blocks, layout.blockRanges)) {
                let (block, blockRange) = pair
                if let intersection = blockRange.intersection(range) {
                    let localRange = NSRange(location: intersection.location - blockRange.location, length: intersection.length)
                    let localString = block.text.attributedString.string as NSString
                    guard localRange.location >= 0, localRange.location <= localString.length, localRange.length <= localString.length - localRange.location else { continue }
                    node.highlight(text: localString.substring(with: localRange), color: color, range: localRange)
                    highlighted = true
                }
            }
            if highlighted { return }
        }
        for node in textNodes {
            node.highlight(text: text, color: color)
        }
    }

    @discardableResult
    func update(_ presentation: ChatLayerMessageTextPresentation, messageId: AnyHashable, selectable: Bool) throws -> Bool {
        guard presentation.nativeFeatures.isEmpty, !presentation.requiresRevealAction || revealBlockAtIndex != nil else {
            try setChildren([])
            for node in textNodes { node.resetInteraction() }
            textNodes.removeAll()
            self.messageId = nil
            frame.size = .zero
            return false
        }
        var nodes = textNodes
        if nodes.count > presentation.blocks.count { nodes.removeSubrange(presentation.blocks.count...) }
        while nodes.count < presentation.blocks.count {
            nodes.append(ChatLayerTextNode(id: BlockId(parent: id, index: nodes.count), selectable: selectable))
        }
        try setChildren(nodes)
        for node in textNodes.dropFirst(nodes.count) { node.resetInteraction() }
        let changedMessage = self.messageId != messageId
        for (index, pair) in zip(nodes, presentation.blocks).enumerated() {
            let (node, block) = pair
            if changedMessage || !selectable { node.resetInteraction() }
            node.isSelectable = selectable
            node.setQuoteClipping(block.clipsTextToBounds, rounded: block.folding != nil)
            node.updateFolding(block.folding?.layout)
            if block.folding != nil {
                if node.onTextClick == nil {
                    node.onTextClick = { [weak self] in
                        guard let self, !self.textNodes.contains(where: { $0.textLayout?.selectedRange.hasSelectText == true }), let reveal = self.revealBlockAtIndex else { return false }
                        reveal(index)
                        return true
                    }
                }
            } else if node.onTextClick != nil {
                node.onTextClick = nil
            }
            node.update(block.layout, knownHasLinks: block.hasLinks, frame: block.frame)
            if block.clipsTextToBounds || !node.children.isEmpty { try node.updateCodeHeaders() }
        }
        textNodes = nodes
        self.messageId = messageId
        frame.size = presentation.size
        return true
    }
}
