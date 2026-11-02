import Cocoa
import Postbox
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import AlertsUI
import WallpaperUI

enum SettingsSearchableItemIcon {
    case profile
    case proxy
    case savedMessages
    case calls
    case stickers
    case notifications
    case privacy
    case data
    case appearance
    case language
    case watch
    case wallet
    case passport
    case support
    case faq
    case general
    case filters
    case premium
    case business
    case gift
    case stars
}

extension SettingsSearchableItemIcon {
    var thumb: CGImage? {
        switch self {
        case .profile:
            return theme.icons.settingsProfile
        case .proxy:
            return theme.icons.settingsProxy
        case .stickers:
            return theme.icons.settingsStickers
        case .notifications:
            return theme.icons.settingsNotifications
        case .privacy:
            return theme.icons.settingsSecurity
        case .data:
            return theme.icons.settingsStorage
        case .appearance:
            return theme.icons.settingsAppearance
        case .language:
            return theme.icons.settingsLanguage
        case .support:
            return theme.icons.settingsAskQuestion
        case .faq:
            return theme.icons.settingsFaq
        case .general:
            return theme.icons.settingsGeneral
        case .filters:
            return theme.icons.settingsFilters
        case .passport:
            return theme.icons.settingsPassport
        case .premium:
            return theme.icons.settingsPremium
        case .business:
            return theme.icons.settingsBusiness
        case .gift:
            return theme.icons.settingsGiftPremium
        case .stars:
            return theme.icons.settingsStars
        default:
            return nil
        }
    }
}





enum SettingsSearchableItemPresentation {
    case push
    case modal
    case immediate
    case dismiss
}



struct SettingsSearchableItem<Context: AccountContextProtocol> {
    let id: SettingsSearchableItemId
    let title: String
    let alternate: [String]
    let icon: SettingsSearchableItemIcon
    let breadcrumbs: [String]
    let present: (Context, NavigationViewController?, @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) -> Void
}



func searchSettingsItems<Context: AccountContextProtocol>(items: [SettingsSearchableItem<Context>], query: String) -> [SettingsSearchableItem<Context>] {
    let queryTokens = stringTokens(query.lowercased())
    
    var result: [SettingsSearchableItem<Context>] = []
    for item in items {
        var string = item.title
        if !item.alternate.isEmpty {
            for alternate in item.alternate {
                let trimmed = alternate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    string += " \(trimmed)"
                }
            }
        }
        if item.breadcrumbs.count > 1 {
            string += " \(item.breadcrumbs.suffix(from: 1).joined(separator: " "))"
        }
        
        let tokens = stringTokens(string)
        if matchStringTokens(tokens, with: queryTokens) {
            result.append(item)
        }
    }
    
    return result
}


func synonyms(_ string: String?) -> [String] {
    if let string = string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return string.components(separatedBy: "\n")
    } else {
        return []
    }
}



private func stringTokens(_ string: String) -> [ValueBoxKey] {
    let nsString = string.folding(options: .diacriticInsensitive, locale: .current).lowercased() as NSString
    
    let flag = UInt(kCFStringTokenizerUnitWord)
    let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault, nsString, CFRangeMake(0, nsString.length), flag, CFLocaleCopyCurrent())
    var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
    var tokens: [ValueBoxKey] = []
    
    var addedTokens = Set<ValueBoxKey>()
    while tokenType != [] {
        let currentTokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        
        if currentTokenRange.location >= 0 && currentTokenRange.length != 0 {
            let token = ValueBoxKey(length: currentTokenRange.length * 2)
            nsString.getCharacters(token.memory.assumingMemoryBound(to: unichar.self), range: NSMakeRange(currentTokenRange.location, currentTokenRange.length))
            if !addedTokens.contains(token) {
                tokens.append(token)
                addedTokens.insert(token)
            }
        }
        tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
    }
    
    return tokens
}

private func matchStringTokens(_ tokens: [ValueBoxKey], with other: [ValueBoxKey]) -> Bool {
    if other.isEmpty {
        return false
    } else if other.count == 1 {
        let otherToken = other[0]
        for token in tokens {
            if otherToken.isPrefix(to: token) {
                return true
            }
        }
    } else {
        for otherToken in other {
            var found = false
            for token in tokens {
                if otherToken.isPrefix(to: token) {
                    found = true
                    break
                }
            }
            if !found {
                return false
            }
        }
        return true
    }
    return false
}


private func languageSearchableItems<Context: AccountContextProtocol>(context: Context, localizations: [LocalizationInfo]) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .language
    
    let applyLocalization: (Context, @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void, String) -> Void = { context, present, languageCode in
        _ = showModalProgress(signal: context.engine.localization.downloadAndApplyLocalization(accountManager: context.sharedContext.accountManager, languageCode: languageCode), for: context.window).start()
    }
    
    var items: [SettingsSearchableItem<Context>] = []
    var index: Int32 = 1
    for localization in localizations {
        items.append(SettingsSearchableItem(id: .language(index), title: localization.localizedTitle, alternate: [localization.title], icon: icon, breadcrumbs: [strings().accountSettingsLanguage], present: { context, _, present in
            applyLocalization(context, present, localization.languageCode)
        }))
        index += 1
    }
    return items
}

