import Foundation
import FocusFilterCore
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramUtils

private struct FocusCatalogSnapshotInput {
    let filters: [ChatListFilter]
    let communityCategories: [PeerId: ChatListFilterPeerCategories]
}

final class FocusAccountCatalogContext {
    let account: Account
    var title: String
    var catalog = FocusFilterCatalog()

    private let queue: Queue
    private let updated: () -> Void
    private let changesDisposable = MetaDisposable()
    private let snapshotDisposable = MetaDisposable()
    private var pending: FocusCatalogSnapshotInput?
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
            self.pending = FocusCatalogSnapshotInput(filters: filters, communityCategories: categories)
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
