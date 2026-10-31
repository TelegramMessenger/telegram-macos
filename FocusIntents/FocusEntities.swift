import AppIntents
import FocusFilterCore
import Foundation

struct FocusAccountEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Account")
    static let defaultQuery = FocusAccountQuery()

    let id: String
    let title: String

    static func == (lhs: FocusAccountEntity, rhs: FocusAccountEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title) (ID: \(id))")
    }
}

struct FocusAccountQuery: EntityStringQuery {
    private let catalogProvider: @Sendable () -> FocusFilterCatalog

    init() {
        self.init(catalogProvider: { FocusIntentStorage.loadCatalog() })
    }

    init(catalogProvider: @escaping @Sendable () -> FocusFilterCatalog) {
        self.catalogProvider = catalogProvider
    }

    func entities(for identifiers: [String]) async throws -> [FocusAccountEntity] {
        FocusEntityCatalog(catalogProvider()).accounts(for: identifiers)
    }

    func suggestedEntities() async throws -> [FocusAccountEntity] {
        FocusEntityCatalog(catalogProvider()).accounts
    }

    func entities(matching string: String) async throws -> [FocusAccountEntity] {
        try await suggestedEntities().filter {
            $0.title.localizedStandardContains(string) || $0.id.localizedStandardContains(string)
        }
    }
}

struct FocusFolderEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Folder")
    static let defaultQuery = FocusFolderQuery()

    let id: String
    let title: String
    let accountTitle: String

    static func == (lhs: FocusFolderEntity, rhs: FocusFolderEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title) (ID: \(id))", subtitle: "\(accountTitle)")
    }
}

struct FocusFolderQuery: EntityStringQuery {
    private let catalogProvider: @Sendable () -> FocusFilterCatalog

    init() {
        self.init(catalogProvider: { FocusIntentStorage.loadCatalog() })
    }

    init(catalogProvider: @escaping @Sendable () -> FocusFilterCatalog) {
        self.catalogProvider = catalogProvider
    }

    func entities(for identifiers: [String]) async throws -> [FocusFolderEntity] {
        FocusEntityCatalog(catalogProvider()).folders(for: identifiers)
    }

    func suggestedEntities() async throws -> [FocusFolderEntity] {
        FocusEntityCatalog(catalogProvider()).folders
    }

    func entities(matching string: String) async throws -> [FocusFolderEntity] {
        try await suggestedEntities().filter {
            $0.title.localizedStandardContains(string)
                || $0.id.localizedStandardContains(string)
                || $0.accountTitle.localizedStandardContains(string)
        }
    }
}

struct FocusChatEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Chat")
    static let defaultQuery = FocusChatQuery()

    let id: String
    let title: String
    let accountTitle: String

    static func == (lhs: FocusChatEntity, rhs: FocusChatEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title) (ID: \(id))", subtitle: "\(accountTitle)")
    }
}

struct FocusChatQuery: EntityStringQuery {
    private let catalogProvider: @Sendable () -> FocusFilterCatalog

    init() {
        self.init(catalogProvider: { FocusIntentStorage.loadCatalog() })
    }

    init(catalogProvider: @escaping @Sendable () -> FocusFilterCatalog) {
        self.catalogProvider = catalogProvider
    }

    func entities(for identifiers: [String]) async throws -> [FocusChatEntity] {
        FocusEntityCatalog(catalogProvider()).chats(for: identifiers)
    }

    func suggestedEntities() async throws -> [FocusChatEntity] {
        FocusEntityCatalog(catalogProvider()).chats
    }

    func entities(matching string: String) async throws -> [FocusChatEntity] {
        try await suggestedEntities().filter {
            $0.title.localizedStandardContains(string)
                || $0.id.localizedStandardContains(string)
                || $0.accountTitle.localizedStandardContains(string)
        }
    }
}

private struct FocusEntityCatalog {
    let catalog: FocusFilterCatalog

    init(_ catalog: FocusFilterCatalog) {
        self.catalog = catalog
    }

    var accounts: [FocusAccountEntity] {
        uniqueEntities(catalog.accounts.map { FocusAccountEntity(id: String($0.id), title: $0.title) })
    }

    func accounts(for identifiers: [String]) -> [FocusAccountEntity] {
        uniqueEntities(identifiers.compactMap { rawValue in
            guard let accountId = Int64(rawValue) else { return nil }
            return FocusAccountEntity(id: String(accountId), title: accountTitle(accountId))
        })
    }

    var folders: [FocusFolderEntity] {
        uniqueEntities(catalog.folders.map {
            FocusFolderEntity(id: $0.id.rawValue, title: $0.title, accountTitle: accountTitle($0.id.accountId))
        })
    }

    func folders(for identifiers: [String]) -> [FocusFolderEntity] {
        uniqueEntities(identifiers.compactMap { rawValue in
            guard let id = FocusFolderIdentifier(rawValue: rawValue) else { return nil }
            let title = catalog.folders.first(where: { $0.id == id })?.title ?? String(localized: "Unavailable folder")
            return FocusFolderEntity(id: id.rawValue, title: title, accountTitle: accountTitle(id.accountId))
        })
    }

    var chats: [FocusChatEntity] {
        uniqueEntities(catalog.chats.map {
            FocusChatEntity(id: $0.id.rawValue, title: $0.title, accountTitle: accountTitle($0.id.accountId))
        })
    }

    func chats(for identifiers: [String]) -> [FocusChatEntity] {
        uniqueEntities(identifiers.compactMap { rawValue in
            guard let id = FocusChatIdentifier(rawValue: rawValue) else { return nil }
            let title = catalog.chats.first(where: { $0.id == id })?.title ?? String(localized: "Unavailable chat")
            return FocusChatEntity(id: id.rawValue, title: title, accountTitle: accountTitle(id.accountId))
        })
    }

    private func uniqueEntities<Entity: AppEntity>(_ entities: [Entity]) -> [Entity] {
        var identifiers = Set<Entity.ID>()
        return entities.filter { identifiers.insert($0.id).inserted }
    }

    private func accountTitle(_ accountId: Int64) -> String {
        catalog.accounts.first(where: { $0.id == accountId })?.title ?? String(localized: "Unavailable account")
    }
}