func settingsSearchableItems<Context: AccountContextProtocol>(context: Context, archivedStickerPacks: Signal<[ArchivedStickerPackItem]?, NoError>, privacySettings: Signal<AccountPrivacySettings?, NoError>) -> Signal<[SettingsSearchableItem<Context>], NoError> {
    
    let canAddAccount = activeAccountsAndPeers(context: context)
        |> take(1)
        |> map { accountsAndPeers -> Bool in
            return accountsAndPeers.1.count + 1 < maximumNumberOfAccounts
    }
    
    let notificationSettings = context.account.postbox.preferencesView(keys: [PreferencesKeys.globalNotifications])
        |> take(1)
        |> map { view -> GlobalNotificationSettingsSet in
            let viewSettings: GlobalNotificationSettingsSet
            if let settings = view.values[PreferencesKeys.globalNotifications]?.get(GlobalNotificationSettings.self) {
                viewSettings = settings.effective
            } else {
                viewSettings = GlobalNotificationSettingsSet.defaultSettings
            }
            return viewSettings
    }
    
    let archivedStickerPacks = archivedStickerPacks
        |> take(1)
    
    let privacySettings = privacySettings
        |> take(1)
    
    let proxyServers = context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> map { sharedData -> ProxySettings in
            if let value = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) {
                return value
            } else {
                return ProxySettings.defaultSettings
            }
        }
        |> map { settings -> [ProxyServerSettings] in
            return settings.servers
    }
    
    let localizationPreferencesKey: PostboxViewKey = .preferences(keys: Set([PreferencesKeys.localizationListState]))
    let localizations = combineLatest(context.account.postbox.combinedView(keys: [localizationPreferencesKey]), context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.localizationSettings]))
        |> map { view, sharedData -> [LocalizationInfo] in
            if let localizationListState = (view.views[localizationPreferencesKey] as? PreferencesView)?.values[PreferencesKeys.localizationListState]?.get(LocalizationListState.self), !localizationListState.availableOfficialLocalizations.isEmpty {
                
                var existingIds = Set<String>()
                let availableSavedLocalizations = localizationListState.availableSavedLocalizations.filter({ info in !localizationListState.availableOfficialLocalizations.contains(where: { $0.languageCode == info.languageCode }) })
                
                var activeLanguageCode: String?
                if let localizationSettings = sharedData.entries[SharedDataKeys.localizationSettings]?.get(LocalizationSettings.self) {
                    activeLanguageCode = localizationSettings.primaryComponent.languageCode
                }
                
                var localizationItems: [LocalizationInfo] = []
                if !availableSavedLocalizations.isEmpty {
                    for info in availableSavedLocalizations {
                        if existingIds.contains(info.languageCode) || info.languageCode == activeLanguageCode {
                            continue
                        }
                        existingIds.insert(info.languageCode)
                        localizationItems.append(info)
                    }
                }
                for info in localizationListState.availableOfficialLocalizations {
                    if existingIds.contains(info.languageCode) || info.languageCode == activeLanguageCode {
                        continue
                    }
                    existingIds.insert(info.languageCode)
                    localizationItems.append(info)
                }
                
                return localizationItems
            } else {
                return []
            }
    }
    
    return combineLatest(canAddAccount, localizations, notificationSettings, archivedStickerPacks, proxyServers, privacySettings)
        |> map { canAddAccount, localizations, notificationSettings, archivedStickerPacks, proxyServers, privacySettings in
            
            var allItems: [SettingsSearchableItem<Context>] = []
            let environment = SettingsSearchEnvironment(privacySettings: privacySettings, canAddAccount: canAddAccount, hasSocksProxy: proxyServers.contains(where: { if case .socks5 = $0.connection { return true } else { return false } }))
            
            allItems.append(contentsOf: searchableItems(ProfileSearchTag.self, context: context, environment: environment))
            
            
            allItems.append(contentsOf: searchableItems(StickersSearchTag.self, context: context, environment: environment))
            
            allItems.append(contentsOf: searchableItems(NotificationSearchTag.self, context: context, environment: environment))
            
            allItems.append(contentsOf: searchableItems(PrivacySearchTag.self, context: context, environment: environment))
            
            allItems.append(contentsOf: searchableItems(SettingsDataAndStorageTag.self, context: context, environment: environment))
            
            allItems.append(contentsOf: searchableItems(ProxySearchTag.self, context: context, environment: environment))
            
            allItems.append(contentsOf: searchableItems(AppearanceSearchTag.self, context: context, environment: environment))
            allItems.append(contentsOf: searchableItems(SettingsRootSearchTag.self, context: context, environment: environment))
            allItems.append(contentsOf: searchableItems(PowerSavingSearchTag.self, context: context, environment: environment))
            
            allItems.append(contentsOf: searchableItems(LanguageSearchTag.self, context: context, environment: environment))
            allItems.append(contentsOf: languageSearchableItems(context: context, localizations: localizations))
            
            allItems.append(contentsOf: searchableItems(GeneralSettingsEntryTag.self, context: context, environment: environment))
            

            allItems.append(contentsOf: searchableItems(SupportSearchTag.self, context: context, environment: environment))
            allItems.append(contentsOf: searchableItems(FaqSearchTag.self, context: context, environment: environment))
            
            return allItems
    }
}




