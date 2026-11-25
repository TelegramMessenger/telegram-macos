import Foundation
import TelegramCore
import Postbox
import RichTextEditorCore
import RichTextEditorUI
import InputView
import TelegramUtils
import InstantPageUI

// MARK: - Button action codec

/// The ONE place `ReplyMarkupButtonAction` and `RichTextEditorCore.ButtonAction` are translated.
/// Both directions live here so they cannot drift. `RichTextEditorCore` is Telegram-free, so it can
/// name only the actions the editor can author or meaningfully describe (`url`, `copyText`, `userProfile`,
/// `disabled`); everything else is preserved verbatim as `.unsupported(kind:payload:)`, whose
/// `payload` is the base64 of the action's own Postbox blob. Nothing outside this section may read
/// or construct those two fields.

/// Discriminates blobs this codec produced. Persisted inside Document JSON (`.rtdoc` / fragments),
/// so it must match iOS byte-for-byte. A `Document` can arrive from a newer build carrying a kind
/// this build does not know, so the decode side checks it.
private let unsupportedActionKind = "replyMarkupButtonAction"

public func buttonAction(from action: ReplyMarkupButtonAction) -> ButtonAction {
    switch action {
    case let .url(url):
        return .url(url)
    case let .copyText(payload):
        return .copyText(payload)
    case .disabled:
        return .disabled
    case let .openUserProfile(peerId):
        return .userProfile(peerId: peerId.toInt64())
    case .callback, .urlAuth, .openWebView, .switchInline, .openWebApp, .payment,
         .text, .requestPhone, .requestMap, .setupPoll, .requestPeer:
        let encoder = PostboxEncoder()
        action.encode(encoder)
        return .unsupported(kind: unsupportedActionKind, payload: encoder.makeData().base64EncodedString())
    }
}

public func replyMarkupButtonAction(from action: ButtonAction) -> ReplyMarkupButtonAction {
    switch action {
    case let .url(url):
        return .url(url)
    case let .copyText(payload):
        return .copyText(payload: payload)
    case let .userProfile(peerId):
        let peerId = PeerId(peerId)
        guard peerId.namespace == Namespaces.Peer.CloudUser else {
            return .disabled
        }
        return .openUserProfile(peerId: peerId)
    case .disabled:
        return .disabled
    case let .unsupported(kind, payload):
        // An unknown kind, or a payload this build cannot decode, degrades to `.disabled` rather
        // than crashing or trapping on a malformed buffer.
        guard kind == unsupportedActionKind, let data = Data(base64Encoded: payload), !data.isEmpty else {
            return .disabled
        }
        return ReplyMarkupButtonAction(decoder: PostboxDecoder(buffer: MemoryBuffer(data: data)))
    }
}

public func buttonColor(from color: ReplyMarkupButton.Style.Color?) -> ButtonColor? {
    guard let color else {
        return nil
    }
    switch color {
    case .primary: return .primary
    case .danger:  return .danger
    case .success: return .success
    }
}

public func replyMarkupColor(from color: ButtonColor?) -> ReplyMarkupButton.Style.Color? {
    guard let color else {
        return nil
    }
    switch color {
    case .primary: return .primary
    case .danger:  return .danger
    case .success: return .success
    }
}

public func buttonRowAlignment(from alignment: InstantPageButtonRowAlignment) -> ButtonRowAlignment {
    switch alignment {
    case .justify: return .justify
    case .left:    return .left
    case .center:  return .center
    case .right:   return .right
    }
}

public func instantPageRowAlignment(from alignment: ButtonRowAlignment) -> InstantPageButtonRowAlignment {
    switch alignment {
    case .justify: return .justify
    case .left:    return .left
    case .center:  return .center
    case .right:   return .right
    }
}

/// Reverse of the plain path: build an editor `Document` from a message's text + inline entities, so the
/// editor can be opened pre-seeded when editing a message. Text is split into paragraphs on "\n"; inline
/// entities map to `CharacterAttributes` runs. Structural InstantPage content (tables/lists/media in a
/// `RichTextMessageAttribute`) is not reconstructed here — its `message.text` (caption/fallback) is seeded.
public func richTextDocument(from message: Message) -> Document {
    // Rich messages keep their content in an InstantPage (message.text is empty) — reconstruct from it.
    if let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
        let blocks = documentBlocks(from: rich.instantPage)
        return Document(blocks: blocks.isEmpty ? [.paragraph(ParagraphBlock(id: BlockID.generate()))] : blocks)
    }
    let entities = message.attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first?.entities ?? []
    return richTextDocument(text: message.text, entities: entities)
}

/// Build an editor `Document` from plain text + inline entities (the chat composer's currency). Shared by
/// the message-edit and composer-handoff seeding paths.
public func richTextDocument(text: String, entities: [MessageTextEntity]) -> Document {
    let nsText = text as NSString
    // `.Pre` entities become REAL code blocks (with language) — the chat carries code as an entity,
    // the editor as a first-class block; without the split the code would arrive as inline monospace.
    let preSpans: [(range: NSRange, language: String?)] = entities.compactMap { entity in
        guard case let .Pre(language) = entity.type else { return nil }
        let lower = max(0, entity.range.lowerBound), upper = min(nsText.length, entity.range.upperBound)
        guard lower < upper else { return nil }
        return (NSRange(location: lower, length: upper - lower), language)
    }.sorted { $0.range.location < $1.range.location }

    var blocks: [Block] = []
    var cursor = 0
    var afterCode = false
    func appendParagraphs(upTo end: Int, beforeCode: Bool) {
        guard end > cursor else { return }
        var range = NSRange(location: cursor, length: end - cursor)
        // A lone newline separating the text from the adjacent code block is structure, not a blank line.
        if afterCode, range.length > 0, nsText.character(at: range.location) == 10 {
            range.location += 1; range.length -= 1
        }
        if beforeCode, range.length > 0, nsText.character(at: range.location + range.length - 1) == 10 {
            range.length -= 1
        }
        guard range.length > 0 else { return }
        let segEntities: [MessageTextEntity] = entities.compactMap { entity in
            if case .Pre = entity.type { return nil }
            let lower = max(entity.range.lowerBound, range.location)
            let upper = min(entity.range.upperBound, range.location + range.length)
            guard lower < upper else { return nil }
            return MessageTextEntity(range: (lower - range.location) ..< (upper - range.location), type: entity.type)
        }
        blocks += richTextParagraphBlocks(text: nsText.substring(with: range), entities: segEntities)
    }
    for span in preSpans where span.range.location >= cursor {
        appendParagraphs(upTo: span.range.location, beforeCode: true)
        let code = nsText.substring(with: span.range).trimmingCharacters(in: .newlines)
        blocks.append(.code(CodeBlock(id: BlockID.generate(),
                                      language: (span.language?.isEmpty == false) ? span.language : nil,
                                      runs: [TextRun(text: code)])))
        cursor = span.range.location + span.range.length
        afterCode = true
    }
    appendParagraphs(upTo: nsText.length, beforeCode: false)

    if blocks.isEmpty {
        blocks = [.paragraph(ParagraphBlock(id: BlockID.generate()))]
    }
    return Document(blocks: blocks)
}

