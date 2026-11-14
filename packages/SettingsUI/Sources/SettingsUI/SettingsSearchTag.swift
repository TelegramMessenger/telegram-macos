import Cocoa
import TGUIKit
import TelegramContext
import InAppSettings
import TelegramCore

struct SettingsSearchEnvironment {
    var privacySettings: AccountPrivacySettings? = nil
    var canAddAccount: Bool = true
    var hasSocksProxy: Bool = true
    var hasMultipleAccounts: Bool = true
    var predictEmojiVisible: Bool = true
    var canAdjustSensitiveContent: Bool = true
    var passkeysAvailable: Bool = true
    var loginEmailAvailable: Bool = true
    var hasWebSessions: Bool = true
    var secretChatWebPreviewAvailable: Bool = true
    var chatBackgroundAvailable: Bool = true
    var dockIconAvailable: Bool = true
    var liquidGlassAvailable: Bool = true
    var premiumAvailable: Bool = true
    var starsAvailable: Bool = true
    var passportAvailable: Bool = true
}

protocol SettingsSearchTag: CaseIterable {
    static var icon: SettingsSearchableItemIcon { get }
    static var rootTitle: String { get }
    static var rootAlternates: [String] { get }
    static var includesRoot: Bool { get }
    static func itemId(_ index: Int32) -> SettingsSearchableItemId
    static func open<Context: AccountContextProtocol>(_ tag: Self?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void)
    var searchTitle: String { get }
    var searchAlternates: [String] { get }
    var searchIcon: SettingsSearchableItemIcon { get }
    var searchBreadcrumbs: [String] { get }
    func isAvailable(in environment: SettingsSearchEnvironment) -> Bool
    var searchIndex: Int32 { get }
}

extension SettingsSearchTag {
    static var includesRoot: Bool {
        return true
    }
    
    static var rootAlternates: [String] {
        return []
    }
    
    var searchAlternates: [String] {
        return []
    }
    
    var searchIcon: SettingsSearchableItemIcon {
        return Self.icon
    }
    
    var searchBreadcrumbs: [String] {
        return Self.includesRoot ? [Self.rootTitle] : []
    }
    
    func isAvailable(in environment: SettingsSearchEnvironment) -> Bool {
        return true
    }
}

struct SettingsSearchEntry<Tag: SettingsSearchTag> {
    let tag: Tag?
    let id: SettingsSearchableItemId
    let title: String
    let alternate: [String]
    let icon: SettingsSearchableItemIcon
    let breadcrumbs: [String]
}

func searchEntries<Tag: SettingsSearchTag>(_ type: Tag.Type, environment: SettingsSearchEnvironment) -> [SettingsSearchEntry<Tag>] {
    var entries: [SettingsSearchEntry<Tag>] = []
    if Tag.includesRoot {
        entries.append(SettingsSearchEntry<Tag>(tag: nil, id: Tag.itemId(0), title: Tag.rootTitle, alternate: Tag.rootAlternates, icon: Tag.icon, breadcrumbs: []))
    }
    for tag in Tag.allCases where tag.isAvailable(in: environment) {
        entries.append(SettingsSearchEntry<Tag>(tag: tag, id: Tag.itemId(tag.searchIndex), title: tag.searchTitle, alternate: tag.searchAlternates, icon: tag.searchIcon, breadcrumbs: tag.searchBreadcrumbs))
    }
    return entries
}

func searchableItems<Tag: SettingsSearchTag, Context: AccountContextProtocol>(_ type: Tag.Type, context: Context, environment: SettingsSearchEnvironment) -> [SettingsSearchableItem<Context>] {
    return searchEntries(type, environment: environment).map { entry in
        SettingsSearchableItem<Context>(id: entry.id, title: entry.title, alternate: entry.alternate, icon: entry.icon, breadcrumbs: entry.breadcrumbs, present: { context, navigation, present in
            Tag.open(entry.tag, context: context, navigation: navigation, environment: environment, present: present)
        })
    }
}
