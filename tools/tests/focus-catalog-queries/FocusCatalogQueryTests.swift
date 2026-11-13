import AppIntents
import FocusFilterCore
import Foundation

private let catalog = FocusFilterCatalog(
    accounts: [FocusCatalogAccount(id: -71, title: "Private account", telegramUserId: 6123456789)],
    chats: [FocusCatalogChat(id: FocusChatIdentifier(accountId: -71, peerId: 42), title: "Private chat", telegramChatId: -1001234567)],
    folders: [FocusCatalogFolder(id: FocusFolderIdentifier(accountId: -71, folderId: 7), title: "Private folder", peerIds: [42])]
)

private final class CatalogProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = true
    private var remainingChecks: Int?
    private var revokeOnRead = false
    private var readCount = 0
    private var permissionCheckCount = 0

    func reset(allowed: Bool, remainingChecks: Int? = nil, revokeOnRead: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        self.allowed = allowed
        self.remainingChecks = remainingChecks
        self.revokeOnRead = revokeOnRead
        readCount = 0
        permissionCheckCount = 0
    }

    func isAllowed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        permissionCheckCount += 1
        guard allowed else { return false }
        if let remainingChecks {
            guard remainingChecks > 0 else { return false }
            self.remainingChecks = remainingChecks - 1
        }
        return true
    }

    func read() -> FocusFilterCatalog {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        if revokeOnRead {
            allowed = false
        }
        return catalog
    }

    var counts: (reads: Int, checks: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (readCount, permissionCheckCount)
    }
}

enum FocusStorageError: Error {
    case locked
}

enum FocusIntentStorage {
    fileprivate static let probe = CatalogProbe()

    static var isCatalogAccessible: Bool { probe.isAllowed() }

    static func loadCatalog() -> FocusFilterCatalog { probe.read() }

    static func withRequest<Result>(_ body: () throws -> Result) rethrows -> Result {
        try body()
    }
}

private struct Snapshot: Equatable {
    let id: String
    let title: String
    let accountTitle: String?
    let telegramId: Int64?

    init(_ entity: FocusAccountEntity) {
        id = entity.id
        title = entity.title
        accountTitle = nil
        telegramId = entity.telegramUserId
    }

    init(_ entity: FocusFolderEntity) {
        id = entity.id
        title = entity.title
        accountTitle = entity.accountTitle
        telegramId = entity.telegramAccountId
    }

    init(_ entity: FocusChatEntity) {
        id = entity.id
        title = entity.title
        accountTitle = entity.accountTitle
        telegramId = entity.telegramChatId
    }
}

private struct QueryCase {
    let name: String
    let id: String
    let telegramId: String
    let resolve: () async throws -> [Snapshot]
    let suggest: () async throws -> [Snapshot]
    let search: (String) async throws -> [Snapshot]

    static func queries(probe: CatalogProbe?, useDefaultAccess: Bool = false) -> [QueryCase] {
        let accounts: FocusAccountQuery
        let folders: FocusFolderQuery
        let chats: FocusChatQuery
        if let probe {
            if useDefaultAccess {
                accounts = FocusAccountQuery(catalogProvider: { probe.read() })
                folders = FocusFolderQuery(catalogProvider: { probe.read() })
                chats = FocusChatQuery(catalogProvider: { probe.read() })
            } else {
                accounts = FocusAccountQuery(catalogProvider: { probe.read() }, accessAllowed: { probe.isAllowed() })
                folders = FocusFolderQuery(catalogProvider: { probe.read() }, accessAllowed: { probe.isAllowed() })
                chats = FocusChatQuery(catalogProvider: { probe.read() }, accessAllowed: { probe.isAllowed() })
            }
        } else {
            accounts = FocusAccountQuery()
            folders = FocusFolderQuery()
            chats = FocusChatQuery()
        }
        return [
            QueryCase(name: "account", id: "-71", telegramId: "6123456789",
                resolve: { try await accounts.entities(for: ["-71", "-071", "invalid", "9223372036854775808"]).map(Snapshot.init) },
                suggest: { try await accounts.suggestedEntities().map(Snapshot.init) },
                search: { try await accounts.entities(matching: $0).map(Snapshot.init) }),
            QueryCase(name: "folder", id: "-71:7", telegramId: "6123456789",
                resolve: { try await folders.entities(for: ["-71:7", "-071:07", "invalid", "-71:2147483648"]).map(Snapshot.init) },
                suggest: { try await folders.suggestedEntities().map(Snapshot.init) },
                search: { try await folders.entities(matching: $0).map(Snapshot.init) }),
            QueryCase(name: "chat", id: "-71:42", telegramId: "-1001234567",
                resolve: { try await chats.entities(for: ["-71:42", "-071:042", "invalid", "-71:9223372036854775808"]).map(Snapshot.init) },
                suggest: { try await chats.suggestedEntities().map(Snapshot.init) },
                search: { try await chats.entities(matching: $0).map(Snapshot.init) })
        ]
    }
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw Failure(description: message) }
}

