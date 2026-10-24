import Foundation
import TelegramCore

public let markdownTaskListUncheckedNumber = "\u{001f}tg-md-task:unchecked"
public let markdownTaskListCheckedNumber = "\u{001f}tg-md-task:checked"

/// The leading rich text of a block for preview purposes — keeps the `RichText` (rather than
/// flattening to a string) so inline custom emoji can be carried out as `.CustomEmoji` entities.
private func markdownPreviewRichText(from block: InstantPageBlock) -> RichText? {
    switch block {
    case let .title(text):           return text
    case let .subtitle(text):        return text
    case let .authorDate(author, _): return author
    case let .header(text):          return text
    case let .subheader(text):       return text
    case let .heading(text, _):      return text
    case .formula:                   return .plain("𝑓𝑥")   // compact formula glyph, not the raw LaTeX
    case let .paragraph(text):       return text
    case let .preformatted(text, _): return text
    case let .footer(text):          return text
    case let .list(items, ordered):
        // Flatten the list into a one-line preview that keeps each item's MARKER (so it reads as a list,
        // not a comma-blob): a running number for ordered lists, a checkbox for task items (the `checked`
        // field OR the markdown task-list sentinel number), a bullet otherwise.
        var parts: [RichText] = []
        var counter = 0
        for item in items {
            let itemText: RichText
            let number: String?
            let checked: Bool?
            switch item {
            case let .text(text, n, c):     itemText = text; number = n; checked = c
            case let .blocks(blocks, n, c): itemText = instantPageRichTextFromBlocks(blocks); number = n; checked = c
            case .unknown:                  continue
            }
            if itemText.plainText.isEmpty { continue }
            counter += 1
            let isChecked: Bool?
            if let checked = checked {
                isChecked = checked
            } else if number == markdownTaskListCheckedNumber {
                isChecked = true
            } else if number == markdownTaskListUncheckedNumber {
                isChecked = false
            } else {
                isChecked = nil
            }
            let marker: String
            if let isChecked = isChecked {
                marker = isChecked ? "☑ " : "☐ "
            } else if ordered {
                marker = "\(counter). "
            } else {
                marker = "• "
            }
            if !parts.isEmpty { parts.append(.plain(", ")) }
            parts.append(.plain(marker))
            parts.append(itemText)
        }
        return parts.isEmpty ? nil : .concat(parts)
    case let .blockQuote(blocks, caption, _):
        let inner = instantPageRichTextFromBlocks(blocks)
        return inner.plainText.isEmpty ? caption : inner
    case let .pullQuote(text, caption):
        return text.plainText.isEmpty ? caption : text
    case let .kicker(text):          return text
    case let .cover(block):
        return markdownPreviewRichText(from: block)
    case let .thinking(text):
        return text
    case let .table(title, rows, _, _, _):
        if !title.plainText.isEmpty {
            return title
        }
        var parts: [RichText] = []
        for row in rows {
            for cell in row.cells {
                if let cellText = cell.text, !cellText.plainText.isEmpty {
                    parts.append(cellText)
                }
            }
        }
        return parts.isEmpty ? nil : (parts.count == 1 ? parts[0] : .concat(parts))
    case let .details(title, blocks, _):
        if !title.plainText.isEmpty {
            return title
        }
        let inner = instantPageRichTextFromBlocks(blocks)
        return inner.plainText.isEmpty ? nil : inner
    case let .relatedArticles(title, _): return title
    case let .postEmbed(_, _, _, author, _, blocks, caption):
        let inner = instantPageRichTextFromBlocks(blocks)
        if !inner.plainText.isEmpty {
            return inner
        }
        if !caption.text.plainText.isEmpty {
            return caption.text
        }
        return author.isEmpty ? nil : .plain(author)
    case let .collage(items, caption), let .slideshow(items, caption):
        let inner = instantPageRichTextFromBlocks(items)
        if !inner.plainText.isEmpty {
            return inner
        }
        return caption.text.plainText.isEmpty ? nil : caption.text
    case let .buttonRow(_, buttons):
        var parts: [RichText] = []
        for button in buttons {
            if !button.text.plainText.isEmpty {
                parts.append(button.text)
            }
        }
        return parts.isEmpty ? nil : (parts.count == 1 ? parts[0] : .concat(parts))
    case let .image(_, caption, _, _, _),
         let .video(_, caption, _, _, _),
         let .audio(_, caption),
         let .document(_, caption),
         let .webEmbed(_, _, _, caption, _, _, _),
         let .map(_, _, _, _, caption):
        return caption.text.plainText.isEmpty ? nil : caption.text
    default:                         return nil
    }
}

