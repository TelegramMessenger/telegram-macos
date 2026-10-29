import AppIntents
import FocusFilterCore
import Foundation

struct FocusAccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Account")
    static let defaultQuery = FocusAccountQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
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
        try await suggestedEntities().filter { $0.title.localizedStandardContains(string) }
    }
}

struct FocusFolderEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Folder")
    static let defaultQuery = FocusFolderQuery()

    let id: String
    let title: String
    let accountTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(accountTitle)")
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
            $0.title.localizedStandardContains(string) || $0.accountTitle.localizedStandardContains(string)
        }
    }
}

struct FocusChatEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Telegram Chat")
    static let defaultQuery = FocusChatQuery()

    let id: String
    let title: String
    let accountTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(accountTitle)")
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
            $0.title.localizedStandardContains(string) || $0.accountTitle.localizedStandardContains(string)
        }
    }
}

private struct FocusEntityCatalog {
    let catalog: FocusFilterCatalog

    init(_ catalog: FocusFilterCatalog) {
        self.catalog = catalog
    }

    var accounts: [FocusAccountEntity] {
        catalog.accounts.map { FocusAccountEntity(id: String($0.id), title: $0.title) }
    }

    func accounts(for identifiers: [String]) -> [FocusAccountEntity] {
        identifiers.compactMap { rawValue in
            guard let accountId = Int64(rawValue) else { return nil }
            return FocusAccountEntity(id: rawValue, title: accountTitle(accountId))
        }
    }

    var folders: [FocusFolderEntity] {
        catalog.folders.map {
            FocusFolderEntity(id: $0.id.rawValue, title: $0.title, accountTitle: accountTitle($0.id.accountId))
        }
    }

    func folders(for identifiers: [String]) -> [FocusFolderEntity] {
        identifiers.compactMap { rawValue in
            guard let id = FocusFolderIdentifier(rawValue: rawValue) else { return nil }
            let title = catalog.folders.first(where: { $0.id == id })?.title ?? String(localized: "Unavailable folder")
            return FocusFolderEntity(id: rawValue, title: title, accountTitle: accountTitle(id.accountId))
        }
    }

    var chats: [FocusChatEntity] {
        catalog.chats.map {
            FocusChatEntity(id: $0.id.rawValue, title: $0.title, accountTitle: accountTitle($0.id.accountId))
        }
    }

    func chats(for identifiers: [String]) -> [FocusChatEntity] {
        identifiers.compactMap { rawValue in
            guard let id = FocusChatIdentifier(rawValue: rawValue) else { return nil }
            let title = catalog.chats.first(where: { $0.id == id })?.title ?? String(localized: "Unavailable chat")
            return FocusChatEntity(id: rawValue, title: title, accountTitle: accountTitle(id.accountId))
        }
    }

    private func accountTitle(_ accountId: Int64) -> String {
        catalog.accounts.first(where: { $0.id == accountId })?.title ?? String(localized: "Unavailable account")
    }
}
