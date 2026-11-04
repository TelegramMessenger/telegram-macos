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
        case .lastSeen:
            presentSelectivePrivacy(context, kind: .presence, present: present)
        case .profilePhoto:
            presentSelectivePrivacy(context, kind: .profilePhoto, present: present)
        case .forwards:
            presentSelectivePrivacy(context, kind: .forwards, present: present)
        case .voiceCalls:
            presentSelectivePrivacy(context, kind: .voiceCalls, present: present)
        case .groups:
            presentSelectivePrivacy(context, kind: .groupInvitations, present: present)
        case .phoneNumber:
            presentSelectivePrivacy(context, kind: .phoneNumber, present: present)
        case .voiceMessages:
            presentSelectivePrivacy(context, kind: .voiceMessages, present: present)
        case .bio:
            presentSelectivePrivacy(context, kind: .bio, present: present)
        case .birthday:
            presentSelectivePrivacy(context, kind: .birthday, present: present)
        case .gifts:
            presentSelectivePrivacy(context, kind: .gifts, present: present)
        case .savedMusic:
            presentSelectivePrivacy(context, kind: .savedMusic, present: present)
        case .deleteAccount:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .accountTimeout, twoStepVerificationConfiguration: nil))
        case .topPeers:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .topPeers, twoStepVerificationConfiguration: nil))
        case .cloudDrafts:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .cloudDraft, twoStepVerificationConfiguration: nil))
        case .messages:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .messages, twoStepVerificationConfiguration: nil))
        case .passkeys:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .passkeys, twoStepVerificationConfiguration: nil))
        case .loginEmail:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .loginEmail, twoStepVerificationConfiguration: nil))
        case .globalTimer:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .globalTimer, twoStepVerificationConfiguration: nil))
        case .webSessions:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .webSessions, twoStepVerificationConfiguration: nil))
        case .secretChatWebPreview:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .secretChatWebPreview, twoStepVerificationConfiguration: nil))
        case .sensitiveContent:
            present(.push, PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: .sensitiveContent, twoStepVerificationConfiguration: nil))
        }
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

private func presentSelectivePrivacy<Context: AccountContextProtocol>(_ context: Context, kind: SelectivePrivacySettingsKind, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
    _ = (context.engine.privacy.requestAccountPrivacySettings()
        |> take(1)
        |> deliverOnMainQueue).start(next: { settings in
            present(.push, selectivePrivacyController(context, kind: kind, settings: settings, updated: { _, _, _, _ in }))
        })
}