private func richTextParagraphBlocks(text: String, entities: [MessageTextEntity]) -> [Block] {
    let nsText = text as NSString
    let length = nsText.length

    // Accumulate per-UTF-16-unit attributes from the (possibly overlapping) entities.
    var unitAttrs = [CharacterAttributes](repeating: .plain, count: length)
    for entity in entities {
        let lower = max(0, entity.range.lowerBound)
        let upper = min(length, entity.range.upperBound)
        guard lower < upper else { continue }
        // One EmojiRef PER ENTITY (not per unit): the whole alt span shares it, so run grouping folds it
        // into a single U+FFFC atom, while adjacent identical emoji keep distinct instanceIDs.
        var entityEmoji: EmojiRef? = nil
        if case let .CustomEmoji(_, fileId) = entity.type {
            let alt = nsText.substring(with: NSRange(location: lower, length: upper - lower))
            entityEmoji = EmojiRef(id: "\(fileId)", instanceID: BlockID.generate().rawValue, altText: alt)
        }
        for i in lower ..< upper {
            var a = unitAttrs[i]
            switch entity.type {
            case .Bold: a.bold = true
            case .Italic: a.italic = true
            case .Underline: a.underline = true
            case .Strikethrough: a.strikethrough = true
            case .Code, .Pre: a.inlineCode = true
            case .Spoiler: a.spoiler = true
            case let .TextUrl(url): a.link = url
            case let .TextMention(peerId):
                if peerId.namespace == Namespaces.Peer.CloudUser { a.link = "tg://user?id=\(peerId.id._internalGetInt64Value())" }
            case let .FormattedDate(_, date): a.link = "tg://timestamp?t=\(date)"
            case .CustomEmoji: a.emoji = entityEmoji
            default: break
            }
            unitAttrs[i] = a
        }
    }

    var blocks: [Block] = []
    var runs: [TextRun] = []
    func flushParagraph() {
        blocks.append(.paragraph(ParagraphBlock(id: BlockID.generate(), runs: runs)))
        runs = []
    }

    var i = 0
    while i < length {
        if nsText.character(at: i) == 10 { // "\n"
            flushParagraph()
            i += 1
            continue
        }
        // Extend a run while the attribute span is constant and there is no newline. Grouping by whole
        // spans (rather than per unit) keeps surrogate pairs / composed emoji intact.
        let startAttr = unitAttrs[i]
        var j = i + 1
        while j < length, nsText.character(at: j) != 10, unitAttrs[j] == startAttr {
            j += 1
        }
        if startAttr.emoji != nil {
            // A custom-emoji span collapses to the editor's one-U+FFFC atom (the alt text lives in the ref).
            runs.append(TextRun(text: "\u{FFFC}", attributes: startAttr))
        } else {
            runs.append(TextRun(text: nsText.substring(with: NSRange(location: i, length: j - i)), attributes: startAttr))
        }
        i = j
    }
    flushParagraph()
    return blocks
}

/// Build an editor `Document` directly from an `InstantPage` (used to reopen the rich-text draft preview
/// back into the editor). Media/table reconstruction follows `documentBlocks(from:)`.
public func richTextDocument(from instantPage: InstantPage) -> Document {
    let blocks = documentBlocks(from: instantPage)
    return Document(blocks: blocks.isEmpty ? [.paragraph(ParagraphBlock(id: BlockID.generate()))] : blocks)
}

// MARK: - Reverse: InstantPage → editor Document (for editing a rich message)

/// Flatten an inline `RichText` tree into editor `TextRun`s, accumulating styling as it descends.
private func runs(from richText: RichText, _ attrs: CharacterAttributes = .plain) -> [TextRun] {
    switch richText {
    case .empty:
        return []
    case let .plain(s):
        return s.isEmpty ? [] : [TextRun(text: s, attributes: attrs)]
    case let .bold(t): var a = attrs; a.bold = true; return runs(from: t, a)
    case let .italic(t): var a = attrs; a.italic = true; return runs(from: t, a)
    case let .underline(t): var a = attrs; a.underline = true; return runs(from: t, a)
    case let .strikethrough(t): var a = attrs; a.strikethrough = true; return runs(from: t, a)
    case let .fixed(t): var a = attrs; a.inlineCode = true; return runs(from: t, a)
    case let .marked(t): return runs(from: t, attrs)
    case let .url(t, url, _): var a = attrs; a.link = url; return runs(from: t, a)
    case let .email(t, _): return runs(from: t, attrs)
    case let .phone(t, _): return runs(from: t, attrs)
    case let .anchor(t, _): return runs(from: t, attrs)
    case let .`subscript`(t): return runs(from: t, attrs)
    case let .superscript(t): return runs(from: t, attrs)
    case let .concat(parts): return parts.flatMap { runs(from: $0, attrs) }
    case let .formula(latex): var a = attrs; a.formula = latex; return [TextRun(text: "\u{FFFC}", attributes: a)]
    case let .textCustomEmoji(fileId, alt):
        var a = attrs
        a.emoji = EmojiRef(id: "\(fileId)", instanceID: BlockID.generate().rawValue, altText: alt.isEmpty ? nil : alt)
        return [TextRun(text: "\u{FFFC}", attributes: a)]
    case let .textSpoiler(t): var a = attrs; a.spoiler = true; return runs(from: t, a)
    case let .textMentionName(t, peerId): var a = attrs; a.link = "tg://user?id=\(peerId)"; return runs(from: t, a)
    case let .textMention(t): return runs(from: t, attrs)
    case let .textAutoEmail(t): return runs(from: t, attrs)
    case let .textAutoPhone(t): return runs(from: t, attrs)
    case let .textAutoUrl(t): return runs(from: t, attrs)
    case let .textBankCard(t): return runs(from: t, attrs)
    case let .textTonAddress(t): return runs(from: t, attrs)
    case let .textBotCommand(t): return runs(from: t, attrs)
    case let .textCashtag(t): return runs(from: t, attrs)
    case let .textHashtag(t): return runs(from: t, attrs)
    case let .textDate(t, date, _): var a = attrs; a.link = "tg://timestamp?t=\(date)"; return runs(from: t, a)
    case .image:
        return []
    case let .textButton(button):
        // The label recursion starts from `.plain`, not the ambient attrs: outer formatting belongs to
        // the carrying run, the label is self-contained.
        var a = attrs
        a.button = ButtonRef(label: runs(from: button.text),
                             action: buttonAction(from: button.action),
                             color: buttonColor(from: button.color),
                             isLink: button.isLink)
        return [TextRun(text: "\u{FFFC}", attributes: a)]
    @unknown default:
        let plain = richText.plainText
        return plain.isEmpty ? [] : [TextRun(text: plain, attributes: attrs)]
    }
}