private func expectLocked(_ operation: () async throws -> [Snapshot], _ context: String) async throws {
    do {
        _ = try await operation()
        throw Failure(description: "\(context): expected locked error")
    } catch FocusStorageError.locked {
    }
}

private func expectPlaceholder(_ values: [Snapshot], _ query: QueryCase) throws {
    try expect(values.count == 1, "\(query.name): invalid identifiers filtered and normalized duplicates removed")
    guard let value = values.first else { return }
    try expect(value.id == query.id, "\(query.name): saved identifier preserved")
    try expect(value.title == "Unavailable \(query.name)", "\(query.name): catalog title hidden")
    try expect(value.telegramId == nil, "\(query.name): public Telegram ID hidden")
    try expect(value.accountTitle == nil || value.accountTitle == "Unavailable account", "\(query.name): account subtitle hidden")
}

private func testDeniedQueries() async throws {
    let probe = CatalogProbe()
    probe.reset(allowed: false)
    for query in QueryCase.queries(probe: probe) {
        try expectPlaceholder(try await query.resolve(), query)
        try await expectLocked(query.suggest, "\(query.name) suggestions")
        for search in ["Private", query.telegramId, "", " \n\t"] {
            try await expectLocked({ try await query.search(search) }, "\(query.name) search \(search)")
        }
    }
    try expect(probe.counts.reads == 0, "denied query routes never read the catalog")
}

private func testAllowedQueries() async throws {
    let probe = CatalogProbe()
    probe.reset(allowed: true)
    FocusIntentStorage.probe.reset(allowed: true)
    for query in QueryCase.queries(probe: probe) {
        let resolved = try await query.resolve()
        try expect(resolved.count == 1 && resolved[0].id == query.id, "\(query.name) resolution")
        try expect(resolved[0].title == "Private \(query.name)", "\(query.name) title")
        try expect(String(resolved[0].telegramId ?? 0) == query.telegramId, "\(query.name) public ID")
        try expect(try await query.suggest() == resolved, "\(query.name) suggestions")
        for search in ["private", query.telegramId, "", " \n\t"] {
            try expect(try await query.search(search) == resolved, "\(query.name) matching \(search)")
        }
        try expect(try await query.search("no matching entity").isEmpty, "\(query.name) nonmatching search")
        if query.name != "account" {
            try expect(resolved[0].accountTitle == "Private account (6123456789)", "\(query.name) account display title")
            try expect(try await query.search("Private account") == resolved, "\(query.name) search by account title")
        }
    }
    try expect(FocusIntentStorage.probe.counts.checks == 0, "projection must not perform live display permission checks per row")
}

private func testRevokedQueries() async throws {
    let probe = CatalogProbe()
    for revokeDuringRead in [true, false] {
        for query in QueryCase.queries(probe: probe) {
            func allowUntilRevocation() {
                probe.reset(allowed: true, remainingChecks: revokeDuringRead ? nil : 2, revokeOnRead: revokeDuringRead)
            }
            allowUntilRevocation()
            try expectPlaceholder(try await query.resolve(), query)
            try expect(probe.counts.reads == 1, "\(query.name) resolution reads before revocation")
            allowUntilRevocation()
            try await expectLocked(query.suggest, "\(query.name) suggestions revoked")
            try expect(probe.counts.reads == 1, "\(query.name) suggestions read before revocation")
            for search in ["Private", ""] {
                allowUntilRevocation()
                try await expectLocked({ try await query.search(search) }, "\(query.name) search revoked")
                try expect(probe.counts.reads == 1, "\(query.name) search reads before revocation")
            }
            probe.reset(allowed: true)
            let recovered = try await query.suggest()
            try expect(recovered.first?.title == "Private \(query.name)", "\(query.name) restores after unlocking")
        }
    }
}