/// Appends `richText`'s plain text to `out` (UTF-16), recording each inline custom emoji as a
/// `.CustomEmoji` entity over the alt text it occupies.
private func appendPreviewRichText(_ richText: RichText, into out: NSMutableString, entities: inout [MessageTextEntity]) {
    switch richText {
    case .empty:
        break
    case let .plain(string):
        out.append(string)
    case let .bold(text), let .italic(text), let .underline(text), let .strikethrough(text),
         let .fixed(text), let .superscript(text), let .marked(text),
         let .textAutoEmail(text), let .textAutoPhone(text), let .textAutoUrl(text),
         let .textBankCard(text), let .textTonAddress(text), let .textBotCommand(text), let .textCashtag(text),
         let .textHashtag(text), let .textMention(text), let .textSpoiler(text):
        appendPreviewRichText(text, into: out, entities: &entities)
    case let .`subscript`(text):
        appendPreviewRichText(text, into: out, entities: &entities)
    case let .url(text, _, _):
        appendPreviewRichText(text, into: out, entities: &entities)
    case let .email(text, _):
        appendPreviewRichText(text, into: out, entities: &entities)
    case let .phone(text, _):
        appendPreviewRichText(text, into: out, entities: &entities)
    case let .anchor(text, _):
        appendPreviewRichText(text, into: out, entities: &entities)
    case let .textMentionName(text, _):
        appendPreviewRichText(text, into: out, entities: &entities)
    case let .concat(texts):
        for text in texts {
            appendPreviewRichText(text, into: out, entities: &entities)
        }
    case .image:
        break
    case let .textButton(button):
        // Previews (chat list, replies, notifications) are plain text: contribute the button's label
        // so a button-only paragraph doesn't preview as empty.
        appendPreviewRichText(button.text, into: out, entities: &entities)
    case .formula:
        // Previews (chat list, replies, notifications) show a compact formula glyph rather than the raw
        // LaTeX source — a math-italic "𝑓𝑥" that reads like a formula icon.
        out.append("𝑓𝑥")
    case let .textCustomEmoji(fileId, alt):
        let lower = out.length
        out.append(alt)
        let upper = out.length
        if upper > lower {
            entities.append(MessageTextEntity(range: lower ..< upper, type: .CustomEmoji(stickerPack: nil, fileId: fileId)))
        }
    case let .textDate(text, _, _):
        appendPreviewRichText(text, into: out, entities: &entities)
    }
}

/// Trims leading/trailing whitespace from a preview fragment, shifting its entity ranges to match.
private func trimmedPreviewFragment(_ s: NSMutableString, entities: [MessageTextEntity]) -> (NSString, [MessageTextEntity]) {
    let ns = s as NSString
    let ws = CharacterSet.whitespacesAndNewlines
    var start = 0
    while start < ns.length, let scalar = Unicode.Scalar(ns.character(at: start)), ws.contains(scalar) {
        start += 1
    }
    var end = ns.length
    while end > start, let scalar = Unicode.Scalar(ns.character(at: end - 1)), ws.contains(scalar) {
        end -= 1
    }
    if start == 0 && end == ns.length {
        return (ns, entities)
    }
    let trimmed = ns.substring(with: NSRange(location: start, length: end - start)) as NSString
    var adjusted: [MessageTextEntity] = []
    for entity in entities {
        let lo = entity.range.lowerBound - start
        let hi = entity.range.upperBound - start
        if lo >= 0, hi <= trimmed.length, lo < hi {
            adjusted.append(MessageTextEntity(range: lo ..< hi, type: entity.type))
        }
    }
    return (trimmed, adjusted)
}

/// One-line preview of a rich (InstantPage) message, for chat-list / notification previews:
/// concatenates the leading blocks' text (until a short budget) along with `.CustomEmoji` entities
/// so the chat list can render inline custom emoji as stickers.
public func instantPagePreview(_ instantPage: InstantPage) -> (text: String, entities: [MessageTextEntity]) {
    let out = NSMutableString()
    var entities: [MessageTextEntity] = []
    var total = 0
    for block in instantPage.blocks {
        guard let rich = markdownPreviewRichText(from: block) else {
            continue
        }
        let frag = NSMutableString()
        var fragEntities: [MessageTextEntity] = []
        appendPreviewRichText(rich, into: frag, entities: &fragEntities)
        let (trimmed, trimmedEntities) = trimmedPreviewFragment(frag, entities: fragEntities)
        if trimmed.length == 0 {
            continue
        }
        let base = out.length + (out.length > 0 ? 1 : 0)
        if out.length > 0 {
            out.append(" ")
        }
        out.append(trimmed as String)
        for entity in trimmedEntities {
            entities.append(MessageTextEntity(range: (base + entity.range.lowerBound) ..< (base + entity.range.upperBound), type: entity.type))
        }
        total += trimmed.length
        if total > 140 {
            break
        }
    }
    return (out as String, entities)
}

/// One-line plain-text preview of a rich (InstantPage) message (custom emoji flattened to their alt
/// text). Used where inline stickers aren't rendered (e.g. notifications).
public func instantPagePreviewText(_ instantPage: InstantPage) -> String {
    return instantPagePreview(instantPage).text
}