/// Reconstruct the text-bearing structure of an `InstantPage` as editor blocks (paragraphs, headings,
/// quotes, lists). Media/table blocks are skipped (no host media cache here); their text is not seeded.
private func coreBlocks(from singleBlock: InstantPageBlock) -> [Block] {
    var result: [Block] = []

    func emit(_ rt: RichText, style: ParagraphStyleName, list: ListMembership? = nil) {
        result.append(.paragraph(ParagraphBlock(id: BlockID.generate(), style: style, list: list, runs: runs(from: rt))))
    }

    func emitList(_ items: [InstantPageListItem], ordered: Bool, level: Int) {
        // The marker is per-ITEM: a non-nil `checked` flag denotes a checklist item (restoring its
        // checkbox), otherwise the list's ordered/bullet kind applies.
        func membership(checked: Bool?) -> ListMembership {
            if let checked = checked {
                return ListMembership(marker: .checklist, level: level, checked: checked)
            }
            return ListMembership(marker: ordered ? .ordered : .bullet, level: level)
        }
        for item in items {
            switch item {
            case let .text(rt, _, checked):
                emit(rt, style: .body, list: membership(checked: checked))
            case let .blocks(blocks, _, checked):
                for b in blocks {
                    if case let .list(subItems, subOrdered) = b {
                        emitList(subItems, ordered: subOrdered, level: level + 1)
                    } else if case let .paragraph(t) = b {
                        emit(t, style: .body, list: membership(checked: checked))
                    } else {
                        handle(b)
                    }
                }
            case .unknown:
                break
            }
        }
    }

    func handle(_ block: InstantPageBlock) {
        switch block {
        case let .paragraph(text):
            emit(text, style: .body)
        case let .heading(text, level):
            let styles: [ParagraphStyleName] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]
            emit(text, style: styles[min(max(Int(level), 1), 6) - 1])
        case let .blockQuote(blocks, _, collapsed):
            var children: [Block] = []
            for b in blocks { children.append(contentsOf: coreBlocks(from: b)) }
            result.append(.blockQuote(BlockQuote(id: BlockID.generate(), children: children, collapsed: collapsed ?? false)))
        case let .pullQuote(text, caption):
            result.append(.pullQuote(PullQuote(id: BlockID.generate(), runs: runs(from: text),
                                               author: pullQuoteAuthorRuns(fromCaption: caption))))
        case let .list(items, ordered):
            emitList(items, ordered: ordered, level: 0)
        case let .table(title, rows, bordered, _, compact):
            // Reconstruct a real editor table so it round-trips back into the editor (reopen / inline edit).
            // The title (if any) becomes a preceding heading — the editor's table model has no title field.
            if !title.plainText.isEmpty {
                emit(title, style: .heading3)
            }
            let columnCount = rows.map { $0.cells.count }.max() ?? 0
            let columns = (0 ..< columnCount).map { _ in ColumnSpec(width: 120) }
            let coreRows = rows.map { row -> Row in
                let cells = row.cells.map { cell -> Cell in
                    let cellRuns = cell.text.map { runs(from: $0) } ?? []
                    // Alignment is per-cell in the editor model now; carry the InstantPage cell's own h/v alignment.
                    let h: TextAlignment
                    switch cell.alignment {
                    case .left: h = .left
                    case .center: h = .center
                    case .right: h = .right
                    @unknown default: h = .left
                    }
                    let v: VerticalAlignment
                    switch cell.verticalAlignment {
                    case .top: v = .top
                    case .middle: v = .middle
                    case .bottom: v = .bottom
                    @unknown default: v = .top
                    }
                    return Cell(id: BlockID.generate(), blocks: [.paragraph(ParagraphBlock(id: BlockID.generate(), runs: cellRuns))],
                                horizontalAlignment: h, verticalAlignment: v)
                }
                return Row(id: BlockID.generate(), isHeader: row.cells.first?.header ?? false, cells: cells)
            }
            result.append(.table(TableBlock(id: BlockID.generate(), columns: columns, rows: coreRows, compact: compact, bordered: bordered)))
        case let .title(text):
            emit(text, style: .heading1)
        case let .subheader(text):
            emit(text, style: .heading2)
        case let .kicker(text):
            emit(text, style: .heading3)
        case let .footer(text):
            emit(text, style: .body)
        case let .preformatted(text, language):
            result.append(.code(CodeBlock(id: BlockID.generate(), language: language, runs: runs(from: text))))
        case let .buttonRow(alignment, buttons):
            result.append(.buttonRow(ButtonRowBlock(
                id: BlockID.generate(),
                buttons: buttons.map {
                    ButtonRef(label: runs(from: $0.text),
                              action: buttonAction(from: $0.action),
                              color: buttonColor(from: $0.color),
                              isLink: $0.isLink)
                },
                alignment: buttonRowAlignment(from: alignment)
            )))
        default:
            break
        }
    }

    handle(singleBlock)
    return result
}

private func documentBlocks(from page: InstantPage) -> [Block] {
    return page.blocks.flatMap { coreBlocks(from: $0) }
}

/// Media-preserving reverse of `composeRichMessage`: an `InstantPage` → editor send-blocks plus the
/// resolved media keyed by a fresh `mediaID` (used to reopen a rich draft WITH its media). Block order /
// MARK: - Content validation (reject structurally-present but empty content before sending)

/// True when the editor's outgoing blocks carry something actually sendable — non-blank text / code /
/// formula / emoji, real media, or a non-empty media group / table. Structurally-present but empty content
/// (an empty table, blank paragraphs, an empty code block) is NOT sendable, so the send paths reject it.
public func richTextOutgoingHasContent(_ blocks: [RichTextOutgoingBlock]) -> Bool {
    for block in blocks {
        switch block {
        case let .paragraph(p):
            if richTextRunsHaveContent(p.runs) { return true }
        case let .code(c):
            if richTextRunsHaveContent(c.runs) { return true }
        case let .table(t):
            if t.rows.contains(where: { $0.cells.contains(where: { $0.blocks.contains(where: richTextCoreBlockHasContent) }) }) { return true }
        case .media:
            return true
        case let .mediaGroup(_, mediaIDs, _, _):
            if !mediaIDs.isEmpty { return true }
        case let .pullQuote(pq):
            if richTextRunsHaveContent(pq.runs) { return true }
        case let .blockQuote(children, _):
            if richTextOutgoingHasContent(children) { return true }
        case let .buttonRow(row):
            if row.buttons.contains(where: { !richTextButtonIsBlankPlaceholder($0) }) { return true }
        }
    }
    return false
}

