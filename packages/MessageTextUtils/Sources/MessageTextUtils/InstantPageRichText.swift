import Foundation
import TelegramCore

public func instantPageRichTextFromBlocks(_ blocks: [InstantPageBlock]) -> RichText {
    var parts: [RichText] = []
    for block in blocks {
        let text: RichText?
        switch block {
        case let .paragraph(t):        text = t
        case let .title(t):            text = t
        case let .subtitle(t):         text = t
        case let .header(t):           text = t
        case let .subheader(t):        text = t
        case let .kicker(t):           text = t
        case let .footer(t):           text = t
        case let .heading(t, _):       text = t
        case let .preformatted(t, _):  text = t
        case let .thinking(t):         text = t
        case let .cover(b):            text = instantPageRichTextFromBlocks([b])
        default:                       text = nil
        }
        if let text = text {
            if !parts.isEmpty { parts.append(.plain("\n")) }
            parts.append(text)
        }
    }
    if parts.isEmpty { return .empty }
    if parts.count == 1 { return parts[0] }
    return .concat(parts)
}

public func messageReplyQuoteText(_ quote: EngineMessageReplyQuote) -> (text: String, entities: [MessageTextEntity]) {
    guard let richText = quote.richText, !richText.isEmpty else {
        return (quote.text, quote.entities)
    }
    let text = NSMutableString()
    var entities: [MessageTextEntity] = []
    func append(_ richText: RichText) {
        let start = text.length
        var entityType: MessageTextEntityType?
        switch richText {
        case let .bold(inner): append(inner); entityType = .Bold
        case let .italic(inner): append(inner); entityType = .Italic
        case let .underline(inner): append(inner); entityType = .Underline
        case let .strikethrough(inner): append(inner); entityType = .Strikethrough
        case let .fixed(inner): append(inner); entityType = .Code
        case let .textSpoiler(inner): append(inner); entityType = .Spoiler
        case let .url(inner, url, _): append(inner); entityType = .TextUrl(url: url)
        case let .textCustomEmoji(fileId, alt):
            text.append(alt)
            entityType = .CustomEmoji(stickerPack: nil, fileId: fileId)
        case let .concat(parts):
            for part in parts { append(part) }
        case let .subscript(inner), let .superscript(inner), let .marked(inner),
             let .email(inner, _), let .phone(inner, _), let .anchor(inner, _),
             let .textAutoEmail(inner), let .textAutoPhone(inner), let .textAutoUrl(inner),
             let .textBankCard(inner), let .textTonAddress(inner), let .textBotCommand(inner),
             let .textCashtag(inner), let .textHashtag(inner), let .textMention(inner),
             let .textMentionName(inner, _), let .textDate(inner, _, _):
            append(inner)
        case let .textButton(button): append(button.text)
        case .formula: text.append("𝑓𝑥")
        case .plain, .empty, .image: text.append(richText.plainText)
        }
        if let entityType, text.length > start {
            entities.append(MessageTextEntity(range: start ..< text.length, type: entityType))
        }
    }
    for (index, part) in richText.enumerated() {
        if index != 0 { text.append("\n") }
        append(part)
    }
    return (text as String, entities)
}
