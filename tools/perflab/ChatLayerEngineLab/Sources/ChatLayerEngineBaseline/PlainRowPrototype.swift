import Cocoa
import TGUIKit
import InputTextView

struct RowPart {
    enum Content {
        case group(NSColor, CGFloat)
        case text(TextViewLayout, Bool)
        case message(FoldingTextLayout)
        case button(String, NSColor)
    }
    let id: String
    var frame: NSRect
    let content: Content
    var children: [RowPart] = []
}

struct PlainRowFixture {
    let size: NSSize
    let parts: [RowPart]

    init(width: CGFloat = 460, variant: Int = 0, includeEmoji: Bool = true, quote: Bool = false, folded: Bool? = nil, codeHeader: Bool = false) {
        let incoming = variant % 2 == 0
        let dark = variant % 4 >= 2
        let bubbleWidth = max(220, width - 80)
        let foreground: NSColor = dark ? .white : .black
        let muted: NSColor = dark ? NSColor(white: 0.75, alpha: 1) : .darkGray
        let accent: NSColor = dark ? NSColor(calibratedRed: 0.4, green: 0.75, blue: 1, alpha: 1) : .systemBlue
        let background: NSColor = dark ? NSColor(calibratedRed: 0.13, green: 0.22, blue: 0.28, alpha: 1) : NSColor(calibratedRed: 0.89, green: 0.95, blue: 0.99, alpha: 1)
        func text(_ value: String, font: NSFont = .systemFont(ofSize: 14), color: NSColor? = nil, constrained: CGFloat? = nil, quote: Bool = false) -> TextViewLayout {
            let value = includeEmoji ? value : ["👩🏽‍💻", "🦆", "👍", "👨‍👩‍👧‍👦", "🇦🇪"].reduce(value) { $0.replacingOccurrences(of: $1, with: "e") }
            let attributed = NSMutableAttributedString(string: value, attributes: [.font: font, .foregroundColor: color ?? foreground])
            let link = (value as NSString).range(of: "example.org")
            if link.location != NSNotFound { attributed.addAttributes([.link: "https://example.org", .foregroundColor: accent], range: link) }
            if quote {
                let header: (TextNodeLayout, TextNode)? = codeHeader ? TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: accent]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left) : nil
                attributed.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 1, colors: .init(main: accent), isCode: codeHeader, header: header, collapsable: folded != nil), range: NSRange(location: 0, length: attributed.length))
            }
            let layout = TextViewLayout(attributed, selectText: accent.withAlphaComponent(0.3))
            layout.measure(width: constrained ?? bubbleWidth - 32)
            return layout
        }
        func label(_ id: String, _ value: String, _ origin: NSPoint, font: NSFont = .systemFont(ofSize: 14), color: NSColor? = nil, constrained: CGFloat? = nil, selectable: Bool = false) -> RowPart {
            let isQuote = id == "body" && (quote || folded != nil || codeHeader)
            let value = id == "body" && folded != nil ? value + "\nA further quoted line.\nOne more quoted line.\nThe final quoted line." : value
            let layout = text(value, font: font, color: color, constrained: constrained, quote: isQuote)
            if isQuote {
                let block = FoldingTextLayout.ViewLayout(text: layout).measured(width: constrained ?? bubbleWidth - 32, revealed: folded != true)
                let source = FoldingTextLayout(blocks: [block])
                return RowPart(id: id, frame: NSRect(origin: origin, size: source.size), content: .message(source))
            }
            return RowPart(id: id, frame: NSRect(origin: origin, size: layout.layoutSize), content: .text(layout, selectable))
        }
        let messages = [
            "A complete row with selectable text, links, replies and reactions. Visit example.org to try a link.\nDrag across lines to select text. 👩🏽‍💻 🦆",
            "مرحبا بالعالم — English and שלום.\nText selection should keep the same glyph positions. example.org",
            "中文 日本語 한글\nCombining marks: café and emoji: 👩🏽‍💻 👨‍👩‍👧‍👦 🇦🇪.\nexample.org",
            "A short message. example.org"
        ]
        let author = label("author", incoming ? "Alex" : "You", NSPoint(x: 16, y: 12), font: .boldSystemFont(ofSize: 14), color: accent)
        let forward = label("forward", "Forwarded from Design", NSPoint(x: 16, y: 33), font: .systemFont(ofSize: 12), color: muted)
        let replyName = label("reply.name", "Morgan", NSPoint(x: 10, y: 5), font: .boldSystemFont(ofSize: 12), color: accent)
        let replyText = label("reply.text", "Let's check the interaction details", NSPoint(x: 10, y: 23), font: .systemFont(ofSize: 12), color: muted, constrained: bubbleWidth - 60)
        let reply = RowPart(id: "reply", frame: NSRect(x: 16, y: 56, width: bubbleWidth - 32, height: 45), content: .button("Open replied message", accent.withAlphaComponent(0.08)), children: [replyName, replyText])
        let body = label("body", messages[variant % messages.count], NSPoint(x: 16, y: 112), selectable: true)
        let bottom = body.frame.maxY + 12
        let time = label("time", "edited 12:34 ✓✓", NSPoint(x: bubbleWidth - 118, y: bottom), font: .systemFont(ofSize: 11), color: muted)
        let bubbleHeight = bottom + 28
        let bubble = RowPart(id: "bubble", frame: NSRect(x: incoming ? 56 : 16, y: 8, width: bubbleWidth, height: bubbleHeight), content: .group(background, 14), children: [author, forward, reply, body, time])
        let avatarText = label("avatar.text", "A", NSPoint(x: 13, y: 10), font: .boldSystemFont(ofSize: 16), color: .white)
        let avatar = RowPart(id: "avatar", frame: NSRect(x: incoming ? 8 : width - 48, y: 8 + bubbleHeight - 40, width: 40, height: 40), content: .button("Open profile", accent), children: [avatarText])
        let reactionLabel = label("reaction.text", "👍 4", NSPoint(x: 10, y: 5), font: .systemFont(ofSize: 13), color: accent)
        let reaction = RowPart(id: "reaction", frame: NSRect(x: bubble.frame.minX + 12, y: bubble.frame.maxY + 6, width: 64, height: 28), content: .button("React with thumbs up, 4 reactions", background), children: [reactionLabel])
        let actionLabel = label("action.text", "Reply", NSPoint(x: 10, y: 5), font: .systemFont(ofSize: 13), color: accent)
        let action = RowPart(id: "action", frame: NSRect(x: bubble.frame.maxX - 70, y: bubble.frame.maxY + 6, width: 64, height: 28), content: .button("Reply", background), children: [actionLabel])
        parts = [bubble, avatar, reaction, action]
        size = NSSize(width: width, height: bubble.frame.maxY + 46)
    }
}

