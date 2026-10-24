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


private func synonyms(_ string: String?) -> [String] {
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


private func profileSearchableItems<Context: AccountContextProtocol>(context: Context, canAddAccount: Bool) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .profile
    
    let presentProfileSettings: (Context, @escaping  (SettingsSearchableItemPresentation, ViewController?) -> Void, EditSettingsEntryTag?) -> Void = { context, present, itemTag in
        EditAccountInfoController(context: context, focusOnItemTag: itemTag, f: { controller in
            present(.push, controller)
        })
    }
    
    var items: [SettingsSearchableItem<Context>] = []
    items.append(SettingsSearchableItem(id: .profile(0), title: strings().editAccountTitle, alternate: synonyms(strings().settingsSearchSynonymsEditProfileTitle), icon: icon, breadcrumbs: [], present: { context, _, present in
        presentProfileSettings(context, present, nil)
    }))
    
    items.append(SettingsSearchableItem(id: .profile(1), title: strings().accountSettingsBio, alternate: synonyms(strings().settingsSearchSynonymsEditProfileTitle), icon: icon, breadcrumbs: [strings().editAccountTitle], present: { context, _, present in
        presentProfileSettings(context, present, .bio)
    }))
    items.append(SettingsSearchableItem(id: .profile(2), title: strings().editAccountChangeNumber, alternate: synonyms(strings().settingsSearchSynonymsEditProfilePhoneNumber), icon: icon, breadcrumbs: [strings().editAccountTitle], present: { context, _, present in
        present(.push, SettingsNavigationHooks.shared.makePhoneNumberIntroController(context))
    }))
    items.append(SettingsSearchableItem(id: .profile(3), title: strings().editAccountUsername, alternate: synonyms(strings().settingsSearchSynonymsEditProfileUsername), icon: icon, breadcrumbs: [strings().editAccountTitle], present: { context, _, present in
        present(.push, UsernameController(context))
    }))
    if canAddAccount {
        items.append(SettingsSearchableItem(id: .profile(4), title: strings().editAccountAddAccount, alternate: synonyms(strings().settingsSearchSynonymsEditProfileAddAccount), icon: icon, breadcrumbs: [strings().editAccountTitle], present: { context, _, present in
            let isTestingEnvironment = NSApp.currentEvent?.modifierFlags.contains(.command) == true
            context.sharedContext.beginNewAuth(testingEnvironment: isTestingEnvironment)
        }))
    }
    items.append(SettingsSearchableItem(id: .profile(5), title: strings().editAccountLogout, alternate: synonyms(strings().settingsSearchSynonymsEditProfileLogout), icon: icon, breadcrumbs: [strings().editAccountTitle], present: { context, navigationController, present in
        showModal(with: LogoutViewController(context: context, f: { controller in
            present(.push, controller)
        }), for: context.window)
    }))
    return items
}



private func stickerSearchableItems<Context: AccountContextProtocol>(context: Context, archivedStickerPacks: [ArchivedStickerPackItem]?) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .stickers
    
    let presentStickerSettings: (Context, (SettingsSearchableItemPresentation, ViewController?) -> Void, SettingsStickersTag?) -> Void = { context, present, itemTag in
        present(.push, SettingsNavigationHooks.shared.makeInstalledStickerPacksController(context, itemTag))
    }
    
    var items: [SettingsSearchableItem<Context>] = []
    
    items.append(SettingsSearchableItem(id: .stickers(0), title: strings().accountSettingsStickers, alternate: synonyms(strings().settingsSearchSynonymsStickersTitle), icon: icon, breadcrumbs: [], present: { context, _, present in
        presentStickerSettings(context, present, nil)
    }))
    items.append(SettingsSearchableItem(id: .stickers(1), title: strings().stickersSuggestStickers, alternate: synonyms(strings().settingsSearchSynonymsStickersSuggestStickers), icon: icon, breadcrumbs: [strings().accountSettingsStickers], present: { context, _, present in
        presentStickerSettings(context, present, .suggestOptions)
    }))
    items.append(SettingsSearchableItem(id: .stickers(3), title: strings().installedStickersTranding, alternate: synonyms(strings().settingsSearchSynonymsStickersFeaturedPacks), icon: icon, breadcrumbs: [strings().accountSettingsStickers], present: { context, _, present in
        present(.push, SettingsNavigationHooks.shared.makeFeaturedStickerPacksController(context))
    }))
    items.append(SettingsSearchableItem(id: .stickers(4), title: strings().installedStickersArchived, alternate: synonyms(strings().settingsSearchSynonymsStickersArchivedPacks), icon: icon, breadcrumbs: [strings().accountSettingsStickers], present: { context, _, present in
        present(.push, SettingsNavigationHooks.shared.makeArchivedStickerPacksController(context))
    }))
    return items
}

