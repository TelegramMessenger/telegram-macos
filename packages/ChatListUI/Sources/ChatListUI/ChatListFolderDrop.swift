import Cocoa
import TGUIKit
import TelegramContext
import TelegramCore
import TelegramUtils
import InAppSettings
import SwiftSignalKit
import Postbox
import InputDataUI
import AlertsUI
import Localization

func chatListFolderDropIsEligible(_ filter: ChatListFilter, peer: Peer, state: SearchPeerFolderState) -> Bool {
    guard state.groupId != nil, peer.id.namespace != Namespaces.Peer.SecretChat,
          peer is TelegramUser || peer is TelegramGroup || peer is TelegramChannel || peer is TelegramCommunity else {
        return false
    }
    if filter == .allChats {
        return state.groupId == Namespaces.PeerGroup.archive
    }
    guard let data = filter.data, !(peer is TelegramCommunity && data.isShared) else {
        return false
    }
    return !data.includePeers.peers.contains(peer.id) && !data.includePeers.pinnedPeers.contains(peer.id) && !searchPeerFolderContains(filter, peer: peer, state: state)
}

func chatListFolderDropUpdate(_ filter: ChatListFilter, peer: Peer, state: SearchPeerFolderState, limit: Int) -> SearchPeerFolderUpdate {
    guard filter.data != nil, chatListFolderDropIsEligible(filter, peer: peer, state: state) else {
        return .unchanged
    }
    return searchPeerFolderUpdate(filter, peer: peer, state: state, limit: limit)
}

func chatListFolderDropUnarchive(transaction: Transaction, peerId: PeerId) -> Bool {
    guard let peer = transaction.getPeer(peerId), peerId.namespace != Namespaces.Peer.SecretChat,
          peer is TelegramUser || peer is TelegramGroup || peer is TelegramChannel || peer is TelegramCommunity,
          case let .ifHasMessagesOrOneOf(groupId, _, minTimestamp) = transaction.getPeerChatListInclusion(peerId), groupId == Namespaces.PeerGroup.archive else {
        return false
    }
    transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: minTimestamp))
    transaction.operationLogAddEntry(peerId: PeerId(0), tag: OperationLogTags.SynchronizeGroupedPeers, tagLocalIndex: .automatic, tagMergedIndex: .automatic, contents: SynchronizeGroupedPeersOperation(peerId: peerId, groupId: .root))
    return true
}

private struct ChatListFolderDragState {
    let peer: Peer
    let folders: SearchPeerFolderState
    let filters: [ChatListFilter]
}

private func chatListFolderDragState(peer: Peer, context: any AccountContextProtocol) -> Signal<ChatListFolderDragState?, NoError> {
    let peerId = peer.id
    let keys: [PostboxViewKey] = [
        .peer(peerId: peerId, components: [.groupId]),
        .chatListIndex(id: peerId),
        .combinedReadState(peerId: peerId, handleThreads: true),
        .historyTagSummaryView(tag: .unseenPersonalMessage, peerId: peerId, threadId: nil, namespace: Namespaces.Message.Cloud, customTag: nil),
        .pendingMessageActionsSummary(type: .consumeUnseenPersonalMessage, peerId: peerId, namespace: Namespaces.Message.Cloud),
        .preferences(keys: Set([PreferencesKeys.globalNotifications, PreferencesKeys.chatListFilters]))
    ]
    let categories: Signal<[PeerId: ChatListFilterPeerCategories], NoError> = peer is TelegramCommunity ? communityFilterCategories(account: context.account) : .single([:])
    return combineLatest(context.account.postbox.combinedView(keys: keys), categories)
    |> deliverOnMainQueue
    |> mapToSignal { _, _ -> Signal<ChatListFolderDragState?, NoError> in
        let state = combineLatest(searchPeerContextMenuSnapshot(peer: peer, context: context, canPin: false), context.engine.peers.currentChatListFilters())
        |> deliverOnMainQueue
        |> map { snapshot, filters -> ChatListFolderDragState? in
            return ChatListFolderDragState(peer: snapshot.peer, folders: snapshot.folders, filters: filters)
        }
        return .single(nil) |> then(state)
    }
}

struct ChatListAvatarDragGesture {
    enum Action {
        case pending
        case drag
        case forward
    }

    let location: NSPoint
    let timestamp: TimeInterval

    func action(location: NSPoint, timestamp: TimeInterval) -> Action {
        let distance = hypot(location.x - self.location.x, location.y - self.location.y)
        guard distance >= 5 else {
            return .pending
        }
        return .drag
    }
}

final class ChatListFolderDragSource: NSObject, NSDraggingSource {
    let context: any AccountContextProtocol
    let peer: Peer
    let token = UUID().uuidString
    private(set) var isActive = true
    private var membership: ChatListFolderDragState?
    private let membershipDisposable = MetaDisposable()
    private let invalidated = Atomic<Bool>(value: false)
    var presentation: ChatListFolderDragPresentation?

    var isInvalidated: Bool {
        return invalidated.with { $0 }
    }

    init(context: any AccountContextProtocol, peer: Peer) {
        self.context = context
        self.peer = peer
        super.init()
        membershipDisposable.set(chatListFolderDragState(peer: peer, context: context).start(next: { [weak self] state in
            guard let self, self.isActive else { return }
            self.membership = state
        }))
    }