/// A pill still in its authoring-placeholder state: no label AND a blank `.url` action — exactly what
/// `insertButtonRow`/`addButtonToRow` seed before the property sheet fills it. Such a pill is dropped
/// on send and does not count as message content.
private func richTextButtonIsBlankPlaceholder(_ button: ButtonRef) -> Bool {
    guard case let .url(url) = button.action else { return false }
    return button.labelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func richTextRunsHaveContent(_ runs: [TextRun]) -> Bool {
    return runs.contains { run in
        if let formula = run.attributes.formula, !formula.isEmpty { return true }
        if run.attributes.emoji != nil { return true }
        return !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private func richTextCoreBlockHasContent(_ block: Block) -> Bool {
    switch block {
    case let .paragraph(p): return richTextRunsHaveContent(p.runs)
    case let .code(c): return richTextRunsHaveContent(c.runs)
    case let .table(t): return t.rows.contains { $0.cells.contains { $0.blocks.contains(where: richTextCoreBlockHasContent) } }
    case .media: return true
    case let .pullQuote(pq): return richTextRunsHaveContent(pq.runs)
    case let .blockQuote(bq): return bq.children.contains(where: richTextCoreBlockHasContent)
    case let .details(d): return richTextRunsHaveContent(d.title) || d.children.contains(where: richTextCoreBlockHasContent)
    case let .buttonRow(row): return row.buttons.contains { !richTextButtonIsBlankPlaceholder($0) }
    }
}

/// interleaving is preserved so text→photo→text round-trips. Maps reconstruct a `TelegramMediaMap` from
/// their coordinates; collages/slideshows become a media group.
public func richTextOutgoing(from page: InstantPage) -> (blocks: [RichTextOutgoingBlock], media: [String: Media]) {
    var out: [RichTextOutgoingBlock] = []
    var mediaMap: [String: Media] = [:]
    var counter = 0
    func key() -> String { counter += 1; return "reopen-\(counter)" }

    func coreToOutgoing(_ block: Block) -> RichTextOutgoingBlock? {
        return RichTextOutgoingBlock(core: block)
    }
    func emitMedia(kind: String, id: MediaId, caption: InstantPageCaption, spoiler: Bool) {
        guard let media = page.media[id]?._asMedia() else { return }
        let k = key(); mediaMap[k] = media
        out.append(.media(kind: kind, mediaID: k, caption: runs(from: caption.text), spoiler: spoiler))
    }
    func groupIDs(_ items: [InstantPageBlock]) -> (ids: [String], spoilers: [Bool]) {
        var ids: [String] = []
        var spoilers: [Bool] = []
        for item in items {
            let mediaId: MediaId?
            let spoiler: Bool
            switch item {
            case let .image(id, _, _, _, sp): mediaId = id; spoiler = sp
            case let .video(id, _, _, _, sp): mediaId = id; spoiler = sp
            default: mediaId = nil; spoiler = false
            }
            if let mediaId = mediaId, let media = page.media[mediaId]?._asMedia() {
                let k = key(); mediaMap[k] = media; ids.append(k); spoilers.append(spoiler)
            }
        }
        return (ids, spoilers)
    }

    for block in page.blocks {
        switch block {
        case let .image(id, caption, _, _, spoiler):
            emitMedia(kind: "image", id: id, caption: caption, spoiler: spoiler)
        case let .video(id, caption, _, _, spoiler):
            emitMedia(kind: "video", id: id, caption: caption, spoiler: spoiler)
        case let .audio(id, caption):
            emitMedia(kind: "audio", id: id, caption: caption, spoiler: false)
        case let .document(id, caption):
            emitMedia(kind: "file", id: id, caption: caption, spoiler: false)
        case let .map(latitude, longitude, _, _, caption):
            let map = TelegramMediaMap(latitude: latitude, longitude: longitude, heading: nil, accuracyRadius: nil, venue: nil, liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil)
            let k = key(); mediaMap[k] = map
            out.append(.media(kind: "map", mediaID: k, caption: runs(from: caption.text), spoiler: false))
        case let .collage(items, caption):
            let g = groupIDs(items)
            if !g.ids.isEmpty { out.append(.mediaGroup(kind: "collage", mediaIDs: g.ids, caption: runs(from: caption.text), spoilers: g.spoilers)) }
        case let .slideshow(items, caption):
            let g = groupIDs(items)
            if !g.ids.isEmpty { out.append(.mediaGroup(kind: "slideshow", mediaIDs: g.ids, caption: runs(from: caption.text), spoilers: g.spoilers)) }
        default:
            out.append(contentsOf: coreBlocks(from: block).compactMap(coreToOutgoing))
        }
    }
    return (out, mediaMap)
}

/// Serialize the editor's `outgoingBlocks()` + media cache into a `ComposedRichMessage`.
public func composeRichMessage(from blocks: [RichTextOutgoingBlock], media: [String: Media]) -> ComposedRichMessage {
    let normalized = trimmedTrailingEmpty(normalizedBlocks(blocks, media: media))
    if normalized.isEmpty {
        return .empty
    }
    if documentNeedsRichLayout(normalized) {
        return .rich(instantPage: buildInstantPage(from: normalized, media: media))
    } else {
        let message = buildEntityMessage(from: normalized)
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .empty
        }
        return .plain(text: message.text, entities: message.entities)
    }
}

/// Serialize the editor's content into an `InstantPage` unconditionally (the AI-compose request format),
/// even when the content is entity-expressible. nil when there is no sendable content.
public func richTextInstantPage(from blocks: [RichTextOutgoingBlock], media: [String: Media]) -> InstantPage? {
    let normalized = trimmedTrailingEmpty(normalizedBlocks(blocks, media: media))
    guard !normalized.isEmpty else { return nil }
    return buildInstantPage(from: normalized, media: media)
}

/// An editor selection fragment (Core `[Block]`) → the outgoing currency (media never appears in a
/// selection fragment). The inverse of `coreBlocks(fromOutgoing:)`.
public func outgoingBlocks(fromSelection blocks: [Block]) -> [RichTextOutgoingBlock] {
    return blocks.compactMap { RichTextOutgoingBlock(core: $0) }
}

/// Outgoing blocks (e.g. an AI-composed result round-tripped from an `InstantPage`) → a Core `[Block]`
/// fragment the editor can splice over a selection. Media/groups are dropped — a selection transform
/// operates on text/structure only.
public func coreBlocks(fromOutgoing blocks: [RichTextOutgoingBlock]) -> [Block] {
    return blocks.compactMap { block -> Block? in
        switch block {
        case .paragraph, .table, .code, .pullQuote, .blockQuote, .buttonRow:
            return block.coreBlock
        case let .media(_, _, caption, _):
            return caption.isEmpty ? nil : .paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: caption))
        case let .mediaGroup(_, _, caption, _):
            return caption.isEmpty ? nil : .paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: caption))
        }
    }
}

/// Best-effort plain preview of an `InstantPage`: real text+entities when the content is
/// entity-expressible, otherwise a flattened text rendering (headings/lists as lines, tables as
/// tab-separated rows, code as a `pre` entity). Used by the AI editor modal to show rich content in
/// its text-based preview.
public func richTextPlainPreview(from page: InstantPage) -> (text: String, entities: [MessageTextEntity]) {
    let (blocks, media) = richTextOutgoing(from: page)
    switch composeRichMessage(from: blocks, media: media) {
    case let .plain(text, entities):
        return (text, entities)
    case .rich, .empty:
        var lines: [String] = []
        var entities: [MessageTextEntity] = []
        var offset = 0
        func append(_ line: String, pre: Bool = false) {
            if pre {
                entities.append(MessageTextEntity(range: offset ..< offset + (line as NSString).length, type: .Pre(language: nil)))
            }
            lines.append(line)
            offset += (line as NSString).length + 1
        }
        func flatten(_ blocks: [RichTextOutgoingBlock]) {
        for block in blocks {
            switch block {
            case let .paragraph(p):
                append(p.runs.map(\.text).joined())
            case let .pullQuote(pq):
                append(pq.text)
            case let .blockQuote(children, _):
                flatten(children)
            case let .code(c):
                append(c.text, pre: true)
            case let .table(t):
                for row in t.rows {
                    append(row.cells.map { cell in
                        cell.blocks.compactMap { inner -> String? in
                            if case let .paragraph(p) = inner { return p.runs.map(\.text).joined() }
                            return nil
                        }.joined(separator: " ")
                    }.joined(separator: "\t"))
                }
            case let .media(_, _, caption, _):
                if !caption.isEmpty { append(caption.map(\.text).joined()) }
            case let .mediaGroup(_, _, caption, _):
                if !caption.isEmpty { append(caption.map(\.text).joined()) }
            case let .buttonRow(row):
                append(row.buttons.map(\.labelText).joined(separator: " "))
            }
        }
        }
        flatten(blocks)
        return (lines.joined(separator: "\n"), entities)
    }
}

