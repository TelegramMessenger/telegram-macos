import Foundation
import SwiftSignalKit

struct ChatListFilter: Equatable {
    let id: Int32
    let title: String
}

struct ChatListFolders: Equatable {
    let list: [ChatListFilter]
    let sidebar: Bool
    let showTags: Bool
}

final class FolderPeers {
    let remote = ValuePipe<[ChatListFilter]>()
    var requests = 0
    var activeRequests = 0

    func requestChatListFilters() -> Signal<[ChatListFilter], NoError> {
        return Signal { subscriber in
            self.requests += 1
            self.activeRequests += 1
            let disposable = self.remote.signal().start(next: subscriber.putNext)
            return ActionDisposable {
                disposable.dispose()
                self.activeRequests -= 1
            }
        }
    }
}

final class FolderEngine {
    let peers = FolderPeers()
    let cached = ValuePromise(ChatListFolders(list: [ChatListFilter(id: 2, title: "Old")], sidebar: false, showTags: false))
}

final class AccountContext {
    let engine = FolderEngine()
}

func chatListFilterPreferences(engine: FolderEngine) -> Signal<ChatListFolders, NoError> {
    return engine.cached.get()
}
