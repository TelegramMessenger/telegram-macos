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
    private static func testTelegramChatIdentifiers() async throws {
        let catalog = FocusFilterCatalog(
            accounts: [.init(id: -71, title: "Account", telegramUserId: 6_123_456_789)],
            chats: [
                .init(id: .init(accountId: -71, peerId: 42), title: "User", telegramChatId: 42),
                .init(id: .init(accountId: -71, peerId: 4_294_967_338), title: "Group", telegramChatId: -42),
                .init(id: .init(accountId: -71, peerId: 8_589_934_634), title: "Channel", telegramChatId: -1_000_000_000_042),
                .init(id: .init(accountId: -71, peerId: 12_884_901_930), title: "Secret", telegramChatId: -1_999_999_999_958),
                .init(id: .init(accountId: -71, peerId: 99), title: "Legacy")
            ],
            folders: [.init(id: .init(accountId: -71, folderId: 7), title: "Folder", peerIds: [])]
        )
        let query = FocusChatQuery(catalogProvider: { catalog })
        let suggested = try await query.suggestedEntities()
        let restored = try await query.entities(for: suggested.map(\.id))
        let expected = ["User (42)", "Group (-42)", "Channel (-1000000000042)", "Secret (-1999999999958)", "Legacy"]
        precondition(suggested.map { String(localized: $0.displayRepresentation.title) } == expected)
        precondition(restored.map { String(localized: $0.displayRepresentation.title) } == expected)
        precondition(restored.allSatisfy { String(localized: $0.displayRepresentation.subtitle!) == "Account (6123456789)" })
        let foundByTelegramId = try await query.entities(matching: "-1000000000042")
        let foundByInternalId = try await query.entities(matching: "-71:8589934634")
        precondition(foundByTelegramId.map(\.id) == ["-71:8589934634"])
        precondition(foundByInternalId.isEmpty)
        let intent = TelegramFocusFilter()
        intent.chats = Set(restored)
        precondition(intent.configuration.chatIds == Set(catalog.chats.map(\.id)))
        let folders = try await FocusFolderQuery(catalogProvider: { catalog }).suggestedEntities()
        precondition(String(localized: folders[0].displayRepresentation.subtitle!) == "Account (6123456789)")
    }

    private static func testTelegramAccountIdentifiers() async throws {
        let localId: Int64 = -8_000_000_000_000_000_001
        let telegramId: Int64 = 6_123_456_789
        let catalog = try JSONDecoder().decode(FocusFilterCatalog.self, from: Data(#"{"accounts":[{"id":-8000000000000000001,"title":"Same","telegramUserId":6123456789},{"id":8000000000000000001,"title":"Same","telegramUserId":7123456789}],"chats":[],"folders":[]}"#.utf8))
        let query = FocusAccountQuery(catalogProvider: { catalog })
        let restored = try await query.entities(for: [String(localId)])
        let suggested = try await query.suggestedEntities()
        precondition(restored.count == 1 && restored[0].id == String(localId))
        precondition(String(localized: restored[0].displayRepresentation.title) == "Same (6123456789)", "Account labels must show the Telegram user ID, not the local account record ID")
        precondition(suggested.map { String(localized: $0.displayRepresentation.title) } == ["Same (6123456789)", "Same (7123456789)"])
        let foundByTelegramId = try await query.entities(matching: String(telegramId))
        let foundByLocalId = try await query.entities(matching: String(localId))
        precondition(foundByTelegramId.map(\.id) == [String(localId)])
        precondition(foundByLocalId.isEmpty)
        let intent = TelegramFocusFilter()
        intent.accounts = Set(restored)
        precondition(intent.configuration.accountIds == [localId])
        precondition(String(localized: intent.displayRepresentation.subtitle!) == "Same (6123456789)")
        let policy = FocusFilterPolicy(configuration: intent.configuration, catalog: catalog)
        precondition(!policy.includes(accountId: localId, peerId: 42, effect: .notifications))
        precondition(policy.includes(accountId: telegramId, peerId: 42, effect: .notifications))
    }

    private static func testLegacyAccountIdentifiers() async throws {
        let legacy = try JSONDecoder().decode(FocusFilterCatalog.self, from: Data(#"{"accounts":[{"id":-123,"title":"Same"},{"id":456,"title":"Same"}],"chats":[],"folders":[]}"#.utf8))
        let query = FocusAccountQuery(catalogProvider: { legacy })
        let suggested = try await query.suggestedEntities()
        precondition(suggested.map { String(localized: $0.displayRepresentation.title) } == ["Same", "Same"])
        let restored = try await query.entities(for: ["-123", "456", "-789"])
        precondition(restored.map(\.id) == ["-123", "456", "-789"])
        precondition(String(localized: restored[2].displayRepresentation.title) == String(localized: "Unavailable account"))
        precondition(!String(localized: restored[2].displayRepresentation.title).contains("Telegram ID"))
        let refreshed = FocusAccountEntity(id: "-123", title: "Renamed", telegramUserId: 6_123_456_789)
        precondition(Set([suggested[0], refreshed]).count == 1)
        let intent = TelegramFocusFilter()
        intent.accounts = Set(restored)
        precondition(intent.configuration.accountIds == [-123, 456, -789])
    }

    private static func testUniqueSelections() async throws {
        let account = FocusAccountEntity(id: "1", title: "Same", telegramUserId: 101)
        let renamedAccount = FocusAccountEntity(id: "1", title: "Renamed", telegramUserId: 101)
        let otherAccount = FocusAccountEntity(id: "2", title: "Same", telegramUserId: 202)
        let folder = FocusFolderEntity(id: "1:7", title: "Same", accountTitle: "Same")
        let renamedFolder = FocusFolderEntity(id: "1:7", title: "Renamed", accountTitle: "Renamed")
        let otherFolder = FocusFolderEntity(id: "1:8", title: "Same", accountTitle: "Same")
        let crossAccountFolder = FocusFolderEntity(id: "2:7", title: "Same", accountTitle: "Same")
        let chat = FocusChatEntity(id: "1:42", title: "Same", accountTitle: "Same", telegramChatId: 42)
        let renamedChat = FocusChatEntity(id: "1:42", title: "Renamed", accountTitle: "Renamed", telegramChatId: 42)
        let otherChat = FocusChatEntity(id: "1:43", title: "Same", accountTitle: "Same", telegramChatId: 43)
        let crossAccountChat = FocusChatEntity(id: "2:42", title: "Same", accountTitle: "Same", telegramChatId: 42)
        let secretChat = FocusChatEntity(id: "1:4294967338", title: "Same", accountTitle: "Same", telegramChatId: -42)
        let intent = TelegramFocusFilter()
        intent.accounts = [account, account, renamedAccount, otherAccount]
        intent.folders = [folder, folder, renamedFolder, otherFolder, crossAccountFolder]
        intent.chats = [chat, chat, renamedChat, otherChat, crossAccountChat, secretChat]
        precondition(intent.accounts?.count == 2, "Account selection must be unique by ID, including renamed entities")
        precondition(intent.folders?.count == 3, "Folder selection must be unique by account and folder ID")
        precondition(intent.chats?.count == 4, "Chat selection must preserve different accounts and peer namespaces")
        precondition(String(localized: intent.displayRepresentation.subtitle!).contains("101"))
        intent.accounts?.remove(renamedAccount)
        intent.folders?.remove(renamedFolder)
        intent.chats?.remove(renamedChat)
        precondition(intent.accounts?.count == 1)
        precondition(intent.folders?.count == 2)
        precondition(intent.chats?.count == 3)
        intent.accounts?.insert(account)
        intent.folders?.insert(folder)
        intent.chats?.insert(chat)
        precondition(String(localized: intent.displayRepresentation.subtitle!) == "Same (101), Same (202)")
        precondition(intent.configuration.accountIds == [1, 2])
        precondition(intent.configuration.folderIds.count == 3)
        precondition(intent.configuration.chatIds.count == 4)
        precondition(String(localized: account.displayRepresentation.title) == "Same (101)")
        precondition(String(localized: folder.displayRepresentation.title) == "Same (ID: 1:7)")
        precondition(String(localized: chat.displayRepresentation.title) == "Same (42)")
        precondition(Set([account, otherAccount].map { String(localized: $0.displayRepresentation.title) }).count == 2)
        precondition(Set([folder, otherFolder, crossAccountFolder].map { String(localized: $0.displayRepresentation.title) }).count == 3)
        precondition(Set([chat, otherChat, crossAccountChat, secretChat].map { String(localized: $0.displayRepresentation.title) }).count == 3)

        let catalog = FocusFilterCatalog(
            accounts: [.init(id: 1, title: "Same", telegramUserId: 101), .init(id: 1, title: "Renamed", telegramUserId: 101), .init(id: 2, title: "Same", telegramUserId: 202)],
            chats: [
                .init(id: .init(accountId: 1, peerId: 42), title: "Same", telegramChatId: 42),
                .init(id: .init(accountId: 1, peerId: 42), title: "Renamed", telegramChatId: 42),
                .init(id: .init(accountId: 2, peerId: 42), title: "Same", telegramChatId: 42)
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
        precondition(String(localized: accounts[2].displayRepresentation.title) == String(localized: "Unavailable account"))
        precondition(String(localized: folders[2].displayRepresentation.title).contains("ID: 3:7"))
        precondition(String(localized: chats[2].displayRepresentation.title) == String(localized: "Unavailable chat"))
        let suggestedAccounts = try await accountQuery.suggestedEntities()
        let suggestedFolders = try await folderQuery.suggestedEntities()
        let suggestedChats = try await chatQuery.suggestedEntities()
        precondition(suggestedAccounts.map(\.id) == ["1", "2"])
        precondition(suggestedFolders.map(\.id) == ["1:7", "2:7"])
        precondition(suggestedChats.map(\.id) == ["1:42", "2:42"])
        let matchingAccounts = try await accountQuery.entities(matching: "2")
        let matchingFolders = try await folderQuery.entities(matching: "2:7")
        let matchingChats = try await chatQuery.entities(matching: "42")
        precondition(matchingAccounts.map(\.id) == ["2"])
        precondition(matchingFolders.map(\.id) == ["2:7"])
        precondition(matchingChats.map(\.id) == ["1:42", "2:42"])
    }

    static func main() async throws {
        try await testTelegramChatIdentifiers()
        try await testTelegramAccountIdentifiers()
        try await testLegacyAccountIdentifiers()
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
        print("PASS: Telegram user IDs, stable local identity, legacy catalogs, unique Focus selections, queries, configuration and persistence errors")
    }
}