// MARK: - Normalization

private let renderableMediaKinds: Set<String> = ["image", "video", "audio", "file", "map"]

/// Pass paragraphs / tables / code through. Keep media whose kind has an InstantPage representation and
/// whose `mediaID`(s) resolve; otherwise fall back to the media's caption as a body paragraph so an
/// unresolvable attachment contributes its caption text rather than vanishing.
private func normalizedBlocks(_ blocks: [RichTextOutgoingBlock], media: [String: Media]) -> [RichTextOutgoingBlock] {
    var out: [RichTextOutgoingBlock] = []
    for block in blocks {
        switch block {
        case .paragraph, .table, .code, .pullQuote, .blockQuote, .buttonRow:
            out.append(block)
        case let .media(kind, mediaID, caption, _):
            if renderableMediaKinds.contains(kind), media[mediaID] != nil {
                out.append(block)
            } else if !caption.isEmpty {
                out.append(.paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: caption)))
            }
        case let .mediaGroup(kind, mediaIDs, caption, spoilers):
            let keep = mediaIDs.indices.filter { media[mediaIDs[$0]] != nil }
            if !keep.isEmpty {
                out.append(.mediaGroup(kind: kind, mediaIDs: keep.map { mediaIDs[$0] }, caption: caption,
                                       spoilers: keep.map { $0 < spoilers.count ? spoilers[$0] : false }))
            } else if !caption.isEmpty {
                out.append(.paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: caption)))
            }
        }
    }
    return out
}

/// Trim trailing empty body/quote paragraphs (e.g. the editor's blank end paragraph).
private func trimmedTrailingEmpty(_ blocks: [RichTextOutgoingBlock]) -> [RichTextOutgoingBlock] {
    var result = blocks
    while let last = result.last,
          case let .paragraph(paragraph) = last,
          paragraph.list == nil,
          paragraph.style == .body,
          paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.removeLast()
    }
    return result
}

private func richTextRunsContainButton(_ runs: [TextRun]) -> Bool {
    return runs.contains { $0.attributes.button != nil }
}

/// True when the content needs the rich (InstantPage) path: any table, media/group, heading, list,
/// formula, or button.
private func documentNeedsRichLayout(_ blocks: [RichTextOutgoingBlock]) -> Bool {
    for block in blocks {
        switch block {
        case .table, .media, .mediaGroup:
            return true
        case .buttonRow:
            return true
        case let .paragraph(paragraph):
            if paragraph.list != nil {
                return true
            }
            if paragraph.runs.contains(where: { $0.attributes.formula != nil }) {
                return true   // formulas have no message-entity; they must travel in an InstantPage
            }
            if richTextRunsContainButton(paragraph.runs) {
                return true   // buttons have no message-entity either
            }
            switch paragraph.style {
            case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
                return true
            case .body, .caption:
                break
            case .pullQuote:
                return true   // pull quotes have no message-entity; they must travel in an InstantPage
            }
        case .pullQuote:
            return true
        case let .blockQuote(children, _):
            // A SIMPLE quote — plain body-paragraph children only (no lists/headings/formulas/nesting) —
            // stays entity-expressible (.BlockQuote); anything structural forces the rich path.
            for child in children {
                guard case let .paragraph(p) = child, p.list == nil else { return true }
                if p.runs.contains(where: { $0.attributes.formula != nil }) { return true }
                if richTextRunsContainButton(p.runs) { return true }
                switch p.style {
                case .body, .caption: break
                default: return true
                }
            }
        case let .code(code):
            if richTextRunsContainButton(code.runs) { return true }
        }
    }
    return false
}

// MARK: - Inline run → RichText

/// Map a single text run to inline `RichText`, applying its character attributes as nested wrappers.
private func richText(from run: TextRun) -> RichText? {
    let attributes = run.attributes
    // FIRST: a button run's text is a bare U+FFFC, so any later arm would emit an invisible
    // placeholder in place of the pill. Falls through to the wrapper chain so ambient formatting
    // around the atom (e.g. a bold(textButton)) survives the round-trip, matching iOS.
    if let button = attributes.button {
        // A never-configured inline pill (a `.url` action left blank) flattens back to its label text
        // rather than sending a labeled dead button — a URL button without a URL is not sendable.
        if case let .url(url) = button.action, url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let label = button.labelText
            if label.isEmpty { return nil }
            var flattened: RichText = .plain(label)
            if attributes.inlineCode { flattened = .fixed(flattened) }
            if attributes.strikethrough { flattened = .strikethrough(flattened) }
            if attributes.underline { flattened = .underline(flattened) }
            if attributes.italic { flattened = .italic(flattened) }
            if attributes.bold { flattened = .bold(flattened) }
            if attributes.spoiler { flattened = .textSpoiler(text: flattened) }
            return flattened
        }
        var result: RichText = .textButton(InstantPageButton(
            text: richText(from: button.label),
            action: replyMarkupButtonAction(from: button.action),
            color: replyMarkupColor(from: button.color),
            isLink: button.isLink
        ))
        if attributes.inlineCode { result = .fixed(result) }
        if attributes.strikethrough { result = .strikethrough(result) }
        if attributes.underline { result = .underline(result) }
        if attributes.italic { result = .italic(result) }
        if attributes.bold { result = .bold(result) }
        if attributes.highlight != nil { result = .marked(result) }
        if let link = attributes.link { result = chatRichTextEditorLink(link).richText(result) }
        if attributes.spoiler { result = .textSpoiler(text: result) }
        return result
    }
    if let latex = attributes.formula, !latex.isEmpty {
        return .formula(latex: latex)   // the only transport for a formula (no message-entity exists)
    }
    if let emoji = attributes.emoji {
        let alt = emoji.altText ?? ""
        if let fileId = Int64(emoji.id) {
            return .textCustomEmoji(fileId: fileId, alt: alt)
        }
        return alt.isEmpty ? nil : .plain(alt)
    }
    if run.text.isEmpty {
        return nil
    }
    var result: RichText = .plain(run.text)
    if attributes.inlineCode { result = .fixed(result) }
    if attributes.strikethrough { result = .strikethrough(result) }
    if attributes.underline { result = .underline(result) }
    if attributes.italic { result = .italic(result) }
    if attributes.bold { result = .bold(result) }
    if attributes.highlight != nil { result = .marked(result) }
    if let link = attributes.link { result = chatRichTextEditorLink(link).richText(result) }
    if attributes.spoiler { result = .textSpoiler(text: result) }
    return result
}

private func richText(from runs: [TextRun]) -> RichText {
    let parts = runs.compactMap(richText(from:))
    if parts.isEmpty { return .empty }
    if parts.count == 1 { return parts[0] }
    return .concat(parts)
}

private func instantCaption(_ runs: [TextRun]) -> InstantPageCaption {
    return InstantPageCaption(text: richText(from: runs), credit: .empty)
}

/// A pull quote's attribution ("author") line, transported as the InstantPage pull-quote CAPTION with the
/// ambient bold+italic baked in (mirrors the shared `authorCaptionRichText`), so InstantPage V2 renders it
/// like the editor's author line. Empty author → `.empty` (the renderer draws no caption).
private func pullQuoteAuthorCaption(_ author: [TextRun]) -> RichText {
    richText(from: author.map { var r = $0; r.attributes.bold = true; r.attributes.italic = true; return r })
}