private func notificationSearchableItems<Context: AccountContextProtocol>(context: Context, settings: GlobalNotificationSettingsSet) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .notifications
    
    let presentNotificationSettings: (Context, (SettingsSearchableItemPresentation, ViewController?) -> Void, NotificationsAndSoundsEntryTag?) -> Void = { context, present, itemTag in
        present(.push, NotificationPreferencesController(context, focusOnItemTag: itemTag))
    }
    
    let presentCategory: (NotificationSettingsCategory, NotificationCategoryEntryTag?, (SettingsSearchableItemPresentation, ViewController?) -> Void, Context) -> Void = { category, tag, present, context in
        present(.push, NotificationCategorySettingsController(context: context, category: category, focusOnItemTag: tag))
    }
    
    let presentReactions: (ReactionNotificationEntryTag?, (SettingsSearchableItemPresentation, ViewController?) -> Void, Context) -> Void = { tag, present, context in
        present(.push, ReactionNotificationSettingsController(context: context, focusOnItemTag: tag))
    }
    
    let categoryItems: (NotificationSettingsCategory, Int32) -> [SettingsSearchableItem<Context>] = { category, base in
        let breadcrumbs = [strings().accountSettingsNotifications, category.title]
        var rows: [(String, NotificationCategoryEntryTag)]
        if case .stories = category {
            rows = [(strings().notificationSettingsStoriesNew, .show), (strings().notificationSettingsStoriesImportant, .important), (strings().notificationSettingsCategoryShowSender, .preview)]
        } else {
            rows = [(strings().notificationSettingsCategoryShowNotifications, .show), (strings().notificationSettingsMessagesPreview, .preview)]
        }
        rows += [(strings().notificationSettingsCategorySound, .sound), (strings().notificationSettingsExceptionsAdd, .addException), (strings().notificationSettingsExceptionsDeleteAll, .deleteExceptions)]
        var items: [SettingsSearchableItem<Context>] = [SettingsSearchableItem(id: .notifications(base), title: category.title, alternate: [], icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsMessageNotifications], present: { context, _, present in
            presentCategory(category, nil, present, context)
        })]
        for (i, row) in rows.enumerated() {
            items.append(SettingsSearchableItem(id: .notifications(base + 1 + Int32(i)), title: row.0, alternate: [], icon: icon, breadcrumbs: breadcrumbs, present: { context, _, present in
                presentCategory(category, row.1, present, context)
            }))
        }
        return items
    }
    
    let reactionRows: [(String, ReactionNotificationEntryTag)] = [(strings().notificationSettingsReactionsMessages, .messages), (strings().notificationSettingsCategoryShowSender, .showSender), (strings().notificationSettingsCategorySound, .sound)]
    var reactionItems: [SettingsSearchableItem<Context>] = [SettingsSearchableItem(id: .notifications(70), title: strings().notificationSettingsReactions, alternate: [], icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsMessageNotifications], present: { context, _, present in
        presentReactions(nil, present, context)
    })]
    for (i, row) in reactionRows.enumerated() {
        reactionItems.append(SettingsSearchableItem(id: .notifications(71 + Int32(i)), title: row.0, alternate: [], icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsReactions], present: { context, _, present in
            presentReactions(row.1, present, context)
        }))
    }
    
    let categorySearchItems = categoryItems(.privateChats, 30) + categoryItems(.groupChats, 40) + categoryItems(.channels, 50) + categoryItems(.stories, 60) + reactionItems
    
    return categorySearchItems + [
        SettingsSearchableItem(id: .notifications(0), title: strings().accountSettingsNotifications, alternate: synonyms(strings().settingsSearchSynonymsNotificationsTitle), icon: icon, breadcrumbs: [], present: { context, _, present in
            presentNotificationSettings(context, present, nil)
        }),
        SettingsSearchableItem(id: .notifications(2), title: strings().notificationSettingsThisDeviceShowMessageText, alternate: synonyms(strings().settingsSearchSynonymsNotificationsMessageNotificationsPreview), icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsThisDeviceHeader], present: { context, _, present in
            presentNotificationSettings(context, present, .messagePreviews)
        }),
