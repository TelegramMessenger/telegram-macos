import Foundation
import Postbox
import TelegramCore

enum ChatRichTextEditorLink {
    case mention(PeerId)
    case date(Int32)
    case url(String)

    func richText(_ text: RichText) -> RichText {
        switch self {
        case let .mention(peerId): return .textMentionName(text: text, peerId: peerId.id._internalGetInt64Value())
        case let .date(date): return .textDate(text: text, date: date, format: nil)
        case let .url(url): return .url(text: text, url: url, webpageId: nil)
        }
    }
}

func chatRichTextEditorLink(_ link: String) -> ChatRichTextEditorLink {
    let mentionPrefix = "tg://user?id="
    if link.hasPrefix(mentionPrefix), let userId = Int64(link.dropFirst(mentionPrefix.count)), userId > 0, userId < (1 << 52) {
        return .mention(PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(userId)))
    }
    let datePrefix = "tg://timestamp?t="
    if link.hasPrefix(datePrefix), let date = Int32(link.dropFirst(datePrefix.count)) {
        return .date(date)
    }
    return .url(link)
}
