import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Localization
import TelegramContext

enum NotificationSearchTag: CaseIterable {
    case messagePreviews
    case includeChannels
    case unreadCount
    case contactJoined
    case reset
    case allAccounts
    case defaultSound
    case category(NotificationSettingsCategory, NotificationCategoryEntryTag?)
    case reactions(ReactionNotificationEntryTag?)
    
    private static let categories: [(NotificationSettingsCategory, Int32)] = [(.privateChats, 30), (.groupChats, 40), (.channels, 50), (.stories, 60)]
    
    private static func categoryRows(_ category: NotificationSettingsCategory) -> [(String, NotificationCategoryEntryTag)] {
        var rows: [(String, NotificationCategoryEntryTag)]
        if case .stories = category {
            rows = [(strings().notificationSettingsStoriesNew, .show), (strings().notificationSettingsStoriesImportant, .important), (strings().notificationSettingsCategoryShowSender, .preview)]
        } else {
            rows = [(strings().notificationSettingsCategoryShowNotifications, .show), (strings().notificationSettingsMessagesPreview, .preview)]
        }
        rows += [(strings().notificationSettingsCategorySound, .sound), (strings().notificationSettingsExceptionsAdd, .addException), (strings().notificationSettingsExceptionsDeleteAll, .deleteExceptions)]
        return rows
    }
    
    private static var reactionRows: [(String, ReactionNotificationEntryTag)] {
        return [(strings().notificationSettingsReactionsMessages, .messages), (strings().notificationSettingsCategoryShowSender, .showSender), (strings().notificationSettingsCategorySound, .sound)]
    }
    
    static var allCases: [NotificationSearchTag] {
        var result: [NotificationSearchTag] = [.messagePreviews, .includeChannels, .unreadCount, .contactJoined, .reset, .allAccounts, .defaultSound]
        for (category, _) in categories {
            result.append(.category(category, nil))
            for row in categoryRows(category) {
                result.append(.category(category, row.1))
            }
        }
        result.append(.reactions(nil))
        for row in reactionRows {
            result.append(.reactions(row.1))
        }
        return result
    }
}

extension NotificationSearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .notifications
    }
    
    static var rootTitle: String {
        return strings().accountSettingsNotifications
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsNotificationsTitle)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .notifications(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: NotificationSearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        let focus: NotificationsAndSoundsEntryTag?
        switch tag {
        case let .category(category, entryTag):
            present(.push, NotificationCategorySettingsController(context: context, category: category, focusOnItemTag: entryTag))
            return
        case let .reactions(entryTag):
            present(.push, ReactionNotificationSettingsController(context: context, focusOnItemTag: entryTag))
            return
        case .messagePreviews:
            focus = .messagePreviews
        case .includeChannels:
            focus = .includeChannels
        case .unreadCount:
            focus = .unreadCountCategory
        case .contactJoined:
            focus = .joinedNotifications
        case .reset:
            focus = .reset
        case .allAccounts:
            focus = .allAccounts
        case .defaultSound:
            focus = .tone
        case nil:
            focus = nil
        }
        present(.push, NotificationPreferencesController(context, focusOnItemTag: focus))
    }
    
    var searchTitle: String {
        switch self {
        case .messagePreviews:
            return strings().notificationSettingsThisDeviceShowMessageText
        case .includeChannels:
            return strings().notificationSettingsIncludeChannels
        case .unreadCount:
            return strings().notificationSettingsCountUnreadMessages
        case .contactJoined:
            return strings().notificationSettingsContactJoined
        case .reset:
            return strings().notificationSettingsResetAll
        case .allAccounts:
            return strings().notificationSettingsAllAccounts
        case .defaultSound:
            return strings().notificationSettingsThisDeviceDefaultSound
        case let .category(category, entryTag):
            guard let entryTag = entryTag else {
                return category.title
            }
            return NotificationSearchTag.categoryRows(category).first(where: { $0.1 == entryTag })?.0 ?? category.title
        case let .reactions(entryTag):
            guard let entryTag = entryTag else {
                return strings().notificationSettingsReactions
            }
            return NotificationSearchTag.reactionRows.first(where: { $0.1 == entryTag })?.0 ?? strings().notificationSettingsReactions
        }
    }
    
    var searchAlternates: [String] {
        switch self {
        case .messagePreviews:
            return synonyms(strings().settingsSearchSynonymsNotificationsMessageNotificationsPreview)
        case .includeChannels:
            return synonyms(strings().settingsSearchSynonymsNotificationsBadgeIncludeMutedChannels)
        case .unreadCount:
            return synonyms(strings().settingsSearchSynonymsNotificationsBadgeCountUnreadMessages)
        case .contactJoined:
            return synonyms(strings().settingsSearchSynonymsNotificationsContactJoined)
        case .reset:
            return synonyms(strings().settingsSearchSynonymsNotificationsResetAllNotifications)
        default:
            return []
        }
    }
    
    var searchBreadcrumbs: [String] {
        let root = strings().accountSettingsNotifications
        switch self {
        case .messagePreviews, .defaultSound:
            return [root, strings().notificationSettingsThisDeviceHeader]
        case .includeChannels, .unreadCount:
            return [root, strings().notificationSettingsBadgeHeader]
        case .contactJoined, .reset, .allAccounts:
            return [root]
        case let .category(category, entryTag):
            return [root, entryTag == nil ? strings().notificationSettingsMessageNotifications : category.title]
        case let .reactions(entryTag):
            return [root, entryTag == nil ? strings().notificationSettingsMessageNotifications : strings().notificationSettingsReactions]
        }
    }
    
    func isAvailable(in environment: SettingsSearchEnvironment) -> Bool {
        if case .allAccounts = self {
            return environment.hasMultipleAccounts
        }
        return true
    }
    
    var searchIndex: Int32 {
        switch self {
        case .messagePreviews:
            return 2
        case .includeChannels:
            return 19
        case .unreadCount:
            return 20
        case .contactJoined:
            return 21
        case .reset:
            return 22
        case .allAccounts:
            return 23
        case .defaultSound:
            return 24
        case let .category(category, entryTag):
            let base: Int32
            switch category {
            case .privateChats:
                base = 30
            case .groupChats:
                base = 40
            case .channels:
                base = 50
            case .stories:
                base = 60
            }
            guard let entryTag = entryTag, let index = NotificationSearchTag.categoryRows(category).firstIndex(where: { $0.1 == entryTag }) else {
                return base
            }
            return base + 1 + Int32(index)
        case let .reactions(entryTag):
            guard let entryTag = entryTag, let index = NotificationSearchTag.reactionRows.firstIndex(where: { $0.1 == entryTag }) else {
                return 70
            }
            return 71 + Int32(index)
        }
    }
}
