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
            presentSelectivePrivacySettings(context, .presence, environment: environment, present: present)
        case .profilePhoto:
            presentSelectivePrivacySettings(context, .profilePhoto, environment: environment, present: present)
        case .forwards:
            presentSelectivePrivacySettings(context, .forwards, environment: environment, present: present)
        case .voiceCalls:
            presentSelectivePrivacySettings(context, .voiceCalls, environment: environment, present: present)
        case .groups:
            presentSelectivePrivacySettings(context, .groupInvitations, environment: environment, present: present)
        case .phoneNumber:
            presentSelectivePrivacySettings(context, .phoneNumber, environment: environment, present: present)
        case .voiceMessages:
            presentSelectivePrivacySettings(context, .voiceMessages, environment: environment, present: present)
        case .bio:
            presentSelectivePrivacySettings(context, .bio, environment: environment, present: present)
        case .birthday:
            presentSelectivePrivacySettings(context, .birthday, environment: environment, present: present)
        case .gifts:
            presentSelectivePrivacySettings(context, .gifts, environment: environment, present: present)
        case .savedMusic:
            presentSelectivePrivacySettings(context, .savedMusic, environment: environment, present: present)
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

private func presentSelectivePrivacySettings<Context: AccountContextProtocol>(_ context: Context, _ kind: SelectivePrivacySettingsKind, environment: SettingsSearchEnvironment, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
    let privacySignal: Signal<AccountPrivacySettings, NoError>
    if let privacySettings = environment.privacySettings {
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