/// Strip the baked-in bold+italic from a decoded pull-quote caption so the model's `author` runs are clean
/// (the ambient styling is re-applied on render / send, never persisted).
private func pullQuoteAuthorRuns(fromCaption caption: RichText) -> [TextRun] {
    runs(from: caption).map { var r = $0; r.attributes.bold = false; r.attributes.italic = false; return r }
}

// MARK: - Rich path: outgoing blocks → InstantPage

private func buildInstantPage(from blocks: [RichTextOutgoingBlock], media: [String: Media]) -> InstantPage {
    var pageMedia: [MediaId: Media] = [:]
    let pageBlocks = buildPageBlocks(from: blocks, media: media, pageMedia: &pageMedia)
    return InstantPage(blocks: pageBlocks, media: pageMedia.mapValues(EngineMedia.init), isComplete: true, rtl: false, url: "", views: nil)
}

private func buildPageBlocks(from blocks: [RichTextOutgoingBlock], media: [String: Media], pageMedia: inout [MediaId: Media]) -> [InstantPageBlock] {
    var pageBlocks: [InstantPageBlock] = []
    var index = 0
    while index < blocks.count {
        switch blocks[index] {
        case let .paragraph(paragraph):
            if paragraph.list != nil {
                var run: [ParagraphBlock] = []
                while index < blocks.count, case let .paragraph(next) = blocks[index], next.list != nil {
                    run.append(next)
                    index += 1
                }
                pageBlocks.append(contentsOf: buildListBlocks(from: run[...]))
                continue
            } else {
                pageBlocks.append(headingOrParagraphBlock(paragraph))
                index += 1
            }
        case let .table(table):
            pageBlocks.append(tableBlock(table))
            index += 1
        case let .code(code):
            pageBlocks.append(.preformatted(text: richText(from: code.runs), language: code.language))
            index += 1
        case let .pullQuote(pq):
            pageBlocks.append(.pullQuote(text: richText(from: pq.runs), caption: pullQuoteAuthorCaption(pq.author)))
            index += 1
        case let .blockQuote(children, collapsed):
            // Recursive: the wire format nests directly.
            let inner = buildPageBlocks(from: children, media: media, pageMedia: &pageMedia)
            pageBlocks.append(.blockQuote(blocks: inner, caption: .empty, collapsed: collapsed))
            index += 1
        case let .buttonRow(row):
            // A never-configured authoring placeholder (blank label + blank URL — what insertButtonRow
            // seeds before the property sheet fills it) is dropped rather than sent as a dead pill.
            let configured = row.buttons.filter { !richTextButtonIsBlankPlaceholder($0) }
            if !configured.isEmpty {
                pageBlocks.append(.buttonRow(
                    alignment: instantPageRowAlignment(from: row.alignment),
                    buttons: configured.map {
                        InstantPageButton(text: richText(from: $0.label),
                                          action: replyMarkupButtonAction(from: $0.action),
                                          color: replyMarkupColor(from: $0.color),
                                          isLink: $0.isLink)
                    }
                ))
            }
            index += 1
        case let .media(kind, mediaID, caption, spoiler):
            if let block = singleMediaBlock(kind: kind, media: media[mediaID], caption: instantCaption(caption), spoiler: spoiler, pageMedia: &pageMedia) {
                pageBlocks.append(block)
            }
            index += 1
        case let .mediaGroup(kind, mediaIDs, caption, spoilers):
            let items = mediaIDs.enumerated().compactMap { i, mid in
                groupItemBlock(media: media[mid], spoiler: i < spoilers.count ? spoilers[i] : false, pageMedia: &pageMedia)
            }
            if !items.isEmpty {
                let cap = instantCaption(caption)
                pageBlocks.append(kind == "slideshow" ? .slideshow(items: items, caption: cap) : .collage(items: items, caption: cap))
            }
            index += 1
        }
    }
    return pageBlocks
}

/// A single media block → its InstantPage block, registering the media by id (except `.map`, which embeds
/// its coordinates). Anything unrenderable returns nil; its caption was kept by `normalizedBlocks`.
private func singleMediaBlock(kind: String, media: Media?, caption: InstantPageCaption, spoiler: Bool, pageMedia: inout [MediaId: Media]) -> InstantPageBlock? {
    guard let media = media else { return nil }
    switch kind {
    case "image":
        guard let id = media.id else { return nil }
        pageMedia[id] = media
        return .image(id: id, caption: caption, url: nil, webpageId: nil, spoiler: spoiler)
    case "video":
        guard let id = media.id else { return nil }
        pageMedia[id] = media
        return .video(id: id, caption: caption, autoplay: false, loop: false, spoiler: spoiler)
    case "audio":
        guard let id = media.id else { return nil }
        pageMedia[id] = media
        return .audio(id: id, caption: caption)
    case "file":
        guard let file = media as? TelegramMediaFile, let id = file.id else { return nil }
        pageMedia[id] = file
        return .document(id: id, caption: caption)
    case "map":
        if let map = media as? TelegramMediaMap {
            return .map(latitude: map.latitude, longitude: map.longitude, zoom: 15,
                        dimensions: PixelDimensions(width: 640, height: 320), caption: caption)
        }
        return nil
    default:
        return nil
    }
}

/// One collage/slideshow item → an image or video block (chosen by the resolved media's type), registered by id.
private func groupItemBlock(media: Media?, spoiler: Bool, pageMedia: inout [MediaId: Media]) -> InstantPageBlock? {
    guard let media = media, let id = media.id else { return nil }
    pageMedia[id] = media
    let caption = InstantPageCaption(text: .empty, credit: .empty)
    if let file = media as? TelegramMediaFile, file.isVideo {
        return .video(id: id, caption: caption, autoplay: false, loop: false, spoiler: spoiler)
    }
    return .image(id: id, caption: caption, url: nil, webpageId: nil, spoiler: spoiler)
}

/// A non-list, non-quote paragraph → a heading or a paragraph block.
private func headingOrParagraphBlock(_ paragraph: ParagraphBlock) -> InstantPageBlock {
    let text = richText(from: paragraph.runs)
    switch paragraph.style {
    case .heading1: return .heading(text: text, level: 1)
    case .heading2: return .heading(text: text, level: 2)
    case .heading3: return .heading(text: text, level: 3)
    case .heading4: return .heading(text: text, level: 4)
    case .heading5: return .heading(text: text, level: 5)
    case .heading6: return .heading(text: text, level: 6)
    case .body, .caption: return .paragraph(text)
    case .pullQuote: return .pullQuote(text: text, caption: .empty)
    }
}

