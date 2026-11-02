import Cocoa
import TGUIKit
import TelegramContext
import InAppSettings
import TelegramCore

struct SettingsSearchEnvironment {
    let privacySettings: AccountPrivacySettings?
}

protocol SettingsSearchTag: CaseIterable {
    static var icon: SettingsSearchableItemIcon { get }
    static var rootTitle: String { get }
    static var rootAlternates: [String] { get }
    static func itemId(_ index: Int32) -> SettingsSearchableItemId
    static func open<Context: AccountContextProtocol>(_ tag: Self?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void)
    var searchTitle: String { get }
    var searchAlternates: [String] { get }
    var searchIndex: Int32 { get }
}

extension SettingsSearchTag {
    static var rootAlternates: [String] {
        return []
    }
    
    var searchAlternates: [String] {
        return []
    }
}

func searchableItems<Tag: SettingsSearchTag, Context: AccountContextProtocol>(_ type: Tag.Type, context: Context, environment: SettingsSearchEnvironment) -> [SettingsSearchableItem<Context>] {
    var items = [SettingsSearchableItem<Context>(id: Tag.itemId(0), title: Tag.rootTitle, alternate: Tag.rootAlternates, icon: Tag.icon, breadcrumbs: [], present: { context, navigation, present in
        Tag.open(nil, context: context, navigation: navigation, environment: environment, present: present)
    })]
    for tag in Tag.allCases {
        items.append(SettingsSearchableItem<Context>(id: Tag.itemId(tag.searchIndex), title: tag.searchTitle, alternate: tag.searchAlternates, icon: Tag.icon, breadcrumbs: [Tag.rootTitle], present: { context, navigation, present in
            Tag.open(tag, context: context, navigation: navigation, environment: environment, present: present)
        }))
    }
    return items
}