final class NativePlainRow {
    let view: View
    private(set) var views: [String: View] = [:]
    var onAction: ((String) -> Void)?
    var onToggle: (() -> Void)?

    init(_ fixture: PlainRowFixture) {
        view = View(frame: NSRect(origin: .zero, size: fixture.size))
        view.backgroundColor = .clear
        bind(fixture)
    }

    func bind(_ fixture: PlainRowFixture) {
        view.setFrameSize(fixture.size)
        func visit(_ part: RowPart, parent: View) {
            let current: View
            switch part.content {
            case let .message(layout):
                for block in layout.blocks {
                    block.text.interactions.processURL = { [weak self] _ in self?.onAction?("link") }
                    block.text.interactions.copyToClipboard = { [weak self] _ in self?.onAction?("copy code") }
                }
                if let view = views[part.id], isReferenceFoldingWrapper(view) {
                    updateReferenceFoldingWrapper(view, layout: layout.blocks[0])
                    current = view
                } else {
                    current = makeReferenceFoldingWrapper(layout.blocks[0])
                }
                if let text = current.subviews.first as? TextView {
                    text.removeAllHandlers()
                    if layout.blocks[0].canReveal {
                        text.sendDownAnyway = true
                        var ignoreNext = false
                        text.set(handler: { control in ignoreNext = (control as? TextView)?.selectionWasCleared == true }, for: .Down)
                        text.set(handler: { [weak self, weak text] _ in
                            if text?.textLayout?.selectedRange.hasSelectText == false && !ignoreNext { self?.onToggle?() }
                        }, for: .Click)
                    }
                }
            case let .text(layout, selectable):
                layout.interactions.processURL = { [weak self] _ in self?.onAction?("link") }
                let text = (views[part.id] as? TextView) ?? TextView()
                text.isSelectable = selectable
                text.userInteractionEnabled = selectable
                text.disableBackgroundDrawing = true
                text.update(layout)
                current = text
            case let .button(label, color):
                let button = (views[part.id] as? Control) ?? Control(frame: part.frame)
                button.backgroundColor = color
                button.layer?.cornerRadius = part.id == "avatar" ? 20 : 8
                button.setAccessibilityRole(.button)
                button.setAccessibilityLabel(label)
                button.set(handler: { [weak self] _ in self?.onAction?(part.id) }, for: .Click)
                current = button
            case let .group(color, radius):
                current = views[part.id] ?? View(frame: part.frame)
                current.backgroundColor = color
                current.layer?.cornerRadius = radius
            }
            if !isReferenceFoldingWrapper(current) { current.layer?.masksToBounds = false }
            if #available(macOS 10.15, *) { current.layer?.cornerCurve = .circular }
            current.frame = part.frame
            if let previous = views[part.id], previous !== current { previous.removeFromSuperview() }
            if current.superview !== parent { parent.addSubview(current) }
            views[part.id] = current
            for child in part.children { visit(child, parent: current) }
        }
        for part in fixture.parts { visit(part, parent: view) }
        view.layoutSubtreeIfNeeded()
    }
}

