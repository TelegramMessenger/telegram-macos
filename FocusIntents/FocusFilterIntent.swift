import AppIntents
import FocusFilterCore
import FocusFilterInfrastructure
import Foundation

enum FocusEffectParameter: String, AppEnum {
    case notifications
    case chatList
    case both

    var filterEffect: FocusFilterEffect {
        switch self {
        case .notifications: return .notifications
        case .chatList: return .chatList
        case .both: return .both
        }
    }

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

    var filterMode: FocusFilterMode {
        switch self {
        case .allowSelected: return .allowSelected
        case .excludeSelected: return .excludeSelected
        }
    }

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
    var accounts: Set<FocusAccountEntity>?

    @Parameter(title: "Effect", default: .notifications)
    var effect: FocusEffectParameter

    @Parameter(title: "Rule", default: .allowSelected)
    var mode: FocusModeParameter

    @Parameter(title: "Folders", description: "Include the current chats in these folders.")
    var folders: Set<FocusFolderEntity>?

    @Parameter(title: "Chats", description: "Choose individual private chats, groups, or channels in addition to folders.")
    var chats: Set<FocusChatEntity>?

    var configuration: FocusFilterConfiguration {
        FocusFilterConfiguration(
            accountIds: Set((accounts ?? []).compactMap { Int64($0.id) }),
            chatIds: Set((chats ?? []).compactMap { FocusChatIdentifier(rawValue: $0.id) }),
            folderIds: Set((folders ?? []).compactMap { FocusFolderIdentifier(rawValue: $0.id) }),
            mode: mode.filterMode,
            effect: effect.filterEffect
        )
    }

    var displayRepresentation: DisplayRepresentation {
        let accountTitles = (accounts ?? []).sorted { $0.id < $1.id }.map {
            String(localized: $0.displayRepresentation.title)
        }
        return DisplayRepresentation(title: "Filter Telegram", subtitle: "\(accountTitles.joined(separator: ", "))")
    }

    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: FocusNotificationFilter(configuration: configuration).predicate)
    }

    func perform() async throws -> some IntentResult {
        try FocusIntentStorage.store().updateConfiguration(configuration)
        return .result()
    }
}