/// Recursively build `.list` blocks from a consecutive run of list paragraphs.
private func buildListBlocks(from paragraphs: ArraySlice<ParagraphBlock>) -> [InstantPageBlock] {
    var result: [InstantPageBlock] = []
    var index = paragraphs.startIndex
    while index < paragraphs.endIndex {
        let baseLevel = paragraphs[index].list?.level ?? 0
        let baseMarker = paragraphs[index].list?.marker ?? .bullet
        var items: [InstantPageListItem] = []
        while index < paragraphs.endIndex,
              (paragraphs[index].list?.level ?? 0) == baseLevel,
              (paragraphs[index].list?.marker ?? .bullet) == baseMarker {
            let text = richText(from: paragraphs[index].runs)
            // A checklist item carries its checked state so the InstantPage renders a checkbox (not a
            // bullet); bullet/ordered items leave it nil. The InstantPageListItem's third field IS that flag.
            let checked: Bool? = baseMarker == .checklist ? (paragraphs[index].list?.checked ?? false) : nil
            index += 1
            let childStart = index
            while index < paragraphs.endIndex, (paragraphs[index].list?.level ?? 0) > baseLevel {
                index += 1
            }
            if index > childStart {
                let nested = buildListBlocks(from: paragraphs[childStart ..< index])
                items.append(.blocks([.paragraph(text)] + nested, nil, checked))
            } else {
                items.append(.text(text, nil, checked))
            }
        }
        result.append(.list(items: items, ordered: baseMarker == .ordered))
    }
    return result
}

/// A table block → `.table`, mapping per-cell alignment and the header row.
private func tableBlock(_ table: TableBlock) -> InstantPageBlock {
    let rows = table.rows.map { row -> InstantPageTableRow in
        let cells = row.cells.map { cell -> InstantPageTableCell in
            let alignment: TableHorizontalAlignment
            switch cell.horizontalAlignment {
            case .left, .justified, .natural: alignment = .left
            case .center: alignment = .center
            case .right: alignment = .right
            }
            let vAlignment: TableVerticalAlignment
            switch cell.verticalAlignment {
            case .top: vAlignment = .top
            case .middle: vAlignment = .middle
            case .bottom: vAlignment = .bottom
            }
            return InstantPageTableCell(text: cellRichText(cell), header: row.isHeader, alignment: alignment,
                                        verticalAlignment: vAlignment, colspan: 1, rowspan: 1)
        }
        return InstantPageTableRow(cells: cells)
    }
    return .table(title: .empty, rows: rows, bordered: table.bordered, striped: false, compact: table.compact)
}

private func cellRichText(_ cell: Cell) -> RichText {
    let paragraphs = cell.blocks.compactMap { block -> RichText? in
        if case let .paragraph(paragraph) = block { return richText(from: paragraph.runs) }
        return nil
    }
    if paragraphs.isEmpty { return .empty }
    if paragraphs.count == 1 { return paragraphs[0] }
    var joined: [RichText] = []
    for (offset, text) in paragraphs.enumerated() {
        if offset > 0 { joined.append(.plain("\n")) }
        joined.append(text)
    }
    return .concat(joined)
}

// MARK: - Plain path: outgoing blocks → (text, entities) via the macOS-native ChatTextInputState

/// Build a normal message (text + entities) from entity-expressible blocks (body/quote paragraphs + code).
/// Reached only when there's no table / media / heading / list / formula (those route to the rich path).
/// Flatten the editor's blocks to plain text + entities (used to hand content back to the chat composer
/// when the editor is dismissed without sending). Structure beyond inline formatting is not preserved.
public func richTextPlain(from blocks: [RichTextOutgoingBlock]) -> (text: String, entities: [MessageTextEntity]) {
    return buildEntityMessage(from: blocks)
}

private func buildEntityMessage(from blocks: [RichTextOutgoingBlock]) -> (text: String, entities: [MessageTextEntity]) {
    let text = NSMutableString()
    var attributes: [ChatTextInputAttribute] = []
    var isFirst = true

    func appendRuns(_ runs: [TextRun]) {
        for run in runs {
            let attrs = run.attributes
            if attrs.formula != nil { continue }   // formulas force the rich path; never leak the U+FFFC atom
            if attrs.button != nil { continue }    // buttons likewise (unreachable — the rich path takes them)
            if let emoji = attrs.emoji {
                guard let alt = emoji.altText, !alt.isEmpty else { continue }
                let start = text.length
                text.append(alt)
                if let fileId = Int64(emoji.id) {
                    attributes.append(.animated(start ..< text.length, "\(arc4random())", fileId, nil, nil))
                }
                continue
            }
            if run.text.isEmpty { continue }
            let start = text.length
            text.append(run.text)
            let range = start ..< text.length
            if attrs.bold { attributes.append(.bold(range)) }
            if attrs.italic { attributes.append(.italic(range)) }
            if attrs.inlineCode { attributes.append(.code(range)) }
            if attrs.strikethrough { attributes.append(.strikethrough(range)) }
            if attrs.underline { attributes.append(.underline(range)) }
            if attrs.spoiler { attributes.append(.spoiler(range)) }
            if let link = attrs.link {
                switch chatRichTextEditorLink(link) {
                case let .mention(peerId): attributes.append(.uid(range, peerId.id._internalGetInt64Value()))
                case let .date(date): attributes.append(.date(range, date))
                case let .url(url): attributes.append(.url(range, url))
                }
            }
        }
    }

    for block in blocks {
        switch block {
        case let .paragraph(paragraph):
            if !isFirst { text.append("\n") }
            isFirst = false
            appendRuns(paragraph.runs)
        case let .blockQuote(children, collapsed):
            // Only SIMPLE quotes (plain body-paragraph children — see documentNeedsRichLayout) reach the
            // plain path: children flatten to "\n"-joined lines under one .quote attribute.
            if !isFirst { text.append("\n") }
            isFirst = false
            let start = text.length
            var innerFirst = true
            for child in children {
                guard case let .paragraph(p) = child else { continue }
                if !innerFirst { text.append("\n") }
                innerFirst = false
                appendRuns(p.runs)
            }
            if text.length > start { attributes.append(.quote(start ..< text.length, collapsed)) }
        case let .code(code):
            if !isFirst { text.append("\n") }
            isFirst = false
            let start = text.length
            text.append(code.text)
            if text.length > start { attributes.append(.pre(start ..< text.length, code.language)) }
        case .table, .media, .mediaGroup, .pullQuote, .buttonRow:
            break   // not reached on the plain path
        }
    }

    let state = ChatTextInputState(inputText: text as String, selectionRange: 0 ..< 0, attributes: attributes)
    return (state.inputText, state.messageTextEntities())
}

// MARK: - Rich-message selection → editor Document (copy/paste)

extension NSAttributedString.Key {
    /// Marks a run in a copied rich-message selection as a rendered formula (value: the LaTeX string), so a
    /// paste can reconstruct it as an editor formula run. Formulas have no message-entity, so they can't
    /// survive the plain clipboard.
    public static let richFormulaLatex = NSAttributedString.Key("RichFormulaLatex")
}

/// Private-use sentinel standing in for a formula while the selection is mapped through the chat
/// text↔entity conversion (which can't carry formulas).
private let richFormulaPlaceholder = "\u{E000}"