//        SettingsSearchableItem(id: .notifications(18), title: strings().notificationSettingsIncludeGroups, alternate: synonyms(strings().settingsSearchSynonymsNotificationsBadgeIncludeMutedPublicGroups), icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsBadgeHeader], present: { context, _, present in
//            presentNotificationSettings(context, present, .includePublicGroups)
//        }),
        SettingsSearchableItem(id: .notifications(19), title: strings().notificationSettingsIncludeChannels, alternate: synonyms(strings().settingsSearchSynonymsNotificationsBadgeIncludeMutedChannels), icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsBadgeHeader], present: { context, _, present in
            presentNotificationSettings(context, present, .includeChannels)
        }),
        SettingsSearchableItem(id: .notifications(20), title: strings().notificationSettingsCountUnreadMessages, alternate: synonyms(strings().settingsSearchSynonymsNotificationsBadgeCountUnreadMessages), icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsBadgeHeader], present: { context, _, present in
            presentNotificationSettings(context, present, .unreadCountCategory)
        }),
        SettingsSearchableItem(id: .notifications(21), title: strings().notificationSettingsContactJoined, alternate: synonyms(strings().settingsSearchSynonymsNotificationsContactJoined), icon: icon, breadcrumbs: [strings().accountSettingsNotifications], present: { context, _, present in
            presentNotificationSettings(context, present, .joinedNotifications)
        }),
        SettingsSearchableItem(id: .notifications(23), title: strings().notificationSettingsAllAccounts, alternate: [], icon: icon, breadcrumbs: [strings().accountSettingsNotifications], present: { context, _, present in
            presentNotificationSettings(context, present, .allAccounts)
        }),
        SettingsSearchableItem(id: .notifications(24), title: strings().notificationSettingsThisDeviceDefaultSound, alternate: [], icon: icon, breadcrumbs: [strings().accountSettingsNotifications, strings().notificationSettingsThisDeviceHeader], present: { context, _, present in
            presentNotificationSettings(context, present, .tone)
        }),
        SettingsSearchableItem(id: .notifications(22), title: strings().notificationSettingsResetAll, alternate: synonyms(strings().settingsSearchSynonymsNotificationsResetAllNotifications), icon: icon, breadcrumbs: [strings().accountSettingsNotifications], present: { context, _, present in
            presentNotificationSettings(context, present, .reset)
        })
    ]
}

