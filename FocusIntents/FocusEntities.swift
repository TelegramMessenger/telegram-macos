import AppIntents
import FocusFilterCore
import Foundation

struct FocusAccountEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Account")
    static let defaultQuery = FocusAccountQuery()

    let id: String
    let title: String
    let telegramUserId: Int64?

    init(id: String, title: String, telegramUserId: Int64? = nil) {
        self.id = id
        self.title = title
        self.telegramUserId = telegramUserId
    }

    static func == (lhs: FocusAccountEntity, rhs: FocusAccountEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayRepresentation: DisplayRepresentation {
        guard FocusIntentStorage.isCatalogAccessible else {
            return DisplayRepresentation(title: "Locked account")
        }
        return DisplayRepresentation(title: focusAccountDisplayTitle(title, telegramUserId: telegramUserId))
    }
}

struct FocusAccountQuery: EntityStringQuery {
    private let catalogAccess: FocusEntityCatalogAccess

    init() {
        self.init(catalogProvider: { FocusIntentStorage.loadCatalog() })
    }

    init(catalogProvider: @escaping @Sendable () -> FocusFilterCatalog, accessAllowed: @escaping @Sendable () -> Bool = { FocusIntentStorage.isCatalogAccessible }) {
        self.catalogAccess = FocusEntityCatalogAccess(catalogProvider: catalogProvider, accessAllowed: accessAllowed)
    }

    func entities(for identifiers: [String]) async throws -> [FocusAccountEntity] {
        FocusIntentStorage.withRequest {
            catalogAccess.resolve { $0.accounts(for: identifiers) }
        }
    }

    func suggestedEntities() async throws -> [FocusAccountEntity] {
        try FocusIntentStorage.withRequest {
            try catalogAccess.browse { $0.accounts }
        }
    }

    func entities(matching string: String) async throws -> [FocusAccountEntity] {
        try FocusIntentStorage.withRequest {
            try catalogAccess.browse { catalog in
                let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let entities = catalog.accounts
                guard !search.isEmpty else { return entities }
                return entities.filter {
                    $0.title.localizedStandardContains(search)
                    || $0.telegramUserId.map { String($0).localizedStandardContains(search) } == true
                }
            }
        }
    }
}

