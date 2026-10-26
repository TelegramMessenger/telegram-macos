import Foundation
import OSLog
import ApiCredentials
import FocusFilterCore
import Localization
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramUtils

private func focusCatalogTitle(_ peer: Peer) -> String {
    if let user = peer as? TelegramUser {
        let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? strings().peerDeletedUser : name
    }
    return peer.displayTitle
}

private func focusAccountCatalog(transaction: Transaction, accountId: Int64, filters: [ChatListFilter], communityCategories: [PeerId: ChatListFilterPeerCategories]) -> FocusFilterCatalog {
    let groups: [PeerGroupId] = [.root, Namespaces.PeerGroup.archive]
    var peers: [PeerId: (peer: Peer, isArchived: Bool)] = [:]
    for groupId in groups {
        for peer in transaction.getChatListPeers(groupId: groupId, filterPredicate: nil, additionalFilter: nil) {
            peers[peer.id] = (peer, groupId == Namespaces.PeerGroup.archive)
        }
    }
    let chats = peers.values.map { entry in
        FocusCatalogChat(id: FocusChatIdentifier(accountId: accountId, peerId: entry.peer.id.toInt64()), title: focusCatalogTitle(entry.peer), isArchived: entry.isArchived)
    }.sorted { $0.id.peerId < $1.id.peerId }
    let folders = filters.map { filter -> FocusCatalogFolder in
        let predicate = chatListFilterPredicate(for: filter, communityCategories: communityCategories)
        var peerIds = Set<Int64>()
        for groupId in groups {
            for peer in transaction.getChatListPeers(groupId: groupId, filterPredicate: predicate, additionalFilter: nil) {
                peerIds.insert(peer.id.toInt64())
            }
        }
        return FocusCatalogFolder(id: FocusFolderIdentifier(accountId: accountId, folderId: filter.id), title: filter.title, peerIds: peerIds)
    }.sorted { $0.id.folderId < $1.id.folderId }
    return FocusFilterCatalog(chats: chats, folders: folders)
}

private final class FocusAccountCatalogContext {
    let account: Account
    var title: String
    var catalog = FocusFilterCatalog()

    private let queue: Queue
    private let updated: () -> Void
    private let changesDisposable = MetaDisposable()
    private let snapshotDisposable = MetaDisposable()
    private var pending: (filters: [ChatListFilter], communityCategories: [PeerId: ChatListFilterPeerCategories])?
    private var timer: SwiftSignalKit.Timer?
    private var snapshotInProgress = false

    init(account: Account, title: String, queue: Queue, updated: @escaping () -> Void) {
        self.account = account
        self.title = title
        self.queue = queue
        self.updated = updated

        let summaryKey = ChatListEntryMessageTagSummaryKey(tag: .unseenPersonalMessage, actionType: PendingMessageActionType.consumeUnseenPersonalMessage)
        let summaries = ChatListEntrySummaryComponents(components: [
            summaryKey: .init(
                tagSummary: .init(namespace: Namespaces.Message.Cloud),
                actionsSummary: .init(namespace: Namespaces.Message.Cloud)
            )
        ])
        let localEntryLimit = Int(Int32.max) / 2
        let rootChanges = account.postbox.tailChatListView(groupId: .root, count: localEntryLimit, summaryComponents: summaries)
        |> map { _ in () }
        let archiveChanges = account.postbox.tailChatListView(groupId: Namespaces.PeerGroup.archive, count: localEntryLimit, summaryComponents: summaries)
        |> map { _ in () }
        let contactChanges = account.postbox.contactPeerIdsView() |> map { _ in () }
        let filters = TelegramEngine(account: account).peers.updatedChatListFilters()
        self.changesDisposable.set((combineLatest(rootChanges, archiveChanges, filters, communityFilterCategories(account: account), contactChanges)
        |> deliverOn(queue)).start(next: { [weak self] _, _, filters, categories, _ in
            guard let self = self else { return }
            self.pending = (filters, categories)
            self.scheduleSnapshot()
        }))
    }

    private func scheduleSnapshot() {
        guard timer == nil, !snapshotInProgress else { return }
        let timer = SwiftSignalKit.Timer(timeout: 0.2, repeat: false, completion: { [weak self] in
            guard let self = self else { return }
            self.timer = nil
            self.takeSnapshot()
        }, queue: queue)
        self.timer = timer
        timer.start()
    }

    private func takeSnapshot() {
        guard let pending = pending else { return }
        self.pending = nil
        self.snapshotInProgress = true
        let account = self.account
        self.snapshotDisposable.set((account.postbox.transaction { transaction in
            focusAccountCatalog(transaction: transaction, accountId: account.id.int64, filters: pending.filters, communityCategories: pending.communityCategories)
        } |> deliverOn(queue)).start(next: { [weak self] catalog in
            guard let self = self else { return }
            self.snapshotInProgress = false
            if self.catalog != catalog {
                self.catalog = catalog
                self.updated()
            }
            if self.pending != nil {
                self.scheduleSnapshot()
            }
        }))
    }

    deinit {
        changesDisposable.dispose()
        snapshotDisposable.dispose()
        timer?.invalidate()
    }
}

final class FocusFilterCoordinator {
    private let queue = Queue(name: "FocusFilterCatalog", qos: .utility)
    private let accountsDisposable = MetaDisposable()
    private let logger = OSLog(subsystem: "org.telegram.macos", category: "FocusFilters")
    private var accounts: [Int64: FocusAccountCatalogContext] = [:]

