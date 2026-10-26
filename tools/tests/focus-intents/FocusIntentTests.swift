import AppIntents
import FocusFilterCore
import Foundation

enum TestFailure: Error {
    case unexpectedStorageAccess
    case persistence
}

enum FocusIntentStorage {
    static var repository: (any FocusFilterRepository)?

    static func store() throws -> any FocusFilterRepository {
        guard let repository else {
            throw TestFailure.unexpectedStorageAccess
        }
        return repository
    }

    static func loadCatalog() -> FocusFilterCatalog {
        preconditionFailure("Tests must inject a catalog provider")
    }
}

private final class TestObservation: FocusFilterObservation {
    func invalidate() {
    }
}

private final class TestRepository: FocusFilterRepository {
    var policy = FocusFilterPolicy()
    var configurations: [FocusFilterConfiguration] = []
    var failWrites = false

    func observe(_ observer: @escaping (FocusFilterPolicy) -> Void) -> any FocusFilterObservation {
        observer(policy)
        return TestObservation()
    }

    func reload() {
    }

    func updateConfiguration(_ configuration: FocusFilterConfiguration) throws {
        if failWrites {
            throw TestFailure.persistence
        }
        configurations.append(configuration)
        policy = FocusFilterPolicy(configuration: configuration, catalog: policy.catalog)
    }

    func updateCatalog(_ catalog: FocusFilterCatalog) throws {
        policy = FocusFilterPolicy(configuration: policy.configuration, catalog: catalog)
    }
}

private final class TestCatalogSource: @unchecked Sendable {
    private let catalog: FocusFilterCatalog
    private let lock = NSLock()
    private var readCount = 0

    init(catalog: FocusFilterCatalog) {
        self.catalog = catalog
    }

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return readCount
    }

    func loadCatalog() -> FocusFilterCatalog {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        return catalog
    }
}

@main
private enum FocusIntentTests {
    static func main() async throws {
        let catalog = FocusFilterCatalog(
            accounts: [.init(id: 1, title: "Work"), .init(id: 2, title: "Personal")],
            chats: [
                .init(id: .init(accountId: 1, peerId: 42), title: "Work Chat"),
                .init(id: .init(accountId: 2, peerId: 42), title: "Personal Chat"),
                .init(id: .init(accountId: 1, peerId: 4_294_967_338), title: "Secret Chat")
            ],
            folders: [
                .init(id: .init(accountId: 1, folderId: 7), title: "Work Folder", peerIds: [42]),
                .init(id: .init(accountId: 2, folderId: 7), title: "Personal Folder", peerIds: [42])
            ]
        )
        let catalogSource = TestCatalogSource(catalog: catalog)
        let provider: @Sendable () -> FocusFilterCatalog = { catalogSource.loadCatalog() }
        let accountQuery = FocusAccountQuery(catalogProvider: provider)
        let folderQuery = FocusFolderQuery(catalogProvider: provider)
        let chatQuery = FocusChatQuery(catalogProvider: provider)
        let accounts = try await accountQuery.entities(for: ["1", "2", "3", "invalid"])
        precondition(accounts.map(\.id) == ["1", "2", "3"])
        precondition(accounts.map(\.title) == ["Work", "Personal", String(localized: "Unavailable account")])
        precondition(catalogSource.reads == 1)
        let folders = try await folderQuery.entities(for: ["1:7", "2:7", "1:999", "3:7", "invalid", "1:2:3"])
        precondition(folders.map(\.id) == ["1:7", "2:7", "1:999", "3:7"])
        precondition(folders.map(\.title) == ["Work Folder", "Personal Folder", String(localized: "Unavailable folder"), String(localized: "Unavailable folder")])
        precondition(folders.map(\.accountTitle) == ["Work", "Personal", "Work", String(localized: "Unavailable account")])
        let chats = try await chatQuery.entities(for: ["1:42", "2:42", "1:4294967338", "1:999", "3:42", "invalid", "1:2:3"])
        precondition(chats.map(\.id) == ["1:42", "2:42", "1:4294967338", "1:999", "3:42"])
        precondition(chats.map(\.title) == ["Work Chat", "Personal Chat", "Secret Chat", String(localized: "Unavailable chat"), String(localized: "Unavailable chat")])
        precondition(chats.map(\.accountTitle) == ["Work", "Personal", "Work", "Work", String(localized: "Unavailable account")])
        precondition(catalogSource.reads == 3)
        let suggestedAccounts = try await accountQuery.suggestedEntities()
        let suggestedFolders = try await folderQuery.suggestedEntities()
        let suggestedChats = try await chatQuery.suggestedEntities()
        precondition(suggestedAccounts.map(\.id) == ["1", "2"])
        precondition(suggestedFolders.map(\.id) == ["1:7", "2:7"])
        precondition(suggestedChats.map(\.id) == ["1:42", "2:42", "1:4294967338"])
        let matchingAccounts = try await accountQuery.entities(matching: "work")
        let matchingFolders = try await folderQuery.entities(matching: "personal")
        let matchingChats = try await chatQuery.entities(matching: "work")
        precondition(matchingAccounts.map(\.id) == ["1"])
        precondition(matchingFolders.map(\.id) == ["2:7"])
        precondition(matchingChats.map(\.id) == ["1:42", "1:4294967338"])
        precondition(catalogSource.reads == 9)

        precondition(FocusEffectParameter.notifications.filterEffect == .notifications)
        precondition(FocusEffectParameter.chatList.filterEffect == .chatList)
        precondition(FocusEffectParameter.both.filterEffect == .both)
        precondition(FocusModeParameter.allowSelected.filterMode == .allowSelected)
        precondition(FocusModeParameter.excludeSelected.filterMode == .excludeSelected)
        let intent = TelegramFocusFilter()
        precondition(intent.configuration == FocusFilterConfiguration())
        intent.accounts = accounts + [FocusAccountEntity(id: "invalid", title: "Invalid")]
        intent.folders = folders + [FocusFolderEntity(id: "invalid", title: "Invalid", accountTitle: "Invalid")]
        intent.chats = chats + [FocusChatEntity(id: "invalid", title: "Invalid", accountTitle: "Invalid")]
        intent.mode = .excludeSelected
        intent.effect = .both
        let configuration = intent.configuration
        precondition(configuration.accountIds == [1, 2, 3])
        precondition(configuration.chatIds == Set(chats.compactMap { FocusChatIdentifier(rawValue: $0.id) }))
        precondition(configuration.folderIds == Set(folders.compactMap { FocusFolderIdentifier(rawValue: $0.id) }))
        precondition(configuration.mode == .excludeSelected && configuration.effect == .both)
        let repository = TestRepository()
        FocusIntentStorage.repository = repository
        _ = try await intent.perform()
        precondition(repository.configurations == [configuration])
        repository.failWrites = true
        do {
            _ = try await intent.perform()
            preconditionFailure("Persistence failure must reach the intent caller")
        } catch TestFailure.persistence {
            precondition(repository.configurations == [configuration])
        }
        print("PASS: native Focus queries, identifiers, unavailable entities, configuration and persistence errors")
    }
}