private func privacySearchableItems<Context: AccountContextProtocol>(context: Context, privacySettings: AccountPrivacySettings?) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .privacy
    
    let presentPrivacySettings: (Context, (SettingsSearchableItemPresentation, ViewController?) -> Void, PrivacyAndSecurityEntryTag?) -> Void = { context, present, itemTag in
        present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: itemTag, twoStepVerificationConfiguration: nil))
    }
    
    let presentSelectivePrivacySettings: (Context, SelectivePrivacySettingsKind, @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) -> Void = { context, kind, present in
        let privacySignal: Signal<AccountPrivacySettings, NoError>
        if let privacySettings = privacySettings {
            privacySignal = .single(privacySettings)
        } else {
            privacySignal = context.engine.privacy.requestAccountPrivacySettings()
        }
        let callsSignal: Signal<(VoiceCallSettings, VoipConfiguration)?, NoError>
        if case .voiceCalls = kind {
            callsSignal = combineLatest(context.sharedContext.accountManager.sharedData(keys: [ApplicationSharedPreferencesKeys.voiceCallSettings]), context.account.postbox.preferencesView(keys: [PreferencesKeys.voipConfiguration]))
                |> take(1)
                |> map { sharedData, view -> (VoiceCallSettings, VoipConfiguration)? in
                    let voiceCallSettings: VoiceCallSettings = sharedData.entries[ApplicationSharedPreferencesKeys.voiceCallSettings]?.get(VoiceCallSettings.self) ?? .defaultSettings
                    let voipConfiguration = view.values[PreferencesKeys.voipConfiguration]?.get(VoipConfiguration.self) ?? .defaultValue
                    return (voiceCallSettings, voipConfiguration)
            }
        } else {
            callsSignal = .single(nil)
        }
        
        let _ = (combineLatest(privacySignal, callsSignal)
            |> deliverOnMainQueue).start(next: { info, callSettings in
                let current: SelectivePrivacySettings
                switch kind {
                case .presence:
                    current = info.presence
                case .groupInvitations:
                    current = info.groupInvitations
                case .voiceCalls:
                    current = info.voiceCalls
                case .profilePhoto:
                    current = info.profilePhoto
                case .forwards:
                    current = info.forwards
                case .phoneNumber:
                    current = info.phoneNumber
                case .voiceMessages:
                    current = info.voiceMessages
                case .bio:
                    current = info.bio
                case .birthday:
                    current = info.birthday
                case .gifts:
                    current = info.giftsAutoSave
                case .savedMusic:
                    current = info.savedMusic
                }
                
                present(.push, SelectivePrivacySettingsController(context, kind: kind, current: current, callSettings: kind == .voiceCalls ? info.voiceCallsP2P : nil, phoneDiscoveryEnabled: nil, updated: { updated, updatedCallSettings, _, _ in }))
            })
    }
    

    
    let passcodeTitle: String = strings().privacySettingsPasscode

    
    return [
        SettingsSearchableItem(id: .privacy(0), title: strings().accountSettingsPrivacyAndSecurity, alternate: synonyms(strings().settingsSearchSynonymsPrivacyTitle), icon: icon, breadcrumbs: [], present: { context, _, present in
            presentPrivacySettings(context, present, nil)
        }),
        SettingsSearchableItem(id: .privacy(1), title: strings().privacySettingsBlockedUsers, alternate: synonyms(strings().settingsSearchSynonymsPrivacyBlockedUsers), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            present(.push, BlockedPeersViewController(context))
        }),
        SettingsSearchableItem(id: .privacy(2), title: strings().privacySettingsLastSeen, alternate: synonyms(strings().settingsSearchSynonymsPrivacyLastSeen), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentSelectivePrivacySettings(context, .presence, present)
        }),
        SettingsSearchableItem(id: .privacy(3), title: strings().privacySettingsProfilePhoto, alternate: synonyms(strings().settingsSearchSynonymsPrivacyProfilePhoto), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentSelectivePrivacySettings(context, .profilePhoto, present)
        }),
        SettingsSearchableItem(id: .privacy(4), title: strings().privacySettingsForwards, alternate: synonyms(strings().settingsSearchSynonymsPrivacyForwards), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentSelectivePrivacySettings(context, .forwards, present)
        }),
        SettingsSearchableItem(id: .privacy(5), title: strings().privacySettingsVoiceCalls, alternate: synonyms(strings().settingsSearchSynonymsPrivacyCalls), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentSelectivePrivacySettings(context, .voiceCalls, present)
        }),
        SettingsSearchableItem(id: .privacy(6), title: strings().privacySettingsGroups, alternate: synonyms(strings().settingsSearchSynonymsPrivacyGroupsAndChannels), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentSelectivePrivacySettings(context, .groupInvitations, present)
        }),
        SettingsSearchableItem(id: .privacy(7), title: passcodeTitle, alternate: [], icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            present(.push, SettingsNavigationHooks.shared.makePasscodeSettingsController(context))
        }),
        SettingsSearchableItem(id: .privacy(8), title: strings().privacySettingsTwoStepVerification, alternate: synonyms(strings().settingsSearchSynonymsPrivacyTwoStepAuth), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, navigation, present in
            present(.push, twoStepVerificationUnlockController(context: context, mode: .access(nil), presentController: { controller, root, animated in
                guard let navigation = navigation else {return}
                if root {
                    navigation.removeUntil(PrivacyAndSecurityViewController<Context>.self)
                }
                if !animated {
                    navigation.stackInsert(controller, at: navigation.stackCount)
                } else {
                    navigation.push(controller)
                }
            }))
        }),
        SettingsSearchableItem(id: .privacy(9), title: strings().privacySettingsActiveSessions, alternate: synonyms(strings().settingsSearchSynonymsPrivacyAuthSessions), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            present(.push, SettingsNavigationHooks.shared.makeRecentSessionsController(context))
        }),
        SettingsSearchableItem(id: .privacy(10), title: strings().privacySettingsDeleteAccountHeader, alternate: synonyms(strings().settingsSearchSynonymsPrivacyDeleteAccountIfAwayFor), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentPrivacySettings(context, present, .accountTimeout)
        }),
        SettingsSearchableItem(id: .privacy(14), title: strings().suggestFrequentContacts, alternate: synonyms(strings().settingsSearchSynonymsPrivacyDataTopPeers), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentPrivacySettings(context, present, .topPeers)
        }),
        SettingsSearchableItem(id: .privacy(15), title: strings().privacyAndSecurityClearCloudDrafts, alternate: synonyms(strings().settingsSearchSynonymsPrivacyDataDeleteDrafts), icon: icon, breadcrumbs: [strings().accountSettingsPrivacyAndSecurity], present: { context, _, present in
            presentPrivacySettings(context, present, .cloudDraft)
        })
    ]
}