struct FocusFolderEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Folder")
    static let defaultQuery = FocusFolderQuery()

    let id: String
    let title: String
    let accountTitle: String
    let telegramAccountId: Int64?

    init(id: String, title: String, accountTitle: String, telegramAccountId: Int64? = nil) {
        self.id = id
        self.title = title
        self.accountTitle = accountTitle
        self.telegramAccountId = telegramAccountId
    }

    static func == (lhs: FocusFolderEntity, rhs: FocusFolderEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayRepresentation: DisplayRepresentation {
        guard FocusIntentStorage.isCatalogAccessible else {
            return DisplayRepresentation(title: "Locked folder")
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(accountTitle)")
    }
}

struct FocusFolderQuery: EntityStringQuery {
    private let catalogAccess: FocusEntityCatalogAccess

    init() {
        self.init(catalogProvider: { FocusIntentStorage.loadCatalog() })
    }

    init(catalogProvider: @escaping @Sendable () -> FocusFilterCatalog, accessAllowed: @escaping @Sendable () -> Bool = { FocusIntentStorage.isCatalogAccessible }) {
        self.catalogAccess = FocusEntityCatalogAccess(catalogProvider: catalogProvider, accessAllowed: accessAllowed)
    }

    func entities(for identifiers: [String]) async throws -> [FocusFolderEntity] {
        FocusIntentStorage.withRequest {
            catalogAccess.resolve { $0.folders(for: identifiers) }
        }
    }

    func suggestedEntities() async throws -> [FocusFolderEntity] {
        try FocusIntentStorage.withRequest {
            try catalogAccess.browse { $0.folders }
        }
    }

    func entities(matching string: String) async throws -> [FocusFolderEntity] {
        try FocusIntentStorage.withRequest {
            try catalogAccess.browse { catalog in
                let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let entities = catalog.folders
                guard !search.isEmpty else { return entities }
                return entities.filter {
                    $0.title.localizedStandardContains(search)
                    || $0.telegramAccountId.map { String($0).localizedStandardContains(search) } == true
                    || $0.accountTitle.localizedStandardContains(search)
                }
            }
        }
    }
}

struct FocusChatEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Chat")
    static let defaultQuery = FocusChatQuery()

    let id: String
    let title: String
    let accountTitle: String
    let telegramChatId: Int64?

    init(id: String, title: String, accountTitle: String, telegramChatId: Int64? = nil) {
        self.id = id
        self.title = title
        self.accountTitle = accountTitle
        self.telegramChatId = telegramChatId
    }

    static func == (lhs: FocusChatEntity, rhs: FocusChatEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayRepresentation: DisplayRepresentation {
        guard FocusIntentStorage.isCatalogAccessible else {
            return DisplayRepresentation(title: "Locked chat")
        }
        if let telegramChatId {
            return DisplayRepresentation(title: "\(title) (\(String(telegramChatId)))", subtitle: "\(accountTitle)")
        }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(accountTitle)")
    }
}

struct FocusChatQuery: EntityStringQuery {
    private let catalogAccess: FocusEntityCatalogAccess

    init() {
        self.init(catalogProvider: { FocusIntentStorage.loadCatalog() })
    }

    init(catalogProvider: @escaping @Sendable () -> FocusFilterCatalog, accessAllowed: @escaping @Sendable () -> Bool = { FocusIntentStorage.isCatalogAccessible }) {
        self.catalogAccess = FocusEntityCatalogAccess(catalogProvider: catalogProvider, accessAllowed: accessAllowed)
    }

    func entities(for identifiers: [String]) async throws -> [FocusChatEntity] {
        FocusIntentStorage.withRequest {
            catalogAccess.resolve { $0.chats(for: identifiers) }
        }
    }

    func suggestedEntities() async throws -> [FocusChatEntity] {
        try FocusIntentStorage.withRequest {
            try catalogAccess.browse { $0.chats }
        }
    }

    func entities(matching string: String) async throws -> [FocusChatEntity] {
        try FocusIntentStorage.withRequest {
            try catalogAccess.browse { catalog in
                let search = string.trimmingCharacters(in: .whitespacesAndNewlines)
                let entities = catalog.chats
                guard !search.isEmpty else { return entities }
                return entities.filter {
                    $0.title.localizedStandardContains(search)
                    || $0.telegramChatId.map { String($0).localizedStandardContains(search) } == true
                    || $0.accountTitle.localizedStandardContains(search)
                }
            }
        }
    }
}

private struct FocusEntityCatalogAccess {
    let catalogProvider: @Sendable () -> FocusFilterCatalog
    let accessAllowed: @Sendable () -> Bool

    func resolve<Result>(_ projection: (FocusEntityCatalog) -> Result) -> Result {
        guard accessAllowed() else {
            return projection(FocusEntityCatalog(FocusFilterCatalog()))
        }
        let catalog = catalogProvider()
        guard accessAllowed() else {
            return projection(FocusEntityCatalog(FocusFilterCatalog()))
        }
        let result = projection(FocusEntityCatalog(catalog))
        guard accessAllowed() else {
            return projection(FocusEntityCatalog(FocusFilterCatalog()))
        }
        return result
    }

    func browse<Result>(_ projection: (FocusEntityCatalog) -> Result) throws -> Result {
        guard accessAllowed() else { throw FocusStorageError.locked }
        let catalog = catalogProvider()
        guard accessAllowed() else { throw FocusStorageError.locked }
        let result = projection(FocusEntityCatalog(catalog))
        guard accessAllowed() else { throw FocusStorageError.locked }
        return result
    }
}

private struct FocusEntityCatalog {
    let catalog: FocusFilterCatalog

    init(_ catalog: FocusFilterCatalog) {
        self.catalog = catalog
    }

    var accounts: [FocusAccountEntity] {
        uniqueEntities(catalog.accounts.map {
            FocusAccountEntity(id: String($0.id), title: $0.title, telegramUserId: $0.telegramUserId)
        })
    }

    func accounts(for identifiers: [String]) -> [FocusAccountEntity] {
        uniqueEntities(identifiers.compactMap { rawValue in
            guard let accountId = Int64(rawValue) else { return nil }
            let account = catalog.accounts.first { $0.id == accountId }
            let title = account?.title ?? String(localized: "Unavailable account")
            return FocusAccountEntity(id: String(accountId), title: title, telegramUserId: account?.telegramUserId)
        })
    }

    var folders: [FocusFolderEntity] {
        uniqueEntities(catalog.folders.map {
            FocusFolderEntity(id: $0.id.rawValue, title: $0.title, accountTitle: accountTitle($0.id.accountId), telegramAccountId: accountUserId($0.id.accountId))
        })
    }

    func folders(for identifiers: [String]) -> [FocusFolderEntity] {
        uniqueEntities(identifiers.compactMap { rawValue in
            guard let id = FocusFolderIdentifier(rawValue: rawValue) else { return nil }
            let title = catalog.folders.first(where: { $0.id == id })?.title ?? String(localized: "Unavailable folder")
            return FocusFolderEntity(id: id.rawValue, title: title, accountTitle: accountTitle(id.accountId), telegramAccountId: accountUserId(id.accountId))
        })
    }

    var chats: [FocusChatEntity] {
        uniqueEntities(catalog.chats.map {
            FocusChatEntity(id: $0.id.rawValue, title: $0.title, accountTitle: accountTitle($0.id.accountId), telegramChatId: $0.telegramChatId)
        })
    }

    func chats(for identifiers: [String]) -> [FocusChatEntity] {
        uniqueEntities(identifiers.compactMap { rawValue in
            guard let id = FocusChatIdentifier(rawValue: rawValue) else { return nil }
            let chat = catalog.chats.first(where: { $0.id == id })
            let title = chat?.title ?? String(localized: "Unavailable chat")
            return FocusChatEntity(id: id.rawValue, title: title, accountTitle: accountTitle(id.accountId), telegramChatId: chat?.telegramChatId)
        })
    }

    private func uniqueEntities<Entity: AppEntity>(_ entities: [Entity]) -> [Entity] {
        var identifiers = Set<Entity.ID>()
        return entities.filter { identifiers.insert($0.id).inserted }
    }

    private func accountUserId(_ accountId: Int64) -> Int64? {
        catalog.accounts.first(where: { $0.id == accountId })?.telegramUserId
    }

    private func accountTitle(_ accountId: Int64) -> String {
        guard let account = catalog.accounts.first(where: { $0.id == accountId }) else {
            return String(localized: "Unavailable account")
        }
        return String(localized: focusAccountDisplayTitle(account.title, telegramUserId: account.telegramUserId))
    }
}

private func focusAccountDisplayTitle(_ title: String, telegramUserId: Int64?) -> LocalizedStringResource {
    if let telegramUserId {
        return "\(title) (\(String(telegramUserId)))"
    }
    return "\(title)"
}