private func testDefaultAccessWiring() async throws {
    let provider = CatalogProbe()
    for queries in [QueryCase.queries(probe: nil), QueryCase.queries(probe: provider, useDefaultAccess: true)] {
        FocusIntentStorage.probe.reset(allowed: false)
        provider.reset(allowed: true)
        for query in queries {
            try expectPlaceholder(try await query.resolve(), query)
            try await expectLocked(query.suggest, "default \(query.name) suggestions")
            try await expectLocked({ try await query.search("") }, "default \(query.name) blank search")
        }
        try expect(FocusIntentStorage.probe.counts.reads == 0, "default storage not read while locked")
        try expect(provider.counts.reads == 0, "injected catalog with default access not read while locked")
        FocusIntentStorage.probe.reset(allowed: true)
        for query in queries {
            let recovered = try await query.suggest()
            try expect(recovered.first?.title == "Private \(query.name)", "default \(query.name) unlock restores catalog")
        }
    }
}

private func testExistingDisplayRedaction() async throws {
    FocusIntentStorage.probe.reset(allowed: true)
    let account = try await FocusAccountQuery().suggestedEntities()[0]
    let folder = try await FocusFolderQuery().suggestedEntities()[0]
    let chat = try await FocusChatQuery().suggestedEntities()[0]
    let accountHash = account.hashValue
    let folderHash = folder.hashValue
    let chatHash = chat.hashValue
    try expect(account.displayRepresentation.title == "Private account (6123456789)", "unlocked account display")
    try expect(folder.displayRepresentation.subtitle == "Private account (6123456789)", "unlocked folder subtitle")
    try expect(chat.displayRepresentation.title == "Private chat (-1001234567)", "unlocked chat display")
    FocusIntentStorage.probe.reset(allowed: false)
    let displays = [account.displayRepresentation, folder.displayRepresentation, chat.displayRepresentation]
    for (display, expected) in zip(displays, ["Locked account", "Locked folder", "Locked chat"]) {
        try expect(display.title == expected && display.subtitle == nil, "existing entity redacts titles, public IDs and subtitle on lock")
    }
    let restoredAccount = try await FocusAccountQuery().entities(for: [account.id])[0]
    let restoredFolder = try await FocusFolderQuery().entities(for: [folder.id])[0]
    let restoredChat = try await FocusChatQuery().entities(for: [chat.id])[0]
    try expect(account == restoredAccount && accountHash == restoredAccount.hashValue, "account identity stable when locked")
    try expect(folder == restoredFolder && folderHash == restoredFolder.hashValue, "folder identity stable when locked")
    try expect(chat == restoredChat && chatHash == restoredChat.hashValue, "chat identity stable when locked")
    try expect(FocusIntentStorage.probe.counts.reads == 0, "display redaction and saved IDs do not read catalog")
    FocusIntentStorage.probe.reset(allowed: true)
    try expect(account.displayRepresentation.title == "Private account (6123456789)", "existing account display restores after unlock")
    try expect(folder.displayRepresentation.title == "Private folder", "existing folder display restores after unlock")
    try expect(chat.displayRepresentation.subtitle == "Private account (6123456789)", "existing chat subtitle restores after unlock")
}

@main
private enum FocusCatalogQueryTests {
    static func main() async throws {
        try await testDeniedQueries()
        try await testAllowedQueries()
        try await testRevokedQueries()
        try await testDefaultAccessWiring()
        try await testExistingDisplayRedaction()
        print("PASS: production catalog queries, search, revocation, live display redaction and stable saved IDs (AppIntents fixture)")
    }
}