    init?(sharedContext: SharedAccountContext) {
        guard let container = ApiEnvironment.containerURL else { return nil }
        FocusFilterStore.shared.configure(
            directory: container.appendingPathComponent("FocusFilters", isDirectory: true),
            notificationName: "\(ApiEnvironment.group).FocusFilters.\(ApiEnvironment.prefix)"
        )
        self.accountsDisposable.set((sharedContext.activeAccountsWithInfo |> deliverOn(queue)).start(next: { [weak self] _, infos in
            guard let self = self else { return }
            let currentIds = Set(infos.map { $0.account.id.int64 })
            for id in Array(self.accounts.keys) where !currentIds.contains(id) {
                self.accounts.removeValue(forKey: id)
            }
            for info in infos {
                let id = info.account.id.int64
                if let current = self.accounts[id], current.account === info.account {
                    current.title = focusCatalogTitle(info.peer)
                } else {
                    self.accounts[id] = FocusAccountCatalogContext(account: info.account, title: focusCatalogTitle(info.peer), queue: self.queue, updated: { [weak self] in
                        self?.publishCatalog()
                    })
                }
            }
            self.publishCatalog()
        }))
    }

    func refresh() {
        FocusFilterStore.shared.reload()
    }

    private func publishCatalog() {
        var catalog = FocusFilterCatalog()
        for id in accounts.keys.sorted() {
            guard let context = accounts[id] else { continue }
            catalog.accounts.append(FocusCatalogAccount(id: id, title: context.title))
            catalog.chats.append(contentsOf: context.catalog.chats)
            catalog.folders.append(contentsOf: context.catalog.folders)
        }
        do {
            try FocusFilterStore.shared.updateCatalog(catalog)
        } catch {
            os_log("Unable to update Focus filter catalog: %{private}@", log: logger, type: .error, error.localizedDescription)
        }
    }

    deinit {
        accountsDisposable.dispose()
    }
}

private func focusNotificationFolderIncludes(transaction: Transaction, peer: Peer, groupId: PeerGroupId, predicate: ChatListFilterPredicate?, isMuted: Bool, isUnread: Bool, isContact: Bool) -> Bool {
    guard let predicate = predicate else { return true }
    if predicate.pinnedPeerIds.contains(peer.id) {
        return true
    }
    let messageTagSummaryResult: Bool?
    if let calculation = predicate.messageTagSummary {
        let addCount = transaction.getMessageTagSummary(peerId: peer.id, threadId: nil, tagMask: calculation.addCount.tag, namespace: calculation.addCount.namespace, customTag: nil)?.count ?? 0
        let subtractCount = transaction.getPendingMessageActionsSummary(peerId: peer.id, type: calculation.subtractCount.type, namespace: calculation.subtractCount.namespace) ?? 0
        messageTagSummaryResult = addCount - subtractCount > 0
    } else {
        messageTagSummaryResult = nil
    }
    return predicate.includes(peer: peer, groupId: groupId, isRemovedFromTotalUnreadCount: isMuted, isUnread: isUnread, isContact: isContact, messageTagSummaryResult: messageTagSummaryResult)
}

func focusNotificationPolicy(transaction: Transaction, accountId: Int64, peerId: PeerId, filters: [ChatListFilter], communityCategories: [PeerId: ChatListFilterPeerCategories], configuration: FocusFilterConfiguration) -> FocusFilterPolicy {
    guard configuration.effect.contains(.notifications), configuration.accountIds.contains(accountId),
          let peer = transaction.getPeer(peerId),
          let (groupId, _) = transaction.getPeerChatListIndex(peerId),
          groupId == .root || groupId == Namespaces.PeerGroup.archive else {
        return FocusFilterPolicy(configuration: configuration)
    }
    let selectedFolders = configuration.folderIds.filter { $0.accountId == accountId }
    let isUnread = transaction.getCombinedPeerReadState(peerId)?.isUnread ?? false
    let isContact = transaction.isPeerContact(peerId: peerId)
    let isMuted = resolvedIsRemovedFromTotalUnreadCount(globalSettings: transaction.getGlobalNotificationSettings(), peer: peer, peerSettings: transaction.getPeerNotificationSettings(id: peerId))
    let folders = filters.compactMap { filter -> FocusCatalogFolder? in
        let id = FocusFolderIdentifier(accountId: accountId, folderId: filter.id)
        guard selectedFolders.contains(id) else { return nil }
        let predicate = chatListFilterPredicate(for: filter, communityCategories: communityCategories)
        let includes = focusNotificationFolderIncludes(transaction: transaction, peer: peer, groupId: groupId, predicate: predicate, isMuted: isMuted, isUnread: isUnread, isContact: isContact)
        return FocusCatalogFolder(id: id, title: filter.title, peerIds: includes ? [peerId.toInt64()] : [])
    }
    return FocusFilterPolicy(configuration: configuration, catalog: FocusFilterCatalog(folders: folders))
}

func focusNotificationPolicy(account: Account, peerId: PeerId) -> Signal<FocusFilterPolicy, NoError> {
    combineLatest(
        TelegramEngine(account: account).peers.updatedChatListFilters() |> take(1),
        communityFilterCategories(account: account) |> take(1)
    ) |> take(1) |> mapToSignal { filters, categories in
        account.postbox.transaction { transaction in
            focusNotificationPolicy(transaction: transaction, accountId: account.id.int64, peerId: peerId, filters: filters, communityCategories: categories, configuration: FocusFilterStore.shared.policy.configuration)
        }
    }
}