private func dataSearchableItems<Context: AccountContextProtocol>(context: Context) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .data
    
    let presentDataSettings: (Context, (SettingsSearchableItemPresentation, ViewController?) -> Void, SettingsDataAndStorageTag?) -> Void = { context, present, itemTag in
        present(.push, SettingsNavigationHooks.shared.makeDataAndStorageController(context, itemTag))
    }
    
    return [
        SettingsSearchableItem(id: .data(0), title: strings().accountSettingsDataAndStorage, alternate: synonyms(strings().settingsSearchSynonymsDataTitle), icon: icon, breadcrumbs: [], present: { context, _, present in
           presentDataSettings(context, present, nil)
        }),
        SettingsSearchableItem(id: .data(1), title: strings().dataAndStorageStorageUsage, alternate: synonyms(strings().settingsSearchSynonymsDataStorageTitle), icon: icon, breadcrumbs: [strings().accountSettingsDataAndStorage], present: { context, _, present in
            present(.push, SettingsNavigationHooks.shared.makeStorageUsageController(context))
        }),
        SettingsSearchableItem(id: .data(2), title: strings().storageUsageKeepMedia, alternate: synonyms(strings().settingsSearchSynonymsDataStorageKeepMedia), icon: icon, breadcrumbs: [strings().accountSettingsDataAndStorage, strings().dataAndStorageStorageUsage], present: { context, _, present in
            present(.push, SettingsNavigationHooks.shared.makeStorageUsageController(context))
        }),
        SettingsSearchableItem(id: .data(3), title: strings().logoutOptionsClearCacheTitle, alternate: synonyms(strings().settingsSearchSynonymsDataStorageClearCache), icon: icon, breadcrumbs: [strings().accountSettingsDataAndStorage, strings().dataAndStorageStorageUsage], present: { context, _, present in
            present(.push, SettingsNavigationHooks.shared.makeStorageUsageController(context))
        }),
        SettingsSearchableItem(id: .data(4), title: strings().dataAndStorageNetworkUsage, alternate: synonyms(strings().settingsSearchSynonymsDataNetworkUsage), icon: icon, breadcrumbs: [strings().accountSettingsDataAndStorage], present: { context, _, present in
            present(.push, SettingsNavigationHooks.shared.makeNetworkUsageController(context))
        }),
        SettingsSearchableItem(id: .data(7), title: strings().dataAndStorageAutomaticDownloadReset, alternate: synonyms(strings().settingsSearchSynonymsDataAutoDownloadReset), icon: icon, breadcrumbs: [strings().accountSettingsDataAndStorage], present: { context, _, present in
            presentDataSettings(context, present, .automaticDownloadReset)
        }),
        SettingsSearchableItem(id: .data(8), title: strings().dataAndStorageAutoplayGIFs, alternate: synonyms(strings().settingsSearchSynonymsDataAutoplayGifs), icon: icon, breadcrumbs: [strings().accountSettingsDataAndStorage, strings().dataAndStorageAutoplayHeader], present: { context, _, present in
            presentDataSettings(context, present, .autoplayGifs)
        }),
        SettingsSearchableItem(id: .data(9), title: strings().dataAndStorageAutoplayVideos, alternate: synonyms(strings().settingsSearchSynonymsDataAutoplayVideos), icon: icon, breadcrumbs: [strings().accountSettingsDataAndStorage, strings().dataAndStorageAutoplayHeader], present: { context, _, present in
            presentDataSettings(context, present, .autoplayVideos)
        })
    ]
}

