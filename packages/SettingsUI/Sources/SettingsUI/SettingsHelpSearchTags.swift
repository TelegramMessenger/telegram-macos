import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Localization
import TelegramContext
import AlertsUI

enum LanguageSearchTag: CaseIterable {
    static var allCases: [LanguageSearchTag] {
        return []
    }
}

extension LanguageSearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .language
    }
    
    static var rootTitle: String {
        return strings().accountSettingsLanguage
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsAppLanguage)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .language(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: LanguageSearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        present(.push, LanguageController(context))
    }
    
    var searchTitle: String {
        return ""
    }
    
    var searchIndex: Int32 {
        return 0
    }
}

enum SupportSearchTag: CaseIterable {
    static var allCases: [SupportSearchTag] {
        return []
    }
}

extension SupportSearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .support
    }
    
    static var rootTitle: String {
        return strings().accountSettingsAskQuestion
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsSupport)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .support(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: SupportSearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        verifyAlert_button(for: context.window, information: strings().accountConfirmAskQuestion, option: strings().accountConfirmGoToFaq, successHandler: { result in
            switch result {
            case .basic:
                _ = showModalProgress(signal: context.engine.peers.supportPeerId(), for: context.window).start(next: { peerId in
                    if let peerId = peerId {
                        present(.push, SettingsHooks.shared.makeChatController(context, .peer(peerId)))
                    }
                })
            case .thrid:
                let _ = (cachedFaqInstantPage(context: context) |> deliverOnMainQueue).start(next: { resolvedUrl in
                    SettingsHooks.shared.executeInAppLink(resolvedUrl)
                })
            }
        })
    }
    
    var searchTitle: String {
        return ""
    }
    
    var searchIndex: Int32 {
        return 0
    }
}

enum FaqSearchTag: CaseIterable {
    static var allCases: [FaqSearchTag] {
        return []
    }
}

extension FaqSearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .faq
    }
    
    static var rootTitle: String {
        return strings().accountSettingsFAQ
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsFAQ)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .faq(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: FaqSearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        let _ = (cachedFaqInstantPage(context: context) |> deliverOnMainQueue).start(next: { resolvedUrl in
            SettingsHooks.shared.executeInAppLink(resolvedUrl)
        })
    }
    
    var searchTitle: String {
        return ""
    }
    
    var searchIndex: Int32 {
        return 0
    }
}