    func isEligible(for filter: ChatListFilter) -> Bool {
        guard let membership else { return false }
        let current: ChatListFilter
        if filter == .allChats {
            current = .allChats
        } else if let filter = membership.filters.first(where: { ChatListUIHooks.shared.chatListFilterId($0) == ChatListUIHooks.shared.chatListFilterId(filter) }) {
            current = filter
        } else {
            return false
        }
        return chatListFolderDropIsEligible(current, peer: membership.peer, state: membership.folders)
    }

    private func stopObserving() {
        membershipDisposable.dispose()
        membership = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .copy : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        return true
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        presentation?.move(to: session.draggingLocation)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isActive = false
        stopObserving()
        session.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:]) { [weak self] item, _, _ in
            self?.presentation?.dragFrame = item.draggingFrame
        }
        presentation?.ended(at: session.draggingLocation)
    }

    func consume() {
        isActive = false
        _ = invalidated.swap(true)
        stopObserving()
        presentation?.invalidate()
    }

    func accept(destination: (() -> NSView?)?) {
        isActive = false
        stopObserving()
        presentation?.accept(destination: destination)
    }

    deinit {
        membershipDisposable.dispose()
    }
}

public enum ChatListFolderDrop {
    public static let pasteboardType = NSPasteboard.PasteboardType("org.telegram.chat-folder-peer")

    private static func source(_ sender: NSDraggingInfo, context: any AccountContextProtocol, filter: ChatListFilter?) -> ChatListFolderDragSource? {
        guard let source = sender.draggingSource as? ChatListFolderDragSource, source.isActive,
              source.context.account === context.account, !context.isFrozen, !source.context.isFrozen,
              sender.draggingSourceOperationMask.contains(.copy),
              sender.draggingPasteboard.string(forType: pasteboardType) == source.token,
              source.peer.id.namespace != Namespaces.Peer.SecretChat,
              source.peer is TelegramUser || source.peer is TelegramGroup || source.peer is TelegramChannel || source.peer is TelegramCommunity else {
            return nil
        }
        if let filter, !source.isEligible(for: filter) {
            return nil
        }
        return source
    }

    static func canScroll(_ sender: NSDraggingInfo, context: any AccountContextProtocol) -> Bool {
        return source(sender, context: context, filter: nil) != nil
    }

    public static func validate(_ sender: NSDraggingInfo, context: any AccountContextProtocol, filter: ChatListFilter) -> NSDragOperation {
        return source(sender, context: context, filter: filter) == nil ? [] : .copy
    }

    public static func perform(_ sender: NSDraggingInfo, context: any AccountContextProtocol, filter: ChatListFilter, destination: (() -> NSView?)? = nil, completed: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard let source = source(sender, context: context, filter: filter) else {
            return false
        }
        source.accept(destination: destination)
        if filter == .allChats {
            _ = (context.account.postbox.transaction { transaction -> Bool in
                guard !context.isFrozen, !source.isInvalidated else { return false }
                return chatListFolderDropUnarchive(transaction: transaction, peerId: source.peer.id)
            }
            |> deliverOnMainQueue).start(next: { changed in
                if let presentation = source.presentation {
                    presentation.complete(added: changed, completed: completed)
                } else {
                    completed(changed)
                }
            })
            return true
        }
        let filterId = ChatListUIHooks.shared.chatListFilterId(filter)
        _ = (searchPeerContextMenuSnapshot(peer: source.peer, context: context, canPin: false)
        |> take(1)
        |> deliverOnMainQueue
        |> mapToSignal { snapshot -> Signal<SearchPeerFolderUpdate, NoError> in
            guard !context.isFrozen, !source.isInvalidated else {
                return .single(.unchanged)
            }
            let limit = context.isPremium ? context.premiumLimits.dialog_filters_chats_limit_premium : context.premiumLimits.dialog_filters_chats_limit_default
            let result = Atomic<SearchPeerFolderUpdate>(value: .unchanged)
            return context.engine.peers.updateChatListFiltersInteractively { list in
                guard !context.isFrozen, !source.isInvalidated else { return list }
                var list = list
                if let index = list.firstIndex(where: { ChatListUIHooks.shared.chatListFilterId($0) == filterId }) {
                    let update = chatListFolderDropUpdate(list[index], peer: snapshot.peer, state: snapshot.folders, limit: limit)
                    _ = result.swap(update)
                    if case let .updated(data) = update {
                        list[index] = list[index].withUpdatedData(data)
                    }
                }
                return list
            } |> map { _ in result.with { $0 } }
        }
        |> deliverOnMainQueue).start(next: { result in
            let added: Bool
            if case .updated = result {
                added = true
            } else {
                added = false
            }
            if let presentation = source.presentation {
                presentation.complete(added: added, completed: completed)
            } else {
                completed(added)
            }
            if case .includeLimitReached = result {
                if context.isPremium {
                    alert(for: context.window, info: strings().chatListFilterIncludeLimitReached)
                } else {
                    FeatureNavigationHooks.shared.showPremiumLimit(context, .chatInFolders)
                }
            }
        })
        return true
    }
}