private func proxySearchableItems<Context: AccountContextProtocol>(context: Context, servers: [ProxyServerSettings]) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .proxy
    
    let presentProxySettings: (Context, @escaping(SettingsSearchableItemPresentation, ViewController?) -> Void) -> Void = { context, present in
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
    
    var items: [SettingsSearchableItem<Context>] = []
    items.append(SettingsSearchableItem(id: .proxy(0), title: strings().accountSettingsProxy, alternate: synonyms(strings().settingsSearchSynonymsProxyTitle), icon: icon, breadcrumbs: [], present: { context, _, present in
        presentProxySettings(context, present)
    }))
    items.append(SettingsSearchableItem(id: .proxy(1), title: strings().proxySettingsAddProxy, alternate: synonyms(strings().settingsSearchSynonymsProxyAddProxy), icon: icon, breadcrumbs: [strings().accountSettingsProxy], present: { context, _, present in
        presentProxySettings(context, present)
    }))
    
    var hasSocksServers = false
    for server in servers {
        if case .socks5 = server.connection {
            hasSocksServers = true
            break
        }
    }
    if hasSocksServers {
        items.append(SettingsSearchableItem(id: .proxy(2), title: strings().proxySettingsUseForCalls, alternate: synonyms(strings().settingsSearchSynonymsProxyUseForCalls), icon: icon, breadcrumbs: [strings().accountSettingsProxy], present: { context, _, present in
            presentProxySettings(context, present)
        }))
    }
    return items
}

private func appearanceSearchableItems<Context: AccountContextProtocol>(context: Context) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .appearance
    
    let presentAppearanceSettings: (Context, (SettingsSearchableItemPresentation, ViewController?) -> Void, ThemeSettingsEntryTag?) -> Void = { context, present, itemTag in
        present(.push, AppAppearanceViewController(context: context, focusOnItemTag: itemTag))
    }
    
    return [
        SettingsSearchableItem(id: .appearance(0), title: strings().accountSettingsTheme, alternate: synonyms(strings().settingsSearchSynonymsAppearanceTitle), icon: icon, breadcrumbs: [], present: { context, _, present in
            presentAppearanceSettings(context, present, nil)
        }),
        SettingsSearchableItem(id: .appearance(1), title: strings().appearanceSettingsTextSizeHeader, alternate: synonyms(strings().settingsSearchSynonymsAppearanceTextSize), icon: icon, breadcrumbs: [strings().accountSettingsTheme], present: { context, _, present in
            presentAppearanceSettings(context, present, .fontSize)
        }),
        SettingsSearchableItem(id: .appearance(2), title: strings().generalSettingsChatBackground, alternate: synonyms(strings().settingsSearchSynonymsAppearanceChatBackground), icon: icon, breadcrumbs: [strings().accountSettingsTheme], present: { context, _, present in
            showModal(with: ChatWallpaperModalController(context), for: context.window)
        }),
        SettingsSearchableItem(id: .appearance(5), title: strings().appearanceSettingsAutoNight, alternate: synonyms(strings().settingsSearchSynonymsAppearanceAutoNightTheme), icon: icon, breadcrumbs: [strings().accountSettingsTheme], present: { context, _, present in
            present(.push, AutoNightSettingsController(context: context))
        }),
        SettingsSearchableItem(id: .appearance(6), title: strings().appearanceSettingsColorThemeHeader, alternate: synonyms(strings().settingsSearchSynonymsAppearanceColorTheme), icon: icon, breadcrumbs: [strings().accountSettingsTheme], present: { context, _, present in
            presentAppearanceSettings(context, present, .accentColor)
        }),
        SettingsSearchableItem(id: .appearance(6), title: strings().appearanceSettingsChatViewHeader, alternate: synonyms(strings().settingsSearchSynonymsAppearanceChatMode), icon: icon, breadcrumbs: [strings().accountSettingsTheme], present: { context, _, present in
            presentAppearanceSettings(context, present, .chatMode)
        }),
    ]
}

