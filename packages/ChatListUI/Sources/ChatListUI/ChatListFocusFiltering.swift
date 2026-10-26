import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUtils
import FocusFilterCore

func chatListFocusSelection(accountId: Int64, policies: Signal<FocusFilterPolicy, NoError>) -> Signal<FocusFilterSelection?, NoError> {
    policies |> map { $0.selection(accountId: accountId, effect: .chatList) } |> distinctUntilChanged
}

private struct ChatListFocusUpdate {
    let revision: UUID
    let view: ChatListViewUpdate

    init(view: ChatListViewUpdate) {
        self.revision = UUID()
        self.view = view
    }
}

private func chatListFocusQueryUpdates(_ request: ChatListFocusRequest, support: Signal<ChatListFocusSupport, NoError>) -> Signal<ChatListFocusUpdate, NoError> {
    support |> map { $0.query } |> distinctUntilChanged |> mapToSignal { query in
        let queryLocation: ChatListControllerLocation
        switch query.scope {
        case .root:
            queryLocation = request.chatListLocation
        case .archive:
            queryLocation = .chatList(groupId: .root)
        }
        return chatListViewForLocation(chatListLocation: queryLocation, location: request.location, filter: request.filter, account: request.account, predicateTransform: { base in
            focusChatListPredicate(base, selection: request.selection, pinnedPeerIds: query.pinnedPeerIds, scope: query.scope)
        }) |> map { ChatListFocusUpdate(view: $0) }
    }
}

private func chatListFocusResult(_ update: ChatListFocusUpdate, request: ChatListFocusRequest, support: ChatListFocusSupport, previousRevision: Atomic<UUID?>) -> ChatListViewUpdate {
    let items = update.view.list.items.filter {
        focusAllowsChatListPeer($0.renderedPeer.peerId, selection: request.selection, scope: support.query.scope)
    }
    let additionalItems = (request.restoresGroups ? support.additionalItems : update.view.list.additionalItems).filter {
        request.selection.includes(peerId: $0.item.renderedPeer.peerId.toInt64())
    }
    let list = EngineChatList(items: items, groupItems: request.restoresGroups ? support.groups : update.view.list.groupItems, additionalItems: additionalItems, hasEarlier: update.view.list.hasEarlier, hasLater: update.view.list.hasLater, isLoading: update.view.list.isLoading)
    let repeated = previousRevision.swap(update.revision) == update.revision
    return update.view.withUpdatedList(list, type: repeated ? .Generic : nil)
}

func focusFilteredChatListView(chatListLocation: ChatListControllerLocation, location: ChatListIndexRequest, filter: ChatListFilter?, account: Account, selection: FocusFilterSelection?, policies: Signal<FocusFilterPolicy, NoError>) -> Signal<ChatListViewUpdate, NoError> {
    guard let selection, case let .chatList(groupId) = chatListLocation else {
        return chatListViewForLocation(chatListLocation: chatListLocation, location: location, filter: filter, account: account)
    }
    let request = ChatListFocusRequest(groupId: groupId, location: location, filter: filter, account: account, selection: selection)
    let support = chatListFocusSupport(request, policies: policies)
    let sharedSupport = Promise<ChatListFocusSupport>(initializeOnFirstAccess: support)
    let filtered = chatListFocusQueryUpdates(request, support: sharedSupport.get())
    let previousRevision = Atomic<UUID?>(value: nil)
    return combineLatest(filtered, sharedSupport.get()) |> map { update, support in
        chatListFocusResult(update, request: request, support: support, previousRevision: previousRevision)
    }
}
