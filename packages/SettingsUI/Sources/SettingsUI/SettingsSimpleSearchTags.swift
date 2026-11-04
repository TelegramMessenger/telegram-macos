import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Localization
import TelegramContext

enum ProfileSearchTag: Int32, CaseIterable {
    case bio = 1
    case phoneNumber = 2
    case username = 3
    case addAccount = 4
    case logout = 5
}

extension ProfileSearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .profile
    }
    
    static var rootTitle: String {
        return strings().editAccountTitle
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsEditProfileTitle)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .profile(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: ProfileSearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        switch tag {
        case nil, .bio:
            EditAccountInfoController(context: context, focusOnItemTag: tag == nil ? nil : .bio, f: { controller in
                present(.push, controller)
            })
        case .phoneNumber:
            present(.push, SettingsNavigationHooks.shared.makePhoneNumberIntroController(context))
        case .username:
            present(.push, UsernameController(context))
        case .addAccount:
            let isTestingEnvironment = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            context.sharedContext.beginNewAuth(testingEnvironment: isTestingEnvironment)
        case .logout:
            showModal(with: LogoutViewController(context: context, f: { controller in
                present(.push, controller)
            }), for: context.window)
        }
    }
    
    var searchTitle: String {
        switch self {
        case .bio:
            return strings().accountSettingsBio
        case .phoneNumber:
            return strings().editAccountChangeNumber
        case .username:
            return strings().editAccountUsername
        case .addAccount:
            return strings().editAccountAddAccount
        case .logout:
            return strings().editAccountLogout
        }
    }
    
    var searchAlternates: [String] {
        switch self {
        case .bio:
            return synonyms(strings().settingsSearchSynonymsEditProfileTitle)
        case .phoneNumber:
            return synonyms(strings().settingsSearchSynonymsEditProfilePhoneNumber)
        case .username:
            return synonyms(strings().settingsSearchSynonymsEditProfileUsername)
        case .addAccount:
            return synonyms(strings().settingsSearchSynonymsEditProfileAddAccount)
        case .logout:
            return synonyms(strings().settingsSearchSynonymsEditProfileLogout)
        }
    }
    
    func isAvailable(in environment: SettingsSearchEnvironment) -> Bool {
        if case .addAccount = self {
            return environment.canAddAccount
        }
        return true
    }
    
    var searchIndex: Int32 {
        return rawValue
    }
}

enum StickersSearchTag: Int32, CaseIterable {
    case suggestOptions = 1
    case featuredPacks = 3
    case archivedPacks = 4
}

extension StickersSearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .stickers
    }
    
    static var rootTitle: String {
        return strings().accountSettingsStickers
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsStickersTitle)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .stickers(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: StickersSearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        switch tag {
        case nil:
            present(.push, SettingsNavigationHooks.shared.makeInstalledStickerPacksController(context, nil))
        case .suggestOptions:
            present(.push, SettingsNavigationHooks.shared.makeInstalledStickerPacksController(context, .suggestOptions))
        case .featuredPacks:
            present(.push, SettingsNavigationHooks.shared.makeFeaturedStickerPacksController(context))
        case .archivedPacks:
            present(.push, SettingsNavigationHooks.shared.makeArchivedStickerPacksController(context))
        }
    }
    
    var searchTitle: String {
        switch self {
        case .suggestOptions:
            return strings().stickersSuggestStickers
        case .featuredPacks:
            return strings().installedStickersTranding
        case .archivedPacks:
            return strings().installedStickersArchived
        }
    }
    
    var searchAlternates: [String] {
        switch self {
        case .suggestOptions:
            return synonyms(strings().settingsSearchSynonymsStickersSuggestStickers)
        case .featuredPacks:
            return synonyms(strings().settingsSearchSynonymsStickersFeaturedPacks)
        case .archivedPacks:
            return synonyms(strings().settingsSearchSynonymsStickersArchivedPacks)
        }
    }
    
    var searchIndex: Int32 {
        return rawValue
    }
}

enum ProxySearchTag: Int32, CaseIterable {
    case addProxy = 1
    case useForCalls = 2
}

extension ProxySearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .proxy
    }
    
    static var rootTitle: String {
        return strings().accountSettingsProxy
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsProxyTitle)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .proxy(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: ProxySearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        let controller = SettingsNavigationHooks.shared.makeProxyListController(context, { servers in
            var message: String = ""
            for server in servers {
                message += server.link + "\n\n"
            }
            message = message.trimmed
            
            SettingsHooks.shared.shareLink(context, message)
        }, { controller in
            present(.push, controller)
        })
        present(.push, controller)
    }
    
    var searchTitle: String {
        switch self {
        case .addProxy:
            return strings().proxySettingsAddProxy
        case .useForCalls:
            return strings().proxySettingsUseForCalls
        }
    }
    
    var searchAlternates: [String] {
        switch self {
        case .addProxy:
            return synonyms(strings().settingsSearchSynonymsProxyAddProxy)
        case .useForCalls:
            return synonyms(strings().settingsSearchSynonymsProxyUseForCalls)
        }
    }
    
    func isAvailable(in environment: SettingsSearchEnvironment) -> Bool {
        if case .useForCalls = self {
            return environment.hasSocksProxy
        }
        return true
    }
    
    var searchIndex: Int32 {
        return rawValue
    }
}
