import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUtils
import FocusFilterCore

struct ChatListFocusRequest {
    let groupId: PeerGroupId
    let location: ChatListIndexRequest
    let filter: ChatListFilter?
    let account: Account
    let selection: FocusFilterSelection

    var chatListLocation: ChatListControllerLocation {
        .chatList(groupId: groupId)
    }

    var restoresGroups: Bool {
        filter == nil || filter?.isAllChats == true
    }
}

struct ChatListFocusQuery: Equatable {
    let pinnedPeerIds: [PeerId]
    let scope: ChatListFocusScope
}

struct ChatListFocusSupport: Equatable {
    let query: ChatListFocusQuery
    let groups: [EngineChatList.GroupItem]
    let additionalItems: [EngineChatList.AdditionalItem]
}

private struct ChatListFocusBaseline {
    let view: ChatListViewUpdate
    let pinnedPeerIds: [PeerId]
}

private func chatListFocusArchiveChanges(accountId: Int64, policies: Signal<FocusFilterPolicy, NoError>) -> Signal<Set<PeerId>, NoError> {
    policies |> map { policy in
        Set(policy.catalog.chats.filter { $0.id.accountId == accountId && $0.isArchived }.map { PeerId($0.id.peerId) })
    } |> distinctUntilChanged
}

private func chatListFocusScopes(_ request: ChatListFocusRequest, policies: Signal<FocusFilterPolicy, NoError>) -> Signal<ChatListFocusScope, NoError> {
    let needsArchiveMembership = request.groupId != .root || (request.filter?.data?.excludeArchived == true && request.filter?.data?.includePeers.peers.isEmpty == false)
    guard needsArchiveMembership else {
        return .single(.root(archivePeerIds: nil))
    }
    return chatListFocusArchiveChanges(accountId: request.account.id.int64, policies: policies) |> mapToSignal { _ in
        request.account.postbox.transaction { transaction -> ChatListFocusScope in
            let archivedPeerIds = Set(transaction.getChatListPeers(groupId: Namespaces.PeerGroup.archive, filterPredicate: nil, additionalFilter: nil).map { $0.id })
            return request.groupId == .root ? .root(archivePeerIds: archivedPeerIds) : .archive(peerIds: archivedPeerIds)
        }
    } |> distinctUntilChanged
}

private func chatListFocusPinnedBaseline(_ request: ChatListFocusRequest) -> Signal<ChatListFocusBaseline, NoError> {
    let baseline = chatListViewForLocation(chatListLocation: request.chatListLocation, location: .Initial(50, nil), filter: nil, account: request.account)
    return baseline |> mapToSignal { view in
        TelegramEngine(account: request.account).peers.getPinnedItemIds(location: .group(request.groupId)) |> map { pinned in
            let peerIds = pinned.map { item -> PeerId in
                switch item {
                case let .peer(peerId):
                    return peerId
                }
            }
            return ChatListFocusBaseline(view: view, pinnedPeerIds: peerIds)
        }
    }
}

private func chatListFocusSanitizedGroups(_ groups: [EngineChatList.GroupItem]) -> [EngineChatList.GroupItem] {
    groups.map {
        EngineChatList.GroupItem(id: $0.id, topMessage: nil, items: [], unreadCount: $0.unreadCount)
    }
}

private func chatListFocusIncludesAdditionalItem(_ item: EngineChatList.AdditionalItem, selection: FocusFilterSelection) -> Bool {
    let peerId = item.item.renderedPeer.peer?._asPeer().id ?? item.item.renderedPeer.peerId
    return selection.includes(peerId: peerId.toInt64())
}

func chatListFocusSupport(_ request: ChatListFocusRequest, policies: Signal<FocusFilterPolicy, NoError>) -> Signal<ChatListFocusSupport, NoError> {
    let baseline = chatListFocusPinnedBaseline(request)
    let scopes = chatListFocusScopes(request, policies: policies)
    return combineLatest(baseline, scopes) |> map { baseline, scope in
        let additionalItems = baseline.view.list.additionalItems.filter {
            chatListFocusIncludesAdditionalItem($0, selection: request.selection)
        }
        return ChatListFocusSupport(query: .init(pinnedPeerIds: baseline.pinnedPeerIds, scope: scope), groups: chatListFocusSanitizedGroups(baseline.view.list.groupItems), additionalItems: additionalItems)
    } |> distinctUntilChanged
}