/// Build an editor `Document` from a rich-message selection's attributed string (carrying inline formatting
/// plus `.richFormulaLatex` marks). Inline formatting (bold/italic/code/links/…) round-trips via the chat
/// text+entities mapping; each formula mark becomes a formula run.
public func documentFromRichSelection(_ attributed: NSAttributedString) -> Document {
    let mutable = NSMutableAttributedString(attributedString: attributed)
    let full = NSRange(location: 0, length: mutable.length)
    var formulaRanges: [(NSRange, String)] = []
    // Standalone formula items mark their run with `.richFormulaLatex`; inline formulas live inside a text
    // item as an attachment char carrying `.instantPageFormulaAttribute` (an `InstantPageMathAttachment`).
    mutable.enumerateAttribute(.richFormulaLatex, in: full, options: []) { value, range, _ in
        if let latex = value as? String, !latex.isEmpty, range.length > 0 { formulaRanges.append((range, latex)) }
    }
    mutable.enumerateAttribute(.instantPageFormulaAttribute, in: full, options: []) { value, range, _ in
        if let attachment = value as? InstantPageMathAttachment, !attachment.latex.isEmpty, range.length > 0,
           !formulaRanges.contains(where: { NSIntersectionRange($0.0, range).length > 0 }) {
            formulaRanges.append((range, attachment.latex))
        }
    }
    let orderedLatex = formulaRanges.sorted { $0.0.location < $1.0.location }.map { $0.1 }
    // Replace each formula range with a single sentinel char, from the end so earlier indices stay valid.
    for (range, _) in formulaRanges.sorted(by: { $0.0.location > $1.0.location }) {
        mutable.replaceCharacters(in: range, with: richFormulaPlaceholder)
    }

    let state = ChatTextInputState(attributedText: mutable, selectionRange: 0 ..< 0)
    let document = richTextDocument(text: state.inputText, entities: state.messageTextEntities())
    guard !orderedLatex.isEmpty else { return document }

    // Re-flow paragraph runs, turning each sentinel char into a formula run (in document order).
    var queue = orderedLatex
    let blocks: [Block] = document.blocks.map { block in
        guard case .paragraph(var paragraph) = block else { return block }
        var newRuns: [TextRun] = []
        for run in paragraph.runs {
            guard run.text.contains(richFormulaPlaceholder) else { newRuns.append(run); continue }
            var buffer = ""
            for ch in run.text {
                if String(ch) == richFormulaPlaceholder {
                    if !buffer.isEmpty { newRuns.append(TextRun(text: buffer, attributes: run.attributes)); buffer = "" }
                    if !queue.isEmpty {
                        var attrs = CharacterAttributes.plain
                        attrs.formula = queue.removeFirst()
                        newRuns.append(TextRun(text: "\u{FFFC}", attributes: attrs))
                    }
                } else {
                    buffer.append(ch)
                }
            }
            if !buffer.isEmpty { newRuns.append(TextRun(text: buffer, attributes: run.attributes)) }
        }
        paragraph.runs = newRuns
        return .paragraph(paragraph)
    }
    return Document(blocks: blocks)
}

// MARK: - AI formula extraction

/// Splits LaTeX spans left as literal delimiter text — `$…$`, `$$…$$`, `\(…\)`, `\[…\]` — into formula
/// atom runs. Applied ONLY to AI-generated content (the server sometimes returns the model's formulas
/// as plain text instead of `RichText.formula`); never to user text, where a `$` is usually money.
public func extractingAIFormulas(_ blocks: [Block]) -> [Block] {
    return blocks.map { block in
        switch block {
        case .paragraph(var p):
            p.runs = extractingFormulaRuns(p.runs)
            return .paragraph(p)
        case .pullQuote(var pq):
            pq.runs = extractingFormulaRuns(pq.runs)
            return .pullQuote(pq)
        case .details(var d):
            d.title = extractingFormulaRuns(d.title)
            d.children = extractingAIFormulas(d.children)
            return .details(d)
        case .blockQuote(var bq):
            bq.children = extractingAIFormulas(bq.children)
            return .blockQuote(bq)
        case .table(var t):
            t.rows = t.rows.map { row in
                var row = row
                row.cells = row.cells.map { cell in
                    var cell = cell
                    cell.blocks = extractingAIFormulas(cell.blocks)
                    return cell
                }
                return row
            }
            return .table(t)
        case .media, .code, .buttonRow:
            return block
        }
    }
}

private func extractingFormulaRuns(_ runs: [TextRun]) -> [TextRun] {
    var out: [TextRun] = []
    for run in runs {
        guard run.attributes.formula == nil, run.attributes.emoji == nil, !run.attributes.inlineCode else {
            out.append(run)
            continue
        }
        let segments = latexSegments(in: run.text)
        guard segments.contains(where: { $0.latex != nil }) else {
            out.append(run)
            continue
        }
        for segment in segments {
            if let latex = segment.latex {
                var a = run.attributes
                a.formula = latex
                out.append(TextRun(text: "\u{FFFC}", attributes: a))
            } else if !segment.text.isEmpty {
                out.append(TextRun(text: segment.text, attributes: run.attributes))
            }
        }
    }
    return out
}

private struct LatexSegment {
    public let text: String
    public let latex: String?
}

private func latexSegments(in text: String) -> [LatexSegment] {
    let chars = Array(text)
    var segments: [LatexSegment] = []
    var plain = ""
    var i = 0

    func flushPlain() {
        if !plain.isEmpty {
            segments.append(LatexSegment(text: plain, latex: nil))
            plain = ""
        }
    }
    func findCloser(_ first: Character, _ second: Character?, from: Int, allowNewlines: Bool) -> Int? {
        var j = from
        let width = second == nil ? 1 : 2
        while j <= chars.count - width {
            if chars[j] == "\\" && first != "\\" { j += 2; continue }
            if !allowNewlines && chars[j] == "\n" { return nil }
            if chars[j] == first, second == nil || (j + 1 < chars.count && chars[j + 1] == second) {
                return j
            }
            j += 1
        }
        return nil
    }
    // A bare `$…$` span is money more often than math — accept it only when the content reads as LaTeX:
    // tight against both delimiters, single-line, and either carrying LaTeX syntax or a short symbol.
    func isInlineLatex(_ content: String) -> Bool {
        guard !content.isEmpty, content.count <= 200 else { return false }
        guard let first = content.first, let last = content.last,
              !first.isWhitespace, !last.isWhitespace else { return false }
        if content.contains(where: { "\\^_{}=".contains($0) }) { return true }
        return content.count <= 3
    }

    while i < chars.count {
        let c = chars[i]
        if c == "\\", i + 1 < chars.count {
            let next = chars[i + 1]
            if next == "[" || next == "(" {
                let isDisplay = next == "["
                if let end = findCloser("\\", isDisplay ? "]" : ")", from: i + 2, allowNewlines: true) {
                    let latex = String(chars[(i + 2)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        flushPlain()
                        segments.append(LatexSegment(text: "", latex: latex))
                        i = end + 2
                        continue
                    }
                }
            } else if next == "$" {
                plain.append("\\$")
                i += 2
                continue
            }
        } else if c == "$" {
            if i + 1 < chars.count, chars[i + 1] == "$" {
                if let end = findCloser("$", "$", from: i + 2, allowNewlines: true) {
                    let latex = String(chars[(i + 2)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        flushPlain()
                        segments.append(LatexSegment(text: "", latex: latex))
                        i = end + 2
                        continue
                    }
                }
            } else if let end = findCloser("$", nil, from: i + 1, allowNewlines: false) {
                let content = String(chars[(i + 1)..<end])
                if isInlineLatex(content) {
                    flushPlain()
                    segments.append(LatexSegment(text: "", latex: content.trimmingCharacters(in: .whitespaces)))
                    i = end + 1
                    continue
                }
            }
        }
        plain.append(c)
        i += 1
    }
    flushPlain()
    return segments
}
