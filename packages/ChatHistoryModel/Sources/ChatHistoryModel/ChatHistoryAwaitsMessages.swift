import Postbox
import TelegramCore
import TelegramContext

public func chatHistoryMessageIsUndisplayedForumRoot(_ message: Message, location: ChatLocation?, peer: Peer?) -> Bool {
    guard case let .thread(thread) = location, thread.isForumPost else { return false }
    return message.media.contains { media in
        guard let action = media as? TelegramMediaAction else { return false }
        switch action.action {
        case .topicCreated:
            return true
        case .groupCreated:
            if let channel = peer as? TelegramChannel { return channel.isMonoForum }
            if let user = peer as? TelegramUser { return user.isForum }
            return false
        default:
            return false
        }
    }
}

public func chatHistoryViewAwaitsMessages(_ view: MessageHistoryView, location: ChatLocation, peer: Peer?) -> Bool {
    if view.isLoading { return true }
    guard view.holeEarlier || view.holeLater, !view.entries.isEmpty else { return false }
    return view.entries.allSatisfy { chatHistoryMessageIsUndisplayedForumRoot($0.message, location: location, peer: peer) }
}
