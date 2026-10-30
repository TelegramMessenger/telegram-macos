import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatHistoryModel
import InputView
import MessageUtils

private var copyEvidence: CopyEvidence?
private let copyEvidenceRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TELEGRAM_COPY_EVIDENCE"] ?? NSTemporaryDirectory()).appendingPathComponent("telegram-copy-formatting")

final class CopyEvidenceButton: NSButton {
    var invoke: (() -> Void)?
    @objc func run() { invoke?() }
}

private final class CopyEvidence {
    var closeObserver: NSObjectProtocol?
    let window: Window
    let source: ChatInteraction
    let table: TableView
    let input: ChatInputTextView
    let status: NSTextField
    var checks: [[String: Any]] = []
    var item: ChatMessageItem!

    init(source: ChatInteraction) {
        try? FileManager.default.createDirectory(at: copyEvidenceRoot, withIntermediateDirectories: true)
        self.source = source
        let rect = NSMakeRect(0, 0, 860, 650)
        window = Window(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Message formatting — native clipboard round trip"
        let host = View(frame: rect)
        host.backgroundColor = theme.colors.chatBackground
        table = TableView(frame: NSMakeRect(10, 112, 410, 520))
        table.backgroundColor = theme.colors.chatBackground
        input = ChatInputTextView(frame: NSMakeRect(440, 112, 400, 520))
        input.theme = theme.inputTheme
        input.textView.isEditable = true
        status = NSTextField(labelWithString: "Run the production Copy callback, then paste into the native input.")
        status.textColor = theme.colors.text
        status.frame = NSMakeRect(20, 12, 820, 24)
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notification in
            self?.windowWillClose(notification)
        }
        host.addSubview(status)
        for (title, x) in [("Source message", 20.0), ("Pasted draft", 450.0)] {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.textColor = theme.colors.text
            label.frame = NSMakeRect(x, 80, 390, 25)
            host.addSubview(label)
        }
        host.addSubview(table)
        host.addSubview(input)
        let button = CopyEvidenceButton(frame: NSMakeRect(20, 43, 300, 30))
        button.title = "Copy message → Paste draft → Check"
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(CopyEvidenceButton.run)
        button.invoke = { [weak self] in self?.run() }
        host.addSubview(button)
        window.contentView = host
        let text = "Inline code: let answer = 42\n\nFirst quote\nSecond quote\n\nfunc hello() {\n    print(\"Hello\")\n}"
        let entities: [MessageTextEntity] = [entity(text, "let answer = 42", .Code), entity(text, "First quote", .BlockQuote(isCollapsed: false)), entity(text, "Second quote", .BlockQuote(isCollapsed: false)), entity(text, "func hello() {\n    print(\"Hello\")\n}", .Pre(language: "swift"))]
        item = row(text, entities)
        _ = table.addItem(item: item)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
    func windowWillClose(_ notification: Notification) {
        if copyEvidence === self {
            copyEvidence = nil
        }
    }

    func entity(_ text: String, _ part: String, _ type: MessageTextEntityType) -> MessageTextEntity {
        let r = (text as NSString).range(of: part)
        return MessageTextEntity(range: r.location ..< NSMaxRange(r), type: type)
    }

    func row(_ text: String, _ entities: [MessageTextEntity]) -> ChatMessageItem {
        let peer = source.peer!
        let message = Message(stableId: 5, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 5), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1782388800, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: peer, text: text, attributes: [TextEntitiesMessageAttribute(entities: entities)], media: [], peers: SimpleDictionary([peer.id: peer]), associatedMessages: .init(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        let entry = ChatHistoryEntry.MessageEntry(message, message.index, true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, .init())
        let result = ChatRowItem.item(NSMakeSize(410, 520), from: entry, interaction: source, theme: theme) as! ChatMessageItem
        _ = result.makeSize(410, oldWidth: 0)
        return result
    }

    func check(_ name: String, _ pass: Bool) {
        checks.append(["name": name, "pass": pass])
    }

    func copy(_ text: NSAttributedString) -> ChatTextInputState? {
        let copied = LinkHooks.shared.globalLinkExecutor().copyAttributedString(text)
        guard copied, let data = NSPasteboard.general.data(forType: .kInApp) else { return nil }
        return try? AdaptedPostboxDecoder().decode(ChatTextInputState.self, from: data)
    }

    func roundTrip(_ name: String, text: String, entities: [MessageTextEntity], range: NSRange? = nil) {
        let rendered = row(text, entities).messageText
        let selected = range.map { rendered.attributedSubstring(from: $0) } ?? rendered
        guard let decoded = copy(selected) else { check(name + ": clipboard decode", false); return }
        check(name + ": exact plain text", decoded.inputText == selected.string)
        check(name + ": plain pasteboard", NSPasteboard.general.string(forType: .string) == selected.string)
        check(name + ": RTF available", NSPasteboard.general.data(forType: .rtf) != nil)
        let pasted = decoded.unique(isPremium: false).attributedString()
        let state = ChatTextInputState(attributedText: pasted, selectionRange: 0 ..< pasted.length)
        let sent = state.subInputState(from: NSRange(location: 0, length: pasted.length))
        let start = range?.location ?? 0
        let end = range.map { NSMaxRange($0) } ?? (text as NSString).length
        let expected = entities.compactMap { entity -> MessageTextEntity? in
            let lower = max(start, entity.range.lowerBound)
            let upper = min(end, entity.range.upperBound)
            guard lower < upper else { return nil }
            return MessageTextEntity(range: lower - start ..< upper - start, type: entity.type)
        }
        let actualEntities = sent.messageTextEntities([])
        let selectedString = selected.string as NSString
        var trimStart = 0
        var trimEnd = selectedString.length
        while trimStart < trimEnd, selectedString.substring(with: NSRange(location: trimStart, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { trimStart += 1 }
        while trimEnd > trimStart, selectedString.substring(with: NSRange(location: trimEnd - 1, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { trimEnd -= 1 }
        let sendExpected = expected.compactMap { entity -> MessageTextEntity? in
            let lower = max(trimStart, entity.range.lowerBound)
            let upper = min(trimEnd, entity.range.upperBound)
            guard lower < upper else { return nil }
            return MessageTextEntity(range: lower - trimStart ..< upper - trimStart, type: entity.type)
        }
        check(name + ": copy entities", sameEntities(decoded.messageTextEntities([]), expected))
        check(name + ": pasted entities", sameEntities(state.messageTextEntities([]), expected))
        check(name + ": send preparation", sameEntities(actualEntities, sendExpected))
        check(name + ": quote boundaries", actualEntities.filter { if case .BlockQuote = $0.type { return true }; return false }.count == expected.filter { if case .BlockQuote = $0.type { return true }; return false }.count)
    }

    func sameEntities(_ lhs: [MessageTextEntity], _ rhs: [MessageTextEntity]) -> Bool {
        func canonical(_ entity: MessageTextEntity) -> MessageTextEntity {
            if case let .Pre(language) = entity.type {
                return MessageTextEntity(range: entity.range, type: .Pre(language: language ?? ""))
            }
            return entity
        }
        func merged(_ entities: [MessageTextEntity]) -> [MessageTextEntity] {
            var result: [MessageTextEntity] = []
            for entity in entities.map(canonical).sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
                if case .BlockQuote = entity.type {
                    result.append(entity)
                } else if let index = result.lastIndex(where: { $0.type == entity.type && $0.range.upperBound >= entity.range.lowerBound }) {
                    result[index].range = result[index].range.lowerBound ..< max(result[index].range.upperBound, entity.range.upperBound)
                } else {
                    result.append(entity)
                }
            }
            return result
        }
        var remaining = merged(rhs)
        for entity in merged(lhs) {
            guard let index = remaining.firstIndex(of: entity) else { return false }
            remaining.remove(at: index)
        }
        return remaining.isEmpty
    }

    func run() {
        checks.removeAll()
        let inline = "Inline let answer = 42 end"
        roundTrip("inline code", text: inline, entities: [entity(inline, "let answer = 42", .Code)])
        for language in [nil, "swift", "a-very-long-language-name"] as [String?] {
            let text = "func hello() {\n    print(\"Hello\")\n}"
            roundTrip("pre " + (language ?? "none"), text: text, entities: [MessageTextEntity(range: 0 ..< (text as NSString).length, type: .Pre(language: language))])
        }
        let quote = "First quote\nSecond quote"
        roundTrip("adjacent quotes", text: quote, entities: [entity(quote, "First quote", .BlockQuote(isCollapsed: false)), entity(quote, "Second quote", .BlockQuote(isCollapsed: false))])
        roundTrip("collapsed quote", text: quote, entities: [MessageTextEntity(range: 0 ..< (quote as NSString).length, type: .BlockQuote(isCollapsed: true))])
        let mixed = "🦄 quoted code text"
        roundTrip("UTF16 mixed selection", text: mixed, entities: [MessageTextEntity(range: 0 ..< (mixed as NSString).length, type: .BlockQuote(isCollapsed: false)), entity(mixed, "code", .Code), entity(mixed, "quoted", .Bold)], range: NSRange(location: 4, length: 11))
        let plain = "Plain text stays unchanged"
        roundTrip("plain", text: plain, entities: [])
        let languages = ChatTextInputState(inputText: "aaaabbbb", selectionRange: 0 ..< 0, attributes: [.pre(0..<4, "swift"), .pre(4..<8, "python")]).subInputState(from: NSRange(location: 0, length: 8))
        check("adjacent code languages do not merge", languages.attributes.count == 2)
        let quotes = ChatTextInputState(inputText: "aaaabbbb", selectionRange: 0 ..< 0, attributes: [.quote(0..<4, false), .quote(4..<8, true)]).subInputState(from: NSRange(location: 0, length: 8))
        check("adjacent input quotes do not merge", quotes.attributes.count == 2)
        check("adjacent rendered quotes do not merge", concatMessageAttributes([.init(range: 0..<4, type: .BlockQuote(isCollapsed: false)), .init(range: 4..<8, type: .BlockQuote(isCollapsed: true))]).count == 2)
        check("adjacent rendered code languages do not merge", concatMessageAttributes([.init(range: 0..<4, type: .Pre(language: "swift")), .init(range: 4..<8, type: .Pre(language: "python"))]).count == 2)

        if let decoded = copy(item.messageText) {
            input.attributedText = textAttributedStringForStateText(decoded.unique(isPremium: false).attributedString(), fontSize: 15, textColor: theme.colors.text, accentTextColor: theme.colors.accent, writingDirection: nil, spoilersRevealed: false, availableEmojis: [])
            input.updateLayout(size: NSMakeSize(400, 520), textHeight: 500, transition: .immediate)
        }
        let passed = checks.filter { $0["pass"] as? Bool == true }.count
        status.stringValue = "\(passed)/\(checks.count) checks passed · Production Copy → .kInApp → native draft"
        if let data = try? JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: copyEvidenceRoot.appendingPathComponent("models.json"), options: .atomic)
        }
    }
}

func codexInstallCopyEvidence(source: ChatInteraction, parent: NSView) {
    guard source.mode == .history else { return }
    guard !parent.subviews.contains(where: { $0 is CopyEvidenceButton }) else { return }
    let button = CopyEvidenceButton(frame: NSMakeRect(20, 130, 230, 30))
    button.title = "Clipboard formatting validation"
    button.bezelStyle = .rounded
    button.target = button
    button.action = #selector(CopyEvidenceButton.run)
    button.invoke = { [weak source] in
        guard let source else { return }
        copyEvidence?.window.close()
        copyEvidence = CopyEvidence(source: source)
    }
    parent.addSubview(button)
}
