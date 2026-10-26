import AppIntents
import FocusFilterCore
import Foundation

enum FocusIntentStorage {
    static func store() throws -> FocusFilterStore {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw FocusStorageError.unavailable
        }
        let source = Bundle.main.object(forInfoDictionaryKey: "SOURCE") as? String
        let channel: String
        switch source {
        case "DEBUG": channel = "debug"
        case "STABLE": channel = "stable"
        case "APP_STORE": channel = "appstore"
        default: channel = "beta"
        }
        let store = FocusFilterStore.shared
        store.configure(directory: container.appendingPathComponent(channel).appendingPathComponent("FocusFilters"), notificationName: "\(group).FocusFilters.\(channel)")
        store.reload()
        return store
    }

    static var catalog: FocusFilterCatalog {
        (try? store().policy.catalog) ?? .init()
    }

    static func accountTitle(_ accountId: Int64, in catalog: FocusFilterCatalog) -> String {
        catalog.accounts.first(where: { $0.id == accountId })?.title ?? String(localized: "Unavailable account")
    }
}

enum FocusStorageError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "Open Telegram once to prepare its Focus filters. The app and extension must share the same App Group.")
    }
}

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
    func entities(for identifiers: [String]) async throws -> [FocusAccountEntity] {
        let catalog = FocusIntentStorage.catalog
        return identifiers.compactMap { id in
            guard let accountId = Int64(id) else { return nil }
            return FocusAccountEntity(id: id, title: FocusIntentStorage.accountTitle(accountId, in: catalog))
        }
    }

    func suggestedEntities() async throws -> [FocusAccountEntity] {
        FocusIntentStorage.catalog.accounts.map { FocusAccountEntity(id: String($0.id), title: $0.title) }
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
    func entities(for identifiers: [String]) async throws -> [FocusFolderEntity] {
        let catalog = FocusIntentStorage.catalog
        return identifiers.compactMap { rawValue in
            guard let id = FocusFolderIdentifier(rawValue: rawValue) else { return nil }
            let title = catalog.folders.first(where: { $0.id == id })?.title ?? String(localized: "Unavailable folder")
            return FocusFolderEntity(id: rawValue, title: title, accountTitle: FocusIntentStorage.accountTitle(id.accountId, in: catalog))
        }
    }

    func suggestedEntities() async throws -> [FocusFolderEntity] {
        let catalog = FocusIntentStorage.catalog
        return catalog.folders.map {
            FocusFolderEntity(id: $0.id.rawValue, title: $0.title, accountTitle: FocusIntentStorage.accountTitle($0.id.accountId, in: catalog))
        }
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
    func entities(for identifiers: [String]) async throws -> [FocusChatEntity] {
        let catalog = FocusIntentStorage.catalog
        return identifiers.compactMap { rawValue in
            guard let id = FocusChatIdentifier(rawValue: rawValue) else { return nil }
            let title = catalog.chats.first(where: { $0.id == id })?.title ?? String(localized: "Unavailable chat")
            return FocusChatEntity(id: rawValue, title: title, accountTitle: FocusIntentStorage.accountTitle(id.accountId, in: catalog))
        }
    }

    func suggestedEntities() async throws -> [FocusChatEntity] {
        let catalog = FocusIntentStorage.catalog
        return catalog.chats.map {
            FocusChatEntity(id: $0.id.rawValue, title: $0.title, accountTitle: FocusIntentStorage.accountTitle($0.id.accountId, in: catalog))
        }
    }

    func entities(matching string: String) async throws -> [FocusChatEntity] {
        try await suggestedEntities().filter {
            $0.title.localizedStandardContains(string) || $0.accountTitle.localizedStandardContains(string)
        }
    }
}

enum FocusEffectParameter: String, AppEnum {
    case notifications
    case chatList
    case both

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Filter Effect")
    static let caseDisplayRepresentations: [FocusEffectParameter: DisplayRepresentation] = [
        .notifications: "Notifications Only",
        .chatList: "Chat List Only",
        .both: "Notifications and Chat List"
    ]
}

enum FocusModeParameter: String, AppEnum {
    case allowSelected
    case excludeSelected

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Selection Rule")
    static let caseDisplayRepresentations: [FocusModeParameter: DisplayRepresentation] = [
        .allowSelected: "Allow Selected",
        .excludeSelected: "Exclude Selected"
    ]
}

struct TelegramFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Filter Chats and Notifications"
    static let description = IntentDescription("Choose the Telegram accounts to filter. Other accounts keep working normally. Selected folders and individual chats are combined. An empty selection allows no chats with Allow Selected, and excludes no chats with Exclude Selected. Existing notification settings still apply.")

    @Parameter(title: "Accounts", description: "Apply the rule only to these accounts. Leave empty to keep all accounts unchanged.")
    var accounts: [FocusAccountEntity]?

    @Parameter(title: "Effect", default: .notifications)
    var effect: FocusEffectParameter

    @Parameter(title: "Rule", default: .allowSelected)
    var mode: FocusModeParameter

    @Parameter(title: "Folders", description: "Include the current chats in these folders.")
    var folders: [FocusFolderEntity]?

    @Parameter(title: "Chats", description: "Choose individual private chats, groups, or channels in addition to folders.")
    var chats: [FocusChatEntity]?

    var configuration: FocusFilterConfiguration {
        FocusFilterConfiguration(
            accountIds: Set((accounts ?? []).compactMap { Int64($0.id) }),
            chatIds: Set((chats ?? []).compactMap { FocusChatIdentifier(rawValue: $0.id) }),
            folderIds: Set((folders ?? []).compactMap { FocusFolderIdentifier(rawValue: $0.id) }),
            mode: FocusFilterMode(rawValue: mode.rawValue) ?? .allowSelected,
            effect: FocusFilterEffect(rawValue: effect.rawValue) ?? .notifications
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Filter Telegram", subtitle: "\((accounts ?? []).map(\.title).joined(separator: ", "))")
    }

    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: FocusFilterPolicy(configuration: configuration).notificationPredicate)
    }

    func perform() async throws -> some IntentResult {
        try FocusIntentStorage.store().updateConfiguration(configuration)
        return .result()
    }
}
