import Cocoa
import TGUIKit
import TelegramContext

final class ChatLayerMessageTextView: ChatLayerSceneView {
    struct Identity: Hashable {
        let messageId: AnyHashable
        let accountId: ObjectIdentifier
    }

    let body = ChatLayerMessageTextNode(id: "message-text")
    private var identity: Identity?
    private var bindingVersion: UInt64 = 0
    private var inlineEmoji: [Int: ChatLayerInlineEmoji] = [:]
    private var inlineEmojiObserver: AnimatableContentObserver?
    private var inlineEmojiFallbackTextColor: NSColor { presentation.colors.text }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect, ownedRoot: body)
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func supports(_ presentation: ChatLayerMessageTextPresentation, hasRevealAction: Bool = false) -> Bool {
        guard !presentation.blocks.isEmpty, presentation.nativeFeatures.isEmpty, !presentation.requiresRevealAction || hasRevealAction else { return false }
        for block in presentation.blocks where !block.layout.embeddedItems.isEmpty {
            guard !presentation.requiresRevealAction, !block.clipsTextToBounds, block.folding == nil, ChatLayerInlineEmoji.supports(block.layout) else { return false }
        }
        return true
    }

    @discardableResult
    func update(_ presentation: ChatLayerMessageTextPresentation, identity: Identity, context: (any AccountContextProtocol)? = nil, animated: Bool = false) -> Bool {
        guard Self.supports(presentation, hasRevealAction: body.revealBlockAtIndex != nil) else { return false }
        guard context != nil || presentation.blocks.allSatisfy({ $0.layout.embeddedItems.isEmpty }) else { return false }
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
            guard try body.update(presentation, messageId: identity.messageId, selectable: true, preservingSelectionGesture: sameMessage, transition: animated && sameMessage ? .animated(duration: 0.2, curve: .easeOut) : .immediate), bindingVersion == version else { return false }
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
        if !inlineEmoji.isEmpty || presentation.blocks.contains(where: { !$0.layout.embeddedItems.isEmpty }) {
            for index in Array(inlineEmoji.keys) where !presentation.blocks.indices.contains(index) || presentation.blocks[index].layout.embeddedItems.isEmpty {
                inlineEmoji.removeValue(forKey: index)?.detach()
                guard bindingVersion == version else { return false }
            }
            if let context {
                for index in presentation.blocks.indices where !presentation.blocks[index].layout.embeddedItems.isEmpty {
                    let owner = inlineEmoji[index] ?? ChatLayerInlineEmoji()
                    inlineEmoji[index] = owner
                    guard owner.update(presentation.blocks[index].layout, context: context, fallbackTextColor: inlineEmojiFallbackTextColor, refreshVisibility: false), bindingVersion == version else { return false }
                    owner.attach(to: body.textNodes[index].layer, host: self, refreshVisibility: false)
                    guard bindingVersion == version else { return false }
                }
            }
        }
        updateInlineEmojiObservation()
        guard bindingVersion == version else { return false }
        isEventLess = false
        return true
    }

    @discardableResult
    func prepareForRemoval() -> Bool {
        bindingVersion &+= 1
        let version = bindingVersion
        let removedEmoji = inlineEmoji
        inlineEmoji.removeAll()
        inlineEmojiObserver = nil
        removedEmoji.values.forEach { $0.detach() }
        guard bindingVersion == version else { return false }
        body.revealBlockAtIndex = nil
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

    func updateInlineEmojiVisibility() {
        guard !inlineEmoji.isEmpty else { return }
        let visibility = ChatLayerInlineEmoji.visibility(in: self, anchor: root.layer)
        for owner in inlineEmoji.values { owner.updateVisibility(visibility, from: self) }
    }

    @objc private func inlineEmojiVisibilityChanged() {
        updateInlineEmojiVisibility()
    }

    private func updateInlineEmojiObservation() {
        if inlineEmoji.isEmpty || window == nil {
            inlineEmojiObserver = nil
        } else {
            let observer = inlineEmojiObserver ?? AnimatableContentObserver()
            inlineEmojiObserver = observer
            observer.update(for: self, target: self, selector: #selector(inlineEmojiVisibilityChanged), options: [.contentBounds, .documentFrame, .ownFrame, .ownBounds])
        }
        updateInlineEmojiVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateInlineEmojiObservation()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateInlineEmojiObservation()
    }

    override func layout() {
        super.layout()
        updateInlineEmojiObservation()
    }

    override var isHidden: Bool {
        didSet { updateInlineEmojiVisibility() }
    }

    override var alphaValue: CGFloat {
        didSet { updateInlineEmojiVisibility() }
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
                return index >= 0 && !layout.isOutsideText(point, line: index)
            }
        }
        return false
    }
}
