import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUtils
import FocusFilterCore

func chatListFocusSelection(accountId: Int64) -> Signal<FocusFilterSelection?, NoError> {
    Signal { subscriber in
        let observation = FocusFilterStore.shared.observe { policy in
            subscriber.putNext(policy.selection(accountId: accountId, effect: .chatList))
        }
        return ActionDisposable {
            observation.invalidate()
        }
    } |> distinctUntilChanged
}

private func chatListFocusArchiveChanges(accountId: Int64) -> Signal<Set<PeerId>, NoError> {
    Signal { subscriber in
        let observation = FocusFilterStore.shared.observe { policy in
            let ids = policy.catalog.chats.filter { $0.id.accountId == accountId && $0.isArchived }.map { PeerId($0.id.peerId) }
            subscriber.putNext(Set(ids))
        }
        return ActionDisposable {
            observation.invalidate()
        }
    } |> distinctUntilChanged
}

private func focusIncludesPeer(_ peer: Peer, selection: FocusFilterSelection) -> Bool {
    selection.includes(peerId: peer.id.toInt64())
}

func focusAllowsChatListPeer(_ peerId: PeerId, selection: FocusFilterSelection, archivePeerIds: Set<PeerId>?, archiveOnly: Bool) -> Bool {
    selection.includes(peerId: peerId.toInt64()) && (!archiveOnly || archivePeerIds?.contains(peerId) == true)
}

func focusChatListPredicate(_ base: ChatListFilterPredicate?, selection: FocusFilterSelection, pinnedPeerIds: [PeerId], archivePeerIds: Set<PeerId>?, archiveOnly: Bool = false) -> ChatListFilterPredicate {
    var predicate = base ?? ChatListFilterPredicate(includePeerIds: [], excludePeerIds: [], pinnedPeerIds: pinnedPeerIds, messageTagSummary: nil, includeAdditionalPeerGroupIds: [], include: { _, _, _, _, _ in true })
    let baseInclude = predicate.include
    let baseIncludePeerIds = predicate.includePeerIds
    let baseExcludePeerIds = predicate.excludePeerIds
    let baseIncludesArchive = predicate.includeAdditionalPeerGroupIds.contains(Namespaces.PeerGroup.archive)
    predicate.includePeerIds = []
    predicate.excludePeerIds = []
    predicate.pinnedPeerIds = predicate.pinnedPeerIds.filter {
        focusAllowsChatListPeer($0, selection: selection, archivePeerIds: archivePeerIds, archiveOnly: archiveOnly)
    }
    if archiveOnly {
        predicate.includeAdditionalPeerGroupIds = [Namespaces.PeerGroup.archive]
    } else if archivePeerIds != nil && !baseIncludePeerIds.isEmpty && !baseIncludesArchive {
        predicate.includeAdditionalPeerGroupIds.append(Namespaces.PeerGroup.archive)
    }
    predicate.include = { peer, isMuted, isUnread, isContact, tagSummary in
        guard focusAllowsChatListPeer(peer.id, selection: selection, archivePeerIds: archivePeerIds, archiveOnly: archiveOnly) else {
            return false
        }
        let baseIdentity: PeerId
        if let associatedId = peer.associatedPeerId, peer.associatedPeerOverridesIdentity {
            baseIdentity = associatedId
        } else {
            baseIdentity = peer.id
        }
        if baseExcludePeerIds.contains(baseIdentity) {
            return false
        }
        if baseIncludePeerIds.contains(baseIdentity) {
            return true
        }
        if !archiveOnly && !baseIncludesArchive && archivePeerIds?.contains(peer.id) == true {
            return false
        }
        return baseInclude(peer, isMuted, isUnread, isContact, tagSummary)
    }
    return predicate
}

private struct ChatListFocusQuery: Equatable {
    let pinnedPeerIds: [PeerId]
    let archivePeerIds: Set<PeerId>?
}

private struct ChatListFocusSupport: Equatable {
    let query: ChatListFocusQuery
    let groups: [EngineChatList.GroupItem]
    let additionalItems: [EngineChatList.AdditionalItem]
}

