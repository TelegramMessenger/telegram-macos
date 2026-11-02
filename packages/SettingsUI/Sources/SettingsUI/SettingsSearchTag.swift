import Cocoa
import TGUIKit
import TelegramContext
import InAppSettings

protocol SettingsSearchTag: CaseIterable {
    static var icon: SettingsSearchableItemIcon { get }
    static var rootTitle: String { get }
    static func itemId(_ index: Int32) -> SettingsSearchableItemId
    static func open<Context: AccountContextProtocol>(_ tag: Self?, context: Context, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void)
    var searchTitle: String { get }
    var searchIndex: Int32 { get }
}

func searchableItems<Tag: SettingsSearchTag, Context: AccountContextProtocol>(_ type: Tag.Type, context: Context) -> [SettingsSearchableItem<Context>] {
    var items = [SettingsSearchableItem<Context>(id: Tag.itemId(0), title: Tag.rootTitle, alternate: [], icon: Tag.icon, breadcrumbs: [], present: { context, _, present in
        Tag.open(nil, context: context, present: present)
    })]
    for tag in Tag.allCases {
        items.append(SettingsSearchableItem<Context>(id: Tag.itemId(tag.searchIndex), title: tag.searchTitle, alternate: [], icon: Tag.icon, breadcrumbs: [Tag.rootTitle], present: { context, _, present in
            Tag.open(tag, context: context, present: present)
        }))
    }
    return items
}