private func languageSearchableItems<Context: AccountContextProtocol>(context: Context, localizations: [LocalizationInfo]) -> [SettingsSearchableItem<Context>] {
    let icon: SettingsSearchableItemIcon = .language
    
    let applyLocalization: (Context, @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void, String) -> Void = { context, present, languageCode in
        _ = showModalProgress(signal: context.engine.localization.downloadAndApplyLocalization(accountManager: context.sharedContext.accountManager, languageCode: languageCode), for: context.window).start()
    }
    
    var items: [SettingsSearchableItem<Context>] = []
    items.append(SettingsSearchableItem(id: .language(0), title: strings().accountSettingsLanguage, alternate: synonyms(strings().settingsSearchSynonymsAppLanguage), icon: icon, breadcrumbs: [], present: { context, _, present in
        present(.push, LanguageController(context))
    }))
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
            
            let profileItems = profileSearchableItems(context: context, canAddAccount: canAddAccount)
            allItems.append(contentsOf: profileItems)
            
            
            let stickerItems = stickerSearchableItems(context: context, archivedStickerPacks: archivedStickerPacks)
            allItems.append(contentsOf: stickerItems)
            
            let notificationItems = notificationSearchableItems(context: context, settings: notificationSettings)
            allItems.append(contentsOf: notificationItems)
            
            let privacyItems = privacySearchableItems(context: context, privacySettings: privacySettings)
            allItems.append(contentsOf: privacyItems)
            
            let dataItems = dataSearchableItems(context: context)
            allItems.append(contentsOf: dataItems)
            
            let proxyItems = proxySearchableItems(context: context, servers: proxyServers)
            allItems.append(contentsOf: proxyItems)
            
            let appearanceItems = appearanceSearchableItems(context: context)
            allItems.append(contentsOf: appearanceItems)
            
            let languageItems = languageSearchableItems(context: context, localizations: localizations)
            allItems.append(contentsOf: languageItems)
            

            let support = SettingsSearchableItem<Context>(id: .support(0), title: strings().accountSettingsAskQuestion, alternate: synonyms(strings().settingsSearchSynonymsSupport), icon: .support, breadcrumbs: [], present: { context, _, present in
                verifyAlert_button(for: context.window, information: strings().accountConfirmAskQuestion, option: strings().accountConfirmGoToFaq, successHandler: {  result in
                    switch result {
                    case .basic:
                        _ = showModalProgress(signal: context.engine.peers.supportPeerId(), for: context.window).start(next: {  peerId in
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
            })
            allItems.append(support)
            
            let faq = SettingsSearchableItem<Context>(id: .faq(0), title: strings().accountSettingsFAQ, alternate: synonyms(strings().settingsSearchSynonymsFAQ), icon: .faq, breadcrumbs: [], present: { context, navigationController, present in
                let _ = (cachedFaqInstantPage(context: context) |> deliverOnMainQueue).start(next: { resolvedUrl in
                    SettingsHooks.shared.executeInAppLink(resolvedUrl)
                })
            })
            allItems.append(faq)
            
            return allItems
    }
}




