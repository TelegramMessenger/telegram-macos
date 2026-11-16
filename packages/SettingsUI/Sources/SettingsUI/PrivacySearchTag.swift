import Cocoa
import Postbox
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Localization
import TelegramContext

enum PrivacySearchTag: Int32 {
    case blockedUsers = 1
    case lastSeen = 2
    case profilePhoto = 3
    case forwards = 4
    case voiceCalls = 5
    case groups = 6
    case passcode = 7
    case twoStep = 8
    case activeSessions = 9
    case deleteAccount = 10
    case topPeers = 14
    case cloudDrafts = 15
    case phoneNumber = 16
    case voiceMessages = 17
    case messages = 18
    case bio = 19
    case birthday = 20
    case gifts = 21
    case savedMusic = 22
    case passkeys = 23
    case loginEmail = 24
    case globalTimer = 25
    case webSessions = 26
    case secretChatWebPreview = 27
    case sensitiveContent = 28
}

extension PrivacySearchTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .privacy
    }
    
    static var rootTitle: String {
        return strings().accountSettingsPrivacyAndSecurity
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsPrivacyTitle)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .privacy(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: PrivacySearchTag?, context: Context, navigation: NavigationViewController?, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        guard let tag = tag else {
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: nil, twoStepVerificationConfiguration: nil))
            return
        }
        switch tag {
        case .blockedUsers:
            present(.push, BlockedPeersViewController(context))
        case .passcode:
            present(.push, SettingsNavigationHooks.shared.makePasscodeSettingsController(context))
        case .activeSessions:
            present(.push, SettingsNavigationHooks.shared.makeRecentSessionsController(context))
        case .twoStep:
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
        default:
            if let kind = tag.selectiveKind {
                presentSelectivePrivacy(context, kind: kind, loaded: environment.privacySettings, present: present)
            } else {
                present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: tag.focusTag, twoStepVerificationConfiguration: nil))
            }
        }
    }
    
    private var selectiveKind: SelectivePrivacySettingsKind? {
        switch self {
        case .lastSeen: return .presence
        case .profilePhoto: return .profilePhoto
        case .forwards: return .forwards
        case .voiceCalls: return .voiceCalls
        case .groups: return .groupInvitations
        case .phoneNumber: return .phoneNumber
        case .voiceMessages: return .voiceMessages
        case .bio: return .bio
        case .birthday: return .birthday
        case .gifts: return .gifts
        case .savedMusic: return .savedMusic
        default: return nil
        }
    }
    
    private var focusTag: PrivacyAndSecurityEntryTag? {
        switch self {
        case .deleteAccount: return .accountTimeout
        case .topPeers: return .topPeers
        case .cloudDrafts: return .cloudDraft
        case .messages: return .messages
        case .passkeys: return .passkeys
        case .loginEmail: return .loginEmail
        case .globalTimer: return .globalTimer
        case .webSessions: return .webSessions
        case .secretChatWebPreview: return .secretChatWebPreview
        case .sensitiveContent: return .sensitiveContent
        default: return nil
        }
    }
    
    var searchBreadcrumbs: [String] {
        if case .activeSessions = self {
            return []
        }
        return [PrivacySearchTag.rootTitle]
    }
    
    var searchTitle: String {
        switch self {
        case .blockedUsers:
            return strings().privacySettingsBlockedUsers
        case .lastSeen:
            return strings().privacySettingsLastSeen
        case .profilePhoto:
            return strings().privacySettingsProfilePhoto
        case .forwards:
            return strings().privacySettingsForwards
        case .voiceCalls:
            return strings().privacySettingsVoiceCalls
        case .groups:
            return strings().privacySettingsGroups
        case .passcode:
            return strings().privacySettingsPasscode
        case .twoStep:
            return strings().privacySettingsTwoStepVerification
        case .activeSessions:
            return strings().privacySettingsActiveSessions
        case .deleteAccount:
            return strings().privacySettingsDeleteAccountHeader
        case .topPeers:
            return strings().suggestFrequentContacts
        case .cloudDrafts:
            return strings().privacyAndSecurityClearCloudDrafts
        case .phoneNumber:
            return strings().privacySettingsPhoneNumber
        case .voiceMessages:
            return strings().privacySettingsVoiceMessages
        case .messages:
            return strings().privacySettingsMessages
        case .bio:
            return strings().privacySettingsBio
        case .birthday:
            return strings().privacySettingsBirthday
        case .gifts:
            return strings().privacySettingsGifts
        case .savedMusic:
            return strings().privacySettingsSavedMusic
        case .passkeys:
            return strings().privacySettingsPasskey
        case .loginEmail:
            return strings().privacySettingsLoginEmail
        case .globalTimer:
            return strings().privacySettingsGlobalTimer
        case .webSessions:
            return strings().telegramWebSessionsController
        case .secretChatWebPreview:
            return strings().privacyAndSecuritySecretChatWebPreviewText
        case .sensitiveContent:
            return strings().privacyAndSecuritySensitiveText
        }
    }
    
    var searchAlternates: [String] {
        switch self {
        case .blockedUsers:
            return synonyms(strings().settingsSearchSynonymsPrivacyBlockedUsers)
        case .lastSeen:
            return synonyms(strings().settingsSearchSynonymsPrivacyLastSeen)
        case .profilePhoto:
            return synonyms(strings().settingsSearchSynonymsPrivacyProfilePhoto)
        case .forwards:
            return synonyms(strings().settingsSearchSynonymsPrivacyForwards)
        case .voiceCalls:
            return synonyms(strings().settingsSearchSynonymsPrivacyCalls)
        case .groups:
            return synonyms(strings().settingsSearchSynonymsPrivacyGroupsAndChannels)
        case .twoStep:
            return synonyms(strings().settingsSearchSynonymsPrivacyTwoStepAuth)
        case .activeSessions:
            return synonyms(strings().settingsSearchSynonymsPrivacyAuthSessions)
        case .deleteAccount:
            return synonyms(strings().settingsSearchSynonymsPrivacyDeleteAccountIfAwayFor)
        case .topPeers:
            return synonyms(strings().settingsSearchSynonymsPrivacyDataTopPeers)
        case .cloudDrafts:
            return synonyms(strings().settingsSearchSynonymsPrivacyDataDeleteDrafts)
        default:
            return []
        }
    }
    
    func isAvailable(in environment: SettingsSearchEnvironment) -> Bool {
        switch self {
        case .passkeys:
            return environment.passkeysAvailable
        case .loginEmail:
            return environment.loginEmailAvailable
        case .webSessions:
            return environment.hasWebSessions
        case .secretChatWebPreview:
            return environment.secretChatWebPreviewAvailable
        case .sensitiveContent:
            #if APP_STORE
            return false
            #else
            return environment.canAdjustSensitiveContent
            #endif
        default:
            return true
        }
    }
    
    var searchIndex: Int32 {
        return rawValue
    }
}

private let selectivePrivacyRequest = MetaDisposable()

private func presentSelectivePrivacy<Context: AccountContextProtocol>(_ context: Context, kind: SelectivePrivacySettingsKind, loaded: AccountPrivacySettings?, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
    let open: (AccountPrivacySettings) -> Void = { settings in
        present(.push, selectivePrivacyController(context, kind: kind, settings: settings, updated: { updated, _, _, globalSettings in
            SettingsHooks.shared.updatePrivacy(context, updated, kind)
            if let globalSettings = globalSettings {
                context.updateMessagesPrivacy(noPaidMessages: settings.noPaidMessages, globalSettings: globalSettings)
            }
        }))
    }
    if let loaded = loaded {
        open(loaded)
        return
    }
    selectivePrivacyRequest.set((context.engine.privacy.requestAccountPrivacySettings()
        |> take(1)
        |> deliverOnMainQueue).start(next: { settings in
            open(settings)
        }))
}
