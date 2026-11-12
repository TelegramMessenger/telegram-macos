import Foundation
import Postbox

public final class HTMLDemoChatCache {
    private var contents: [String: HTMLDemoChatContents] = [:]

    public init() {
    }

    public func contents(chat: HTMLDemoChat, accountPeerId: PeerId, accountName: String = "You") -> HTMLDemoChatContents {
        assert(Thread.isMainThread)
        let key = "\(accountPeerId.toInt64())|\(chat.id)"
        if let contents = contents[key] {
            return contents
        }
        let contents = HTMLDemoChatContents.reusing(chat: chat, accountPeerId: accountPeerId, accountName: accountName)
        switch chat.preset {
        case .allWidgets?:
            break
        case .voxelClash?, nil:
            self.contents[key] = contents
        }
        return contents
    }
}
