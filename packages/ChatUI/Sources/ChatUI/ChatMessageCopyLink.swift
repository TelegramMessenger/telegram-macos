import Foundation
import Postbox
import TelegramCore

enum ChatMessageCopyLinkKind: Equatable {
    case channelMessage
    case directMessages
}

func chatMessageCopyLinkKind(messageId: MessageId, peer: Peer?, getPeer: (PeerId) -> Peer?, isService: Bool) -> ChatMessageCopyLinkKind? {
    guard messageId.namespace == Namespaces.Message.Cloud, let channel = peer as? TelegramChannel, !isService else {
        return nil
    }
    if channel.isMonoForum {
        guard let mainChannelId = channel.linkedMonoforumId, let mainChannel = getPeer(mainChannelId) as? TelegramChannel, mainChannel.hasPermission(.manageDirect) else {
            return nil
        }
        return .directMessages
    }
    return .channelMessage
}

func chatMessageCopyLink(exportedLink: String?, messageId: MessageId, kind: ChatMessageCopyLinkKind) -> String? {
    if let exportedLink {
        return exportedLink
    }
    if kind == .directMessages {
        return "https://t.me/c/\(messageId.peerId.id._internalGetInt64Value())/\(messageId.id)"
    }
    return nil
}