func focusFilteredChatListView(chatListLocation: ChatListControllerLocation, location: ChatListIndexRequest, filter: ChatListFilter?, account: Account, selection: FocusFilterSelection?) -> Signal<ChatListViewUpdate, NoError> {
    guard let selection, case let .chatList(groupId) = chatListLocation else {
        return chatListViewForLocation(chatListLocation: chatListLocation, location: location, filter: filter, account: account)
    }
    let archiveOnly = groupId != .root
    let needsArchiveMembership = archiveOnly || (filter?.data?.excludeArchived == true && filter?.data?.includePeers.peers.isEmpty == false)
    let archivePeers: Signal<Set<PeerId>?, NoError>
    if needsArchiveMembership {
        archivePeers = chatListFocusArchiveChanges(accountId: account.id.int64) |> mapToSignal { _ in
            account.postbox.transaction { transaction -> Set<PeerId>? in
                Set(transaction.getChatListPeers(groupId: Namespaces.PeerGroup.archive, filterPredicate: nil, additionalFilter: nil).map { $0.id })
            }
        } |> distinctUntilChanged
    } else {
        archivePeers = .single(nil)
    }
    let baseline = chatListViewForLocation(chatListLocation: chatListLocation, location: .Initial(50, nil), filter: nil, account: account)
    let baselineWithPins = baseline |> mapToSignal { baseline in
        TelegramEngine(account: account).peers.getPinnedItemIds(location: .group(groupId)) |> map { (baseline, $0) }
    }
    let support = combineLatest(baselineWithPins, archivePeers) |> map { value, archivePeerIds -> ChatListFocusSupport in
            let (baseline, pinned) = value
            let pinnedPeerIds = pinned.map { item -> PeerId in
                switch item {
                case let .peer(peerId): return peerId
                }
            }
            let groups = baseline.list.groupItems.map { group in
                EngineChatList.GroupItem(id: group.id, topMessage: nil, items: [], unreadCount: group.unreadCount)
            }
            let additionalItems = baseline.list.additionalItems.filter { item in
                guard let peer = item.item.renderedPeer.peer?._asPeer() else {
                    return selection.includes(peerId: item.item.renderedPeer.peerId.toInt64())
                }
                return focusIncludesPeer(peer, selection: selection)
            }
            return ChatListFocusSupport(query: .init(pinnedPeerIds: pinnedPeerIds, archivePeerIds: archivePeerIds), groups: groups, additionalItems: additionalItems)
    } |> distinctUntilChanged
    let sharedSupport = Promise<ChatListFocusSupport>(initializeOnFirstAccess: support)
    let filtered = sharedSupport.get() |> map { $0.query } |> distinctUntilChanged |> mapToSignal { query in
        let queryLocation: ChatListControllerLocation = archiveOnly ? .chatList(groupId: .root) : chatListLocation
        return chatListViewForLocation(chatListLocation: queryLocation, location: location, filter: filter, account: account, predicateTransform: { base in
            focusChatListPredicate(base, selection: selection, pinnedPeerIds: query.pinnedPeerIds, archivePeerIds: query.archivePeerIds, archiveOnly: archiveOnly)
        }) |> map { (UUID(), $0) }
    }
    let previousRevision = Atomic<UUID?>(value: nil)
    return combineLatest(filtered, sharedSupport.get()) |> map { value, support in
        let (revision, update) = value
        let restoreGroups = filter == nil || filter?.isAllChats == true
        let items = update.list.items.filter {
            focusAllowsChatListPeer($0.renderedPeer.peerId, selection: selection, archivePeerIds: support.query.archivePeerIds, archiveOnly: archiveOnly)
        }
        let additionalItems = (restoreGroups ? support.additionalItems : update.list.additionalItems).filter { selection.includes(peerId: $0.item.renderedPeer.peerId.toInt64()) }
        let list = EngineChatList(items: items, groupItems: restoreGroups ? support.groups : update.list.groupItems, additionalItems: additionalItems, hasEarlier: update.list.hasEarlier, hasLater: update.list.hasLater, isLoading: update.list.isLoading)
        let repeated = previousRevision.swap(revision) == revision
        return update.withUpdatedList(list, type: repeated ? .Generic : nil)
    }
}