final class LayerPlainRow {
    let view: ChatLayerSceneView
    private(set) var nodes: [String: ChatLayerNode] = [:]
    var onAction: ((String) -> Void)?
    var onToggle: (() -> Void)?

    init(_ fixture: PlainRowFixture) {
        view = ChatLayerSceneView(frame: NSRect(origin: .zero, size: fixture.size))
        view.backgroundColor = .clear
        bind(fixture)
    }

    func bind(_ fixture: PlainRowFixture) {
        view.setFrameSize(fixture.size)
        func visit(_ part: RowPart) -> ChatLayerNode {
            let node: ChatLayerNode
            switch part.content {
            case let .message(layout):
                for block in layout.blocks {
                    block.text.interactions.processURL = { [weak self] _ in self?.onAction?("link") }
                    block.text.interactions.copyToClipboard = { [weak self] _ in self?.onAction?("copy code") }
                }
                let message = (nodes[part.id] as? ChatLayerMessageTextNode) ?? ChatLayerMessageTextNode(id: part.id)
                message.revealBlockAtIndex = { [weak self] _ in self?.onToggle?() }
                try! message.update(ChatLayerMessageTextPresentation(layout), messageId: ObjectIdentifier(layout), selectable: true)
                node = message
            case let .text(layout, selectable):
                layout.interactions.processURL = { [weak self] _ in self?.onAction?("link") }
                let text = (nodes[part.id] as? ChatLayerTextNode) ?? ChatLayerTextNode(id: part.id, selectable: selectable)
                text.update(layout)
                node = text
            case let .button(label, color):
                let button = (nodes[part.id] as? ChatLayerButtonNode) ?? ChatLayerButtonNode(id: part.id, label: label, action: { [weak self] in self?.onAction?(part.id) })
                button.layer.backgroundColor = color.cgColor
                button.layer.cornerRadius = part.id == "avatar" ? 20 : 8
                node = button
            case let .group(color, radius):
                node = nodes[part.id] ?? ChatLayerNode(id: part.id)
                node.layer.backgroundColor = color.cgColor
                node.layer.cornerRadius = radius
            }
            node.layer.edgeAntialiasingMask = []
            node.frame = part.frame
            nodes[part.id] = node
            if !(node is ChatLayerMessageTextNode) { try! node.setChildren(part.children.map(visit)) }
            return node
        }
        try! view.root.setChildren(fixture.parts.map(visit))
        view.selectableTextNodeIds = (nodes["body"] as? ChatLayerMessageTextNode)?.selectableTextNodeIds ?? ["body"]
        view.layoutSubtreeIfNeeded()
    }
}

