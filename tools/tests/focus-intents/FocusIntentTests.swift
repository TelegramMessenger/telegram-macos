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
    private static func testUniqueSelections() async throws {
        let account = FocusAccountEntity(id: "1", title: "Same")
        let renamedAccount = FocusAccountEntity(id: "1", title: "Renamed")
        let otherAccount = FocusAccountEntity(id: "2", title: "Same")
        let folder = FocusFolderEntity(id: "1:7", title: "Same", accountTitle: "Same")
        let renamedFolder = FocusFolderEntity(id: "1:7", title: "Renamed", accountTitle: "Renamed")
        let otherFolder = FocusFolderEntity(id: "1:8", title: "Same", accountTitle: "Same")
        let crossAccountFolder = FocusFolderEntity(id: "2:7", title: "Same", accountTitle: "Same")
        let chat = FocusChatEntity(id: "1:42", title: "Same", accountTitle: "Same")
        let renamedChat = FocusChatEntity(id: "1:42", title: "Renamed", accountTitle: "Renamed")
        let otherChat = FocusChatEntity(id: "1:43", title: "Same", accountTitle: "Same")
        let crossAccountChat = FocusChatEntity(id: "2:42", title: "Same", accountTitle: "Same")
        let secretChat = FocusChatEntity(id: "1:4294967338", title: "Same", accountTitle: "Same")
        let intent = TelegramFocusFilter()
        intent.accounts = [account, account, renamedAccount, otherAccount]
        intent.folders = [folder, folder, renamedFolder, otherFolder, crossAccountFolder]
        intent.chats = [chat, chat, renamedChat, otherChat, crossAccountChat, secretChat]
        precondition(intent.accounts?.count == 2, "Account selection must be unique by ID, including renamed entities")
        precondition(intent.folders?.count == 3, "Folder selection must be unique by account and folder ID")
        precondition(intent.chats?.count == 4, "Chat selection must preserve different accounts and peer namespaces")
        precondition(String(localized: intent.displayRepresentation.subtitle!).contains("ID: 1"))
        intent.accounts?.remove(renamedAccount)
        intent.folders?.remove(renamedFolder)
        intent.chats?.remove(renamedChat)
        precondition(intent.accounts?.count == 1)
        precondition(intent.folders?.count == 2)
        precondition(intent.chats?.count == 3)
        intent.accounts?.insert(account)
        intent.folders?.insert(folder)
        intent.chats?.insert(chat)
        precondition(String(localized: intent.displayRepresentation.subtitle!) == "Same (ID: 1), Same (ID: 2)")
        precondition(intent.configuration.accountIds == [1, 2])
        precondition(intent.configuration.folderIds.count == 3)
        precondition(intent.configuration.chatIds.count == 4)
        precondition(String(localized: account.displayRepresentation.title) == "Same (ID: 1)")
        precondition(String(localized: folder.displayRepresentation.title) == "Same (ID: 1:7)")
        precondition(String(localized: chat.displayRepresentation.title) == "Same (ID: 1:42)")
        precondition(Set([account, otherAccount].map { String(localized: $0.displayRepresentation.title) }).count == 2)
        precondition(Set([folder, otherFolder, crossAccountFolder].map { String(localized: $0.displayRepresentation.title) }).count == 3)
        precondition(Set([chat, otherChat, crossAccountChat, secretChat].map { String(localized: $0.displayRepresentation.title) }).count == 4)

        let catalog = FocusFilterCatalog(
            accounts: [.init(id: 1, title: "Same"), .init(id: 1, title: "Renamed"), .init(id: 2, title: "Same")],
            chats: [
                .init(id: .init(accountId: 1, peerId: 42), title: "Same"),
                .init(id: .init(accountId: 1, peerId: 42), title: "Renamed"),
                .init(id: .init(accountId: 2, peerId: 42), title: "Same")
            ],
            folders: [
                .init(id: .init(accountId: 1, folderId: 7), title: "Same", peerIds: []),
                .init(id: .init(accountId: 1, folderId: 7), title: "Renamed", peerIds: []),
                .init(id: .init(accountId: 2, folderId: 7), title: "Same", peerIds: [])
            ]
        )
        let accountQuery = FocusAccountQuery(catalogProvider: { catalog })
        let folderQuery = FocusFolderQuery(catalogProvider: { catalog })
        let chatQuery = FocusChatQuery(catalogProvider: { catalog })
        let accounts = try await accountQuery.entities(for: ["1", "01", "2", "3", "3"])
        let folders = try await folderQuery.entities(for: ["1:7", "01:007", "2:7", "3:7", "3:7"])
        let chats = try await chatQuery.entities(for: ["1:42", "01:042", "2:42", "3:42", "3:42"])
        precondition(accounts.map(\.id) == ["1", "2", "3"])
        precondition(folders.map(\.id) == ["1:7", "2:7", "3:7"])
        precondition(chats.map(\.id) == ["1:42", "2:42", "3:42"])
        precondition(String(localized: accounts[2].displayRepresentation.title).contains("ID: 3"))
        precondition(String(localized: folders[2].displayRepresentation.title).contains("ID: 3:7"))
        precondition(String(localized: chats[2].displayRepresentation.title).contains("ID: 3:42"))
        let suggestedAccounts = try await accountQuery.suggestedEntities()
        let suggestedFolders = try await folderQuery.suggestedEntities()
        let suggestedChats = try await chatQuery.suggestedEntities()
        precondition(suggestedAccounts.map(\.id) == ["1", "2"])
        precondition(suggestedFolders.map(\.id) == ["1:7", "2:7"])
        precondition(suggestedChats.map(\.id) == ["1:42", "2:42"])
        let matchingAccounts = try await accountQuery.entities(matching: "2")
        let matchingFolders = try await folderQuery.entities(matching: "2:7")
        let matchingChats = try await chatQuery.entities(matching: "2:42")
        precondition(matchingAccounts.map(\.id) == ["2"])
        precondition(matchingFolders.map(\.id) == ["2:7"])
        precondition(matchingChats.map(\.id) == ["2:42"])
    }

    static func main() async throws {
        try await testUniqueSelections()
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
        intent.accounts = Set(accounts + [FocusAccountEntity(id: "invalid", title: "Invalid")])
        intent.folders = Set(folders + [FocusFolderEntity(id: "invalid", title: "Invalid", accountTitle: "Invalid")])
        intent.chats = Set(chats + [FocusChatEntity(id: "invalid", title: "Invalid", accountTitle: "Invalid")])
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
        print("PASS: unique Focus selections, ID labels/search, queries, unavailable entities, configuration and persistence errors")
    }
}
