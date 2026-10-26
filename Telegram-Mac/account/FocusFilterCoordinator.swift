import Foundation
import OSLog
import FocusFilterCore
import SwiftSignalKit
import TelegramContext

final class FocusFilterCoordinator {
    private let queue = Queue(name: "FocusFilterCatalog", qos: .utility)
    private let accountsDisposable = MetaDisposable()
    private let logger = OSLog(subsystem: "org.telegram.macos", category: "FocusFilters")
    private var accounts: [Int64: FocusAccountCatalogContext] = [:]

    private let repository: any FocusFilterRepository

    init(sharedContext: SharedAccountContext, repository: any FocusFilterRepository) {
        self.repository = repository
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
        repository.reload()
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
            try repository.updateCatalog(catalog)
        } catch {
            os_log("Unable to update Focus filter catalog: %{private}@", log: logger, type: .error, error.localizedDescription)
        }
    }

    deinit {
        accountsDisposable.dispose()
    }
}