public enum ChatLayerDemo {
    private static var retainedImages: [NSImage] = []
    public static func bootstrap() {
        guard retainedImages.isEmpty else { return }
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                NSColor.black.setFill(); rect.insetBy(dx: 4, dy: 4).fill(); return true
            }
            image.setName(name)
            retainedImages.append(image)
        }
    }
    public static func makeDocument(layerBased: Bool, count: Int, onAction: @escaping (String) -> Void) -> NSView {
        return RowDocument(layerBased: layerBased, count: count, onAction: onAction)
    }
}

private final class RowDocument: View {
    private var nativeRows: [NativePlainRow] = []
    private var layerRows: [LayerPlainRow] = []
    private var selection: LayerDocumentSelection?
    init(layerBased: Bool, count: Int, onAction: @escaping (String) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 0))
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.1, blue: 0.13, alpha: 1)
        var offset: CGFloat = 12
        for i in 0..<count {
            let foldable = i % 10 == 0
            var folded = true
            let fixture = PlainRowFixture(variant: i, quote: i % 5 == 0, folded: foldable ? folded : nil, codeHeader: i % 7 == 1)
            let row: View
            if layerBased {
                let value = LayerPlainRow(fixture)
                value.onAction = { onAction("Row \(i + 1): \($0)") }
                if foldable {
                    value.onToggle = { [weak self, weak value] in
                        folded.toggle()
                        value?.bind(PlainRowFixture(variant: i, quote: true, folded: folded, codeHeader: i % 7 == 1))
                        self?.positionRows()
                        onAction("Row \(i + 1): \(folded ? "collapsed" : "expanded")")
                    }
                }
                layerRows.append(value)
                row = value.view
            } else {
                let value = NativePlainRow(fixture)
                value.onAction = { onAction("Row \(i + 1): \($0)") }
                if foldable {
                    value.onToggle = { [weak self, weak value] in
                        folded.toggle()
                        value?.bind(PlainRowFixture(variant: i, quote: true, folded: folded, codeHeader: i % 7 == 1))
                        self?.positionRows()
                        onAction("Row \(i + 1): \(folded ? "collapsed" : "expanded")")
                    }
                }
                nativeRows.append(value)
                row = value.view
            }
            row.setFrameOrigin(NSPoint(x: 0, y: offset))
            addSubview(row)
            offset += fixture.size.height
        }
        setFrameSize(NSSize(width: 460, height: offset + 12))
        if layerBased { selection = LayerDocumentSelection(document: self, scenes: layerRows.map(\.view)) }
    }
    private func positionRows() {
        var y: CGFloat = 12
        for row in subviews {
            row.setFrameOrigin(NSPoint(x: 0, y: y))
            y += row.frame.height
        }
        setFrameSize(NSSize(width: 460, height: y + 12))
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        selection?.bind(to: window as? Window)
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityChildren() -> [Any]? {
        if !layerRows.isEmpty { return layerRows.map(\.view) }
        return NSAccessibility.unignoredChildren(from: nativeRows.map(\.view))
    }
    required init(frame frameRect: NSRect) { fatalError() }
    required init?(coder: NSCoder) { fatalError() }
}
