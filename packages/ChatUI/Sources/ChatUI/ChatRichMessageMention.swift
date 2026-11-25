import Foundation
import Postbox
import TelegramCore

func chatRichMessageMentionPeerId(_ url: String) -> PeerId? {
    if case let .mention(peerId) = chatRichTextEditorLink(url) {
        return peerId
    }
    return nil
}
