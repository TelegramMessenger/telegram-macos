import FocusFilterCore
import Postbox
import TelegramCore
import TelegramUtils

struct FocusNotificationMembershipRequest {
    let chat: FocusChatIdentifier
    let configuration: FocusFilterConfiguration
    let filters: [ChatListFilter]
    let communityCategories: [PeerId: ChatListFilterPeerCategories]
}

func focusNotificationPolicy(transaction: Transaction, request: FocusNotificationMembershipRequest) -> FocusFilterPolicy {
    let configuration = request.configuration
    guard configuration.effect.contains(.notifications), configuration.accountIds.contains(request.chat.accountId),
          let state = FocusFolderChatState(transaction: transaction, peerId: PeerId(request.chat.peerId)) else {
        return FocusFilterPolicy(configuration: configuration)
    }
    let selectedFolders = configuration.folderIds.filter { $0.accountId == request.chat.accountId }
    let folders = request.filters.compactMap { filter -> FocusCatalogFolder? in
        let id = FocusFolderIdentifier(accountId: request.chat.accountId, folderId: filter.id)
        guard selectedFolders.contains(id) else { return nil }
        let predicate = chatListFilterPredicate(for: filter, communityCategories: request.communityCategories)
        let includes = state.belongs(to: predicate, transaction: transaction)
        return FocusCatalogFolder(id: id, title: filter.title, peerIds: includes ? [request.chat.peerId] : [])
    }
    return FocusFilterPolicy(configuration: configuration, catalog: FocusFilterCatalog(folders: folders))
}
