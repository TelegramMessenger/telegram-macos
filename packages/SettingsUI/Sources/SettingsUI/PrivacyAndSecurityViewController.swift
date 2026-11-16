import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import AvatarUI
import ShortPeerRow
import TelegramIconsTheme
import ProxyUtils


public enum PrivacyAndSecurityEntryTag: ItemListItemTag {
    case accountTimeout
    case topPeers
    case cloudDraft
    case autoArchive
    public func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? PrivacyAndSecurityEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
    
    fileprivate var stableId: AnyHashable {
        switch self {
        case .accountTimeout:
            return PrivacyAndSecurityEntry.accountTimeout(sectionId: 0, "", viewType: .singleItem).stableId
        case .topPeers:
            return PrivacyAndSecurityEntry.togglePeerSuggestions(sectionId: 0, enabled: false, viewType: .singleItem).stableId
        case .cloudDraft:
            return PrivacyAndSecurityEntry.clearCloudDrafts(sectionId: 0, viewType: .singleItem).stableId
        case .autoArchive:
            return PrivacyAndSecurityEntry.autoArchiveToggle(sectionId: 0, value: false, viewType: .singleItem).stableId
        }
    }
}

private final class PrivacyAndSecurityControllerArguments {
    let context: any AccountContextProtocol
    let openBlockedUsers: () -> Void
    let openLastSeenPrivacy: () -> Void
    let openGroupsPrivacy: () -> Void
    let openVoiceCallPrivacy: () -> Void
    let openBioPrivacy:()->Void
    let openBirthdayPrivacy:()->Void
    let openGiftsPrivacy:()->Void
    let openSavedMusicPrivacy:()->Void
    let openProfilePhotoPrivacy: () -> Void
    let openForwardPrivacy: () -> Void
    let openPhoneNumberPrivacy: () -> Void
    let openVoicePrivacy: () -> Void
    let openMessagesPrivacy: () -> Void
    let openPasskey:([TelegramPasskey])->Void
    let openPasscode: () -> Void
    let openTwoStepVerification: (TwoStepVeriticationAccessConfiguration?) -> Void
    let openActiveSessions: ([RecentAccountSession]?) -> Void
    let openWebAuthorizations: () -> Void
    let setupAccountAutoremove: () -> Void
    let setupGlobalAutoremove: () -> Void
    let openProxySettings:() ->Void
    let togglePeerSuggestions:(Bool)->Void
    let clearCloudDrafts: () -> Void
    let toggleSensitiveContent:(Bool)->Void
    let toggleSecretChatWebPreview: (Bool)->Void
    let toggleAutoArchive: (Bool)->Void
    let setupLoginEmail:(String?)->Void
    init(context: any AccountContextProtocol, openBlockedUsers: @escaping () -> Void, openLastSeenPrivacy: @escaping () -> Void, openGroupsPrivacy: @escaping () -> Void, openVoiceCallPrivacy: @escaping () -> Void, openBioPrivacy: @escaping()->Void, openBirthdayPrivacy:@escaping()->Void, openProfilePhotoPrivacy: @escaping () -> Void, openForwardPrivacy: @escaping () -> Void, openPhoneNumberPrivacy: @escaping() -> Void, openVoicePrivacy: @escaping() -> Void, openMessagesPrivacy: @escaping()->Void, openPasscode: @escaping () -> Void, openPasskey:@escaping([TelegramPasskey])->Void, openTwoStepVerification: @escaping (TwoStepVeriticationAccessConfiguration?) -> Void, openActiveSessions: @escaping ([RecentAccountSession]?) -> Void, openWebAuthorizations: @escaping() -> Void, setupAccountAutoremove: @escaping () -> Void, setupGlobalAutoremove: @escaping()->Void, openProxySettings:@escaping() ->Void, togglePeerSuggestions:@escaping(Bool)->Void, clearCloudDrafts: @escaping() -> Void, toggleSensitiveContent: @escaping(Bool)->Void, toggleSecretChatWebPreview: @escaping(Bool)->Void, toggleAutoArchive: @escaping(Bool)->Void, openGiftsPrivacy:@escaping()->Void, openSavedMusicPrivacy:@escaping()->Void, setupLoginEmail:@escaping(String?)->Void) {
        self.context = context
        self.openBlockedUsers = openBlockedUsers
        self.openLastSeenPrivacy = openLastSeenPrivacy
        self.openGroupsPrivacy = openGroupsPrivacy
        self.openVoiceCallPrivacy = openVoiceCallPrivacy
        self.openBioPrivacy = openBioPrivacy
        self.openPasscode = openPasscode
        self.openPasskey = openPasskey
        self.openTwoStepVerification = openTwoStepVerification
        self.openActiveSessions = openActiveSessions
        self.openWebAuthorizations = openWebAuthorizations
        self.setupAccountAutoremove = setupAccountAutoremove
        self.setupGlobalAutoremove = setupGlobalAutoremove
        self.openProxySettings = openProxySettings
        self.togglePeerSuggestions = togglePeerSuggestions
        self.clearCloudDrafts = clearCloudDrafts
        self.openProfilePhotoPrivacy = openProfilePhotoPrivacy
        self.openForwardPrivacy = openForwardPrivacy
        self.openPhoneNumberPrivacy = openPhoneNumberPrivacy
        self.openVoicePrivacy = openVoicePrivacy
        self.openMessagesPrivacy = openMessagesPrivacy
        self.toggleSensitiveContent = toggleSensitiveContent
        self.toggleSecretChatWebPreview = toggleSecretChatWebPreview
        self.toggleAutoArchive = toggleAutoArchive
        self.openBirthdayPrivacy = openBirthdayPrivacy
        self.openGiftsPrivacy = openGiftsPrivacy
        self.openSavedMusicPrivacy = openSavedMusicPrivacy
        self.setupLoginEmail = setupLoginEmail
    }
}


private enum PrivacyAndSecurityEntry: Comparable, Identifiable {
    case privacyHeader(sectionId:Int)
    case twoStepVerification(sectionId:Int, configuration: TwoStepVeriticationAccessConfiguration?, viewType: GeneralViewType)
    case passkeys(sectionId:Int, passkeys: [TelegramPasskey], viewType: GeneralViewType)
    case passcode(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case blockedPeers(sectionId:Int, Int?, viewType: GeneralViewType)
    case phoneNumberPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case lastSeenPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case groupPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case profilePhotoPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case forwardPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case voiceCallPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case voiceMessagesPrivacy(sectionId: Int, String, Bool, viewType: GeneralViewType)
    case messagesPrivacy(sectionId: Int, String, Bool, viewType: GeneralViewType)
    case bioPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case birthdayPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case savedMusicPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case giftsPrivacy(sectionId: Int, String, viewType: GeneralViewType)
    case securityHeader(sectionId:Int)
    case globalTimer(sectionId: Int, String, viewType: GeneralViewType)
    case globalTimerInfo(sectionId:Int)
    case loginEmail(sectionId: Int, pattern: String?, viewType: GeneralViewType)
    case loginEmailInfo(sectionId: Int, String, viewType: GeneralViewType)
    case activeSessions(sectionId:Int, [RecentAccountSession]?, viewType: GeneralViewType)
    case webAuthorizationsHeader(sectionId: Int)
    case webAuthorizations(sectionId:Int, viewType: GeneralViewType)
    case accountHeader(sectionId:Int)
    case accountTimeout(sectionId: Int, String, viewType: GeneralViewType)
    case accountInfo(sectionId:Int)
    case proxyHeader(sectionId:Int)
    case proxySettings(sectionId:Int, String, viewType: GeneralViewType)
    case togglePeerSuggestions(sectionId: Int, enabled: Bool, viewType: GeneralViewType)
    case togglePeerSuggestionsDesc(sectionId: Int)
    case sensitiveContentHeader(sectionId: Int)
    case autoArchiveToggle(sectionId: Int, value: Bool?, viewType: GeneralViewType)
    case autoArchiveDesc(sectionId: Int)
    case autoArchiveHeader(sectionId: Int)
    case sensitiveContentToggle(sectionId: Int, value: Bool?, viewType: GeneralViewType)
    case sensitiveContentDesc(sectionId: Int)
    case clearCloudDraftsHeader(sectionId: Int)
    case clearCloudDrafts(sectionId: Int, viewType: GeneralViewType)

    case secretChatWebPreviewHeader(sectionId: Int)
    case secretChatWebPreviewToggle(sectionId: Int, value: Bool?, viewType: GeneralViewType)
    case secretChatWebPreviewDesc(sectionId: Int)
    
    case section(sectionId:Int)

    var sectionId: Int {
        switch self {
        case let .privacyHeader(sectionId):
            return sectionId
        case let .blockedPeers(sectionId, _, _):
            return sectionId
        case let .phoneNumberPrivacy(sectionId, _, _):
            return sectionId
        case let .lastSeenPrivacy(sectionId, _, _):
            return sectionId
        case let .groupPrivacy(sectionId, _, _):
            return sectionId
        case let .profilePhotoPrivacy(sectionId, _, _):
            return sectionId
        case let .forwardPrivacy(sectionId, _, _):
            return sectionId
        case let .voiceCallPrivacy(sectionId, _, _):
            return sectionId
        case let .voiceMessagesPrivacy(sectionId, _, _, _):
            return sectionId
        case let .messagesPrivacy(sectionId, _, _, _):
            return sectionId
        case let .bioPrivacy(sectionId, _, _):
            return sectionId
        case let .birthdayPrivacy(sectionId, _, _):
            return sectionId
        case let .savedMusicPrivacy(sectionId, _, _):
            return sectionId
        case let .giftsPrivacy(sectionId, _, _):
            return sectionId
        case let .securityHeader(sectionId):
            return sectionId
        case let .passcode(sectionId, _, _):
            return sectionId
        case let .passkeys(sectionId, _, _):
            return sectionId
        case let .twoStepVerification(sectionId, _, _):
            return sectionId
        case let .globalTimer(sectionId, _, _):
            return sectionId
        case let .globalTimerInfo(sectionId):
            return sectionId
        case let .loginEmail(sectionId, _, _):
            return sectionId
        case let .loginEmailInfo(sectionId, _, _):
            return sectionId
        case let .activeSessions(sectionId, _, _):
            return sectionId
        case let .webAuthorizationsHeader(sectionId):
            return sectionId
        case let .webAuthorizations(sectionId, _):
            return sectionId
        case let .autoArchiveHeader(sectionId):
            return sectionId
        case let .autoArchiveToggle(sectionId, _, _):
            return sectionId
        case let .autoArchiveDesc(sectionId):
            return sectionId
        case let .accountHeader(sectionId):
            return sectionId
        case let .accountTimeout(sectionId, _, _):
            return sectionId
        case let .accountInfo(sectionId):
            return sectionId
        case let .togglePeerSuggestions(sectionId, _, _):
            return sectionId
        case let .togglePeerSuggestionsDesc(sectionId):
            return sectionId
        case let .clearCloudDraftsHeader(sectionId):
            return sectionId
        case let .clearCloudDrafts(sectionId, _):
            return sectionId
        case let .proxyHeader(sectionId):
            return sectionId
        case let .proxySettings(sectionId, _, _):
            return sectionId
        case let .sensitiveContentHeader(sectionId):
            return sectionId
        case let .sensitiveContentToggle(sectionId, _, _):
            return sectionId
        case let .sensitiveContentDesc(sectionId):
            return sectionId
        case let .secretChatWebPreviewHeader(sectionId):
            return sectionId
        case let .secretChatWebPreviewToggle(sectionId, _, _):
            return sectionId
        case let .secretChatWebPreviewDesc(sectionId):
            return sectionId
        case let .section(sectionId):
            return sectionId
        }
    }
    

    var stableId:Int {
        switch self {
        case .twoStepVerification:
            return 0
        case .passkeys:
            return 1
        case .passcode:
            return 2
        case .blockedPeers:
            return 3
        case .activeSessions:
            return 4
        case .globalTimer:
            return 5
        case .globalTimerInfo:
            return 6
        case .loginEmail:
            return 7
        case .loginEmailInfo:
            return 8
        case .privacyHeader:
            return 9
        case .phoneNumberPrivacy:
            return 10
        case .lastSeenPrivacy:
            return 11
        case .groupPrivacy:
            return 12
        case .voiceCallPrivacy:
            return 13
        case .forwardPrivacy:
            return 14
        case .profilePhotoPrivacy:
            return 15
        case .voiceMessagesPrivacy:
            return 16
        case .messagesPrivacy:
            return 17
        case .bioPrivacy:
            return 18
        case .giftsPrivacy:
            return 19
        case .birthdayPrivacy:
            return 20
        case .savedMusicPrivacy:
            return 21
        case .securityHeader:
            return 22
        case .autoArchiveHeader:
            return 23
        case .autoArchiveToggle:
            return 24
        case .autoArchiveDesc:
            return 25
        case .accountHeader:
            return 26
        case .accountTimeout:
            return 27
        case .accountInfo:
            return 28
        case .webAuthorizationsHeader:
            return 29
        case .webAuthorizations:
            return 30
        case .proxyHeader:
            return 31
        case .proxySettings:
            return 32
        case .togglePeerSuggestions:
            return 33
        case .togglePeerSuggestionsDesc:
            return 34
        case .clearCloudDraftsHeader:
            return 35
        case .clearCloudDrafts:
            return 36
        case .sensitiveContentHeader:
            return 37
        case .sensitiveContentToggle:
            return 38
        case .sensitiveContentDesc:
            return 39
        case .secretChatWebPreviewHeader:
            return 40
        case .secretChatWebPreviewToggle:
            return 41
        case .secretChatWebPreviewDesc:
            return 42
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        }
    }


    private var stableIndex:Int {
        switch self {
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        default:
            return (sectionId * 1000) + stableId
        }

    }

    static func <(lhs: PrivacyAndSecurityEntry, rhs: PrivacyAndSecurityEntry) -> Bool {
        return lhs.stableIndex < rhs.stableIndex
    }
    func item(_ arguments: PrivacyAndSecurityControllerArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case .privacyHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacySettingsPrivacyHeader, viewType: .textTopItem)
        case let .blockedPeers(_, count, viewType):
            let text: String
            if let count = count, count > 0 {
                text = strings().privacyAndSecurityBlockedUsers("\(count)")
            } else {
                text = ""
            }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsBlockedUsers, icon: theme.icons.privacySettings_blocked, type: .nextContext(text), viewType: viewType, action: {
                arguments.openBlockedUsers()
            })
        case let .phoneNumberPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsPhoneNumber, type: .nextContext(text), viewType: viewType, action: {
                arguments.openPhoneNumberPrivacy()
            })
        case let .lastSeenPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsLastSeen, type: .nextContext(text), viewType: viewType, action: {
                arguments.openLastSeenPrivacy()
            })
        case let .groupPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsGroups, type: .nextContext(text), viewType: viewType, action: {
                arguments.openGroupsPrivacy()
            })
        case let .profilePhotoPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsProfilePhoto, type: .nextContext(text), viewType: viewType, action: {
                arguments.openProfilePhotoPrivacy()
            })
        case let .forwardPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsForwards, type: .nextContext(text), viewType: viewType, action: {
                arguments.openForwardPrivacy()
            })
        case let .voiceCallPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsVoiceCalls, type: .nextContext(text), viewType: viewType, action: {
                arguments.openVoiceCallPrivacy()
            })
        case let .voiceMessagesPrivacy(_, text, _, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsVoiceMessages, type: .nextContext(text), viewType: viewType, action: arguments.openVoicePrivacy)
        case let .messagesPrivacy(_, text, _, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsMessages, type: .nextContext(text), viewType: viewType, action: arguments.openMessagesPrivacy)
        case let .bioPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsBio, type: .nextContext(text), viewType: viewType, action: {
                arguments.openBioPrivacy()
            })
        case let .birthdayPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsBirthday, type: .nextContext(text), viewType: viewType, action: {
                arguments.openBirthdayPrivacy()
            })
        case let .savedMusicPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(
                initialSize,
                stableId: stableId,
                name: strings().privacySettingsSavedMusic,
                type: .nextContext(text),
                viewType: viewType,
                action: arguments.openSavedMusicPrivacy
            )
        case let .giftsPrivacy(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsGifts, type: .nextContext(text), viewType: viewType, action: {
                arguments.openGiftsPrivacy()
            })
        case .securityHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacySettingsSecurityHeader, viewType: .textTopItem)
        case let .passcode(_, enabled, viewType):
            let desc = enabled ? strings().privacyAndSecurityItemOn : strings().privacyAndSecurityItemOff
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsPasscode, icon: theme.icons.privacySettings_passcode, type: .nextContext(desc), viewType: viewType, action: {
                arguments.openPasscode()
            })
        case let .passkeys(_, passkeys, viewType):
            let desc = !passkeys.isEmpty ? strings().privacyAndSecurityItemOn : strings().privacyAndSecurityItemOff
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsPasskey, icon: generateSettingsIcon(TelegramThemeHooks.shared.image(.iconPasskeySettings).precomposed(flipVertical: true)), type: .nextContext(desc), viewType: viewType, action: {
                arguments.openPasskey(passkeys)
            })
        case let .twoStepVerification(_, configuration, viewType):
            let desc: String 
            if let configuration = configuration {
                switch configuration {
                case .set:
                    desc = strings().privacyAndSecurityItemOn
                case .notSet:
                    desc = strings().privacyAndSecurityItemOff
                }
            } else {
                desc = ""
            }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsTwoStepVerification, icon: theme.icons.privacySettings_twoStep, type: .nextContext(desc), viewType: viewType, action: {
                arguments.openTwoStepVerification(configuration)
            })
        case let .globalTimer(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsGlobalTimer, icon: theme.icons.privacy_settings_autodelete, type: .nextContext(text), viewType: viewType, action: arguments.setupGlobalAutoremove)
        case .globalTimerInfo:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacySettingsGlobalTimerInfo, viewType: .textBottomItem)
        case let .loginEmail(_, pattern, viewType):
            let image = TelegramThemeHooks.shared.image(.iconPrivacySettingsEmail).precomposed(flipVertical: true)
            
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsLoginEmail, icon: generateSettingsIcon(image), type: .next, viewType: viewType, action: {
                arguments.setupLoginEmail(pattern)
            })
        case let .loginEmailInfo(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: viewType)
        case let .activeSessions(_, sessions, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsActiveSessions, icon: theme.icons.privacySettings_activeSessions, type: .nextContext(sessions != nil ? "\(sessions!.count)" : ""), viewType: viewType, action: {
                arguments.openActiveSessions(sessions)
            })
        case .webAuthorizationsHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecurityWebAuthorizationHeader, viewType: .textTopItem)
        case let .webAuthorizations(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().telegramWebSessionsController, viewType: viewType, action: {
                arguments.openWebAuthorizations()
            })
        case .accountHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacySettingsDeleteAccountHeader, viewType: .textTopItem)
        case let .accountTimeout(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsDeleteAccount, type: .context(text), viewType: viewType, action: {
                arguments.setupAccountAutoremove()
            })
        case .accountInfo:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacySettingsDeleteAccountDescription, viewType: .textBottomItem)
        case .proxyHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacySettingsProxyHeader, viewType: .textTopItem)
        case let .proxySettings(_, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacySettingsUseProxy, type: .nextContext(text), viewType: viewType, action: {
                arguments.openProxySettings()
            })
        case let .togglePeerSuggestions(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().suggestFrequentContacts, type: .switchable(enabled), viewType: viewType, action: {
                if enabled {
                    verifyAlert_button(for: arguments.context.window, information: strings().suggestFrequentContactsAlert, successHandler: { _ in
                        arguments.togglePeerSuggestions(!enabled)
                    })
                } else {
                    arguments.togglePeerSuggestions(!enabled)
                }
            }, autoswitch: false)
        case .togglePeerSuggestionsDesc:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().suggestFrequentContactsDesc, viewType: .textBottomItem)
        case .clearCloudDraftsHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecurityClearCloudDraftsHeader, viewType: .textTopItem)
        case let .clearCloudDrafts(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacyAndSecurityClearCloudDrafts, type: .none, viewType: viewType, action: {
                arguments.clearCloudDrafts()
            })
        case .autoArchiveHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecurityAutoArchiveHeader, viewType: .textTopItem)
        case let .autoArchiveToggle(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacyAndSecurityAutoArchiveText, type: enabled != nil ? .switchable(enabled!) : .loading, viewType: viewType, action: {
                if let enabled = enabled {
                    arguments.toggleAutoArchive(!enabled)
                } else {
                    arguments.toggleAutoArchive(true)
                }
            }, autoswitch: true)
        case .autoArchiveDesc:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecurityAutoArchiveDesc, viewType: .textBottomItem)
        case .sensitiveContentHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecuritySensitiveHeader, viewType: .textTopItem)
        case let .sensitiveContentToggle(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacyAndSecuritySensitiveText, type: enabled != nil ? .switchable(enabled!) : .loading, viewType: viewType, action: {
                if let enabled = enabled {
                    arguments.toggleSensitiveContent(!enabled)
                }
            }, autoswitch: true)
        case .sensitiveContentDesc:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecuritySensitiveDesc, viewType: .textBottomItem)
        case .secretChatWebPreviewHeader:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecuritySecretChatWebPreviewHeader, viewType: .textTopItem)
        case let .secretChatWebPreviewToggle(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().privacyAndSecuritySecretChatWebPreviewText, type: enabled != nil ? .switchable(enabled!) : .loading, viewType: viewType, action: {
                if let enabled = enabled {
                    arguments.toggleSecretChatWebPreview(!enabled)
                }
            }, autoswitch: true)
        case .secretChatWebPreviewDesc:
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().privacyAndSecuritySecretChatWebPreviewDesc, viewType: .textBottomItem)
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        }
    }
}

func countForSelectivePeers(_ peers: [PeerId: SelectivePrivacyPeer], enablePremium: Bool = false) -> Int {
    var result = 0
    for (_, peer) in peers {
        result += peer.userCount
    }
    return result
}


func stringForSelectiveSettings(settings: SelectivePrivacySettings) -> String {
    switch settings {
    case let .disableEveryone(enableFor, _, enableForPremium, _):
        if enableFor.isEmpty {
            if enableForPremium {
                return strings().privacySettingsPremiumUsers
            } else {
                return strings().privacySettingsControllerNobody
            }
        } else {
            return strings().privacySettingsLastSeenNobodyPlus("\(countForSelectivePeers(enableFor))") + "\(enableForPremium ? " , \(strings().privacySettingsPremiumUsers)" : "")"
        }
    case let .enableEveryone(disableFor):
        if disableFor.isEmpty {
            return strings().privacySettingsControllerEverbody
        } else {
            return strings().privacySettingsLastSeenEverybodyMinus("\(countForSelectivePeers(disableFor))")
        }
    case let .enableContacts(enableFor, disableFor, enableForPremium, _):
        if !enableFor.isEmpty && !disableFor.isEmpty {
            return strings().privacySettingsLastSeenContactsMinusPlus("\(countForSelectivePeers(disableFor))", "\(countForSelectivePeers(enableFor))")
        } else if !enableFor.isEmpty {
            return strings().privacySettingsLastSeenContactsPlus("\(countForSelectivePeers(enableFor))") + "\(enableForPremium ? ", \(strings().privacySettingsPremiumUsers)" : "")"
        } else if !disableFor.isEmpty {
            return strings().privacySettingsLastSeenContactsMinus("\(countForSelectivePeers(disableFor))")
        } else {
            return strings().privacySettingsControllerMyContacts
        }
    }
}

private struct PrivacyAndSecurityControllerState: Equatable {
    var updatingAccountTimeoutValue: Int32?
    var updatingGlobalTimeoutValue: Int32?
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<PrivacyAndSecurityEntry>], right: [AppearanceWrapperEntry<PrivacyAndSecurityEntry>], initialSize:NSSize, arguments:PrivacyAndSecurityControllerArguments) -> TableUpdateTransition {

    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }

    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

private func entries(state: PrivacyAndSecurityControllerState, contentConfiguration: ContentSettingsConfiguration?, privacySettings: AccountPrivacySettings?, webSessions: WebSessionsContextState, blockedState: BlockedPeersContextState, proxy: ProxySettings, recentPeers: RecentPeers, configuration: TwoStepVeriticationAccessConfiguration?, activeSessions: ActiveSessionsContextState, passcodeData: PostboxAccessChallengeData, context: any AccountContextProtocol, loginEmail: String?, passkeysDataValue: [TelegramPasskey]?, displayPasskeys: Bool) -> [PrivacyAndSecurityEntry] {
    var entries: [PrivacyAndSecurityEntry] = []

    var sectionId:Int = 1
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    let hasPasscode: Bool
    switch passcodeData {
    case .none:
        hasPasscode = false
    default:
        hasPasscode = context.sharedContext.appEncryptionValue.hasPasscode()
    }
    entries.append(.twoStepVerification(sectionId: sectionId, configuration: configuration, viewType: .firstItem))
    
    let displayPasskeys = displayPasskeys && context.appConfiguration.getBoolValue("settings_display_passkeys", orElse: false)
    
    if displayPasskeys {
        let passkeys: [TelegramPasskey] = passkeysDataValue ?? []
        entries.append(.passkeys(sectionId: sectionId, passkeys: passkeys, viewType: .innerItem))
    }

    
    entries.append(.passcode(sectionId: sectionId, enabled: hasPasscode, viewType: .innerItem))


    entries.append(.blockedPeers(sectionId: sectionId, blockedState.totalCount, viewType: .innerItem))
   // entries.append(.activeSessions(sectionId: sectionId, activeSessions, viewType: .innerItem))
    
    
    if let privacySettings = privacySettings {
        let value: Int32
        if let updatingAccountTimeoutValue = state.updatingGlobalTimeoutValue {
            value = updatingAccountTimeoutValue
        } else {
            value = privacySettings.messageAutoremoveTimeout ?? 0
        }
        if value != 0 {
            entries.append(.globalTimer(sectionId: sectionId, timeIntervalString(Int(value)), viewType: .lastItem))
        } else {
            entries.append(.globalTimer(sectionId: sectionId, strings().privacySettingsGlobalTimerNever, viewType: .lastItem))
        }

    } else {
        entries.append(.globalTimer(sectionId: sectionId, "", viewType: .lastItem))
    }
    entries.append(.globalTimerInfo(sectionId: sectionId))
    

    var showLoginEmail = false
    if let _ = loginEmail {
        showLoginEmail = true
    } else if let phone = (context.myPeer as? TelegramUser)?.phone, phone.hasPrefix("7") {
        showLoginEmail = true
    } else if appAppearance.languageCode == "ru" {
        showLoginEmail = true
    } else if context.debug {
        showLoginEmail = true
    }
    if showLoginEmail {
        
        entries.append(.section(sectionId: sectionId))
        sectionId += 1

        
        var hasLoginEmail = false
        if let loginEmail {
            hasLoginEmail = !loginEmail.contains(" ")
        }
        entries.append(.loginEmail(sectionId: sectionId, pattern: loginEmail, viewType: .singleItem))
        entries.append(.loginEmailInfo(sectionId: sectionId, !hasLoginEmail ? strings().privacySettingsLoginEmailSetupInfo : strings().privacySettingsLoginEmailInfo, viewType: .textBottomItem))
    }


    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.privacyHeader(sectionId: sectionId))
    if let privacySettings = privacySettings {
        entries.append(.phoneNumberPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.phoneNumber), viewType: .firstItem))
        entries.append(.lastSeenPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.presence), viewType: .innerItem))
        entries.append(.groupPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.groupInvitations), viewType: .innerItem))
        entries.append(.voiceCallPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.voiceCalls), viewType: .innerItem))
        entries.append(.profilePhotoPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.profilePhoto), viewType: .innerItem))
        entries.append(.bioPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.bio), viewType: .innerItem))
        entries.append(.giftsPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.giftsAutoSave), viewType: .innerItem))
        entries.append(.birthdayPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.birthday), viewType: .innerItem))
        entries.append(.savedMusicPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.savedMusic), viewType: .innerItem))
        entries.append(.forwardPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.forwards), viewType: .innerItem))
        entries.append(.voiceMessagesPrivacy(sectionId: sectionId, stringForSelectiveSettings(settings: privacySettings.voiceMessages), !context.isPremium, viewType: .innerItem))
        
        let messagePrivacyText: String
        switch privacySettings.globalSettings.nonContactChatsPrivacy {
        case .everybody:
            messagePrivacyText = strings().privacySettingsMessagesAll
        case .requirePremium:
            messagePrivacyText = strings().privacySettingsMessagesMyContacts
        case .paidMessages(let starsAmount):
            messagePrivacyText = strings().starListItemCountOther(Int(starsAmount.value))
        }
        entries.append(.messagesPrivacy(sectionId: sectionId, messagePrivacyText, false, viewType: .lastItem))
        
    } else {
        entries.append(.phoneNumberPrivacy(sectionId: sectionId, "", viewType: .firstItem))
        entries.append(.lastSeenPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.groupPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.voiceCallPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.profilePhotoPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.bioPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.birthdayPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.giftsPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.forwardPrivacy(sectionId: sectionId, "", viewType: .innerItem))
        entries.append(.voiceMessagesPrivacy(sectionId: sectionId, "", !context.isPremium, viewType: .lastItem))
    }


    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
//    
//    let autoarchiveConfiguration = AutoarchiveConfiguration.with(appConfiguration: context.appConfiguration)
//
//    
//    if autoarchiveConfiguration.autoarchive_setting_available {
//        entries.append(.autoArchiveHeader(sectionId: sectionId))
//        entries.append(.autoArchiveToggle(sectionId: sectionId, value: privacySettings?.globalSettings.automaticallyArchiveAndMuteNonContacts, viewType: .singleItem))
//        entries.append(.autoArchiveDesc(sectionId: sectionId))
//        
//        entries.append(.section(sectionId: sectionId))
//        sectionId += 1
//    }

    entries.append(.accountHeader(sectionId: sectionId))


    if let privacySettings = privacySettings {
        let value: Int32
        if let updatingAccountTimeoutValue = state.updatingAccountTimeoutValue {
            value = updatingAccountTimeoutValue
        } else {
            value = privacySettings.accountRemovalTimeout
        }
        entries.append(.accountTimeout(sectionId: sectionId, timeIntervalString(Int(value), months: true), viewType: .singleItem))

    } else {
        entries.append(.accountTimeout(sectionId: sectionId, "", viewType: .singleItem))
    }
    entries.append(.accountInfo(sectionId: sectionId))

    

    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    if let contentConfiguration = contentConfiguration, contentConfiguration.canAdjustSensitiveContent {
        #if !APP_STORE
        entries.append(.sensitiveContentHeader(sectionId: sectionId))
        entries.append(.sensitiveContentToggle(sectionId: sectionId, value: contentConfiguration.sensitiveContentEnabled, viewType: .singleItem))
        entries.append(.sensitiveContentDesc(sectionId: sectionId))
        
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
        #endif
    }
    

    let enabled: Bool
    switch recentPeers {
    case .disabled:
        enabled = false
    case .peers:
        enabled = true
    }

    entries.append(.togglePeerSuggestions(sectionId: sectionId, enabled: enabled, viewType: .singleItem))
    entries.append(.togglePeerSuggestionsDesc(sectionId: sectionId))

    entries.append(.section(sectionId: sectionId))
    sectionId += 1

    entries.append(.clearCloudDraftsHeader(sectionId: sectionId))
    entries.append(.clearCloudDrafts(sectionId: sectionId, viewType: .singleItem))

    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    

    if !webSessions.sessions.isEmpty {
        entries.append(.webAuthorizationsHeader(sectionId: sectionId))
        entries.append(.webAuthorizations(sectionId: sectionId, viewType: .singleItem))
        
        if FastSettings.isSecretChatWebPreviewAvailable(for: context.account.id.int64) != nil {
            entries.append(.section(sectionId: sectionId))
            sectionId += 1
        }
    }
    
    if let value = FastSettings.isSecretChatWebPreviewAvailable(for: context.account.id.int64) {
        entries.append(.secretChatWebPreviewHeader(sectionId: sectionId))
        entries.append(.secretChatWebPreviewToggle(sectionId: sectionId, value: value, viewType: .singleItem))
        entries.append(.secretChatWebPreviewDesc(sectionId: sectionId))
    }

    entries.append(.section(sectionId: sectionId))
    sectionId += 1

    return entries
}





open class PrivacyAndSecurityViewController<Context: AccountContextProtocol>: TableViewController<Context> {

    open override var defaultBarTitle: String {
        return strings().telegramPrivacyAndSecurityViewController
    }
    private let privacySettingsPromise = Promise<AccountPrivacySettings?>()
    private let currentInfoDisposable = MetaDisposable()


    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    open override func readyToDetach() {
        super.readyToDetach()
        self.currentInfoDisposable.set(nil)
    }

    private let twoStepAccessConfiguration: Promise<TwoStepVeriticationAccessConfiguration?> = Promise(nil)

    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        twoStepAccessConfiguration.set(context.engine.auth.twoStepVerificationConfiguration() |> map { .init(configuration: $0, password: nil) })
    }
    open override func viewDidLoad() {
        super.viewDidLoad()

        
        let statePromise = ValuePromise(PrivacyAndSecurityControllerState(), ignoreRepeated: true)
        let stateValue = Atomic(value: PrivacyAndSecurityControllerState())
        let updateState: ((PrivacyAndSecurityControllerState) -> PrivacyAndSecurityControllerState) -> Void = { f in
            statePromise.set(stateValue.modify { f($0) })
        }

        let actionsDisposable = DisposableSet()
        let context = self.context

        let pushControllerImpl: (ViewController) -> Void = { [weak self] c in
            self?.navigationController?.push(c)
        }


        let settings:Signal<ProxySettings, NoError> = proxySettings(accountManager: context.sharedContext.accountManager)

        let currentInfoDisposable = self.currentInfoDisposable
        actionsDisposable.add(currentInfoDisposable)

        let updateAccountTimeoutDisposable = MetaDisposable()
        actionsDisposable.add(updateAccountTimeoutDisposable)

        
        let updatePasskeyDataDisposable = MetaDisposable()
        actionsDisposable.add(updatePasskeyDataDisposable)
        
        let privacySettingsPromise = self.privacySettingsPromise
        let loadedPrivacySettings = privacySettingsPromise.get()
            |> filter { $0 != nil }
            |> take(1)
            |> deliverOnMainQueue
            |> filter { [weak self] _ in
                return self?.navigationController?.controller === self && !hasModals(context.window)
            }

        let arguments = PrivacyAndSecurityControllerArguments(context: context, openBlockedUsers: { [weak self] in
            if let context = self?.context {
                pushControllerImpl(BlockedPeersViewController(context))
            }
        }, openLastSeenPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .presence, current: info.presence, callSettings: nil, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, _, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: updated, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openGroupsPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .groupInvitations, current: info.groupInvitations, callSettings: nil, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, _, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: updated, voiceCalls: value.voiceCalls, voiceCallsP2P: value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openVoiceCallPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .voiceCalls, current: info.voiceCalls, callSettings: info.voiceCallsP2P, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, p2pUpdated, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: updated, voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openBioPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .bio, current: info.bio, callSettings: nil, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, p2pUpdated, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: updated, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openBirthdayPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .birthday, current: info.birthday, callSettings: nil, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, p2pUpdated, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: updated, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openProfilePhotoPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .profilePhoto, current: info.profilePhoto, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, _, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: value.voiceCallsP2P, profilePhoto: updated, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openForwardPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .forwards, current: info.forwards, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, _, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: updated, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openPhoneNumberPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .phoneNumber, current: info.phoneNumber, phoneDiscoveryEnabled: info.phoneDiscoveryEnabled, updated: { updated, _, phoneDiscoveryEnabled, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: updated, phoneDiscoveryEnabled: phoneDiscoveryEnabled!, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openVoicePrivacy: { [currentInfoDisposable] in
        
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .voiceMessages, current: info.voiceMessages, callSettings: info.voiceCallsP2P, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, p2pUpdated, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: updated, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openMessagesPrivacy: {
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { info in
                if let info = info {
                    pushControllerImpl(MessagesPrivacyController(context: context, noPaidMessages: info.noPaidMessages, globalSettings: info.globalSettings, updated: { (noPaidMessages, updated) in
                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: info.presence, groupInvitations: info.groupInvitations, voiceCalls: info.voiceCalls, voiceCallsP2P: info.voiceCallsP2P, profilePhoto: info.profilePhoto, forwards: info.forwards, phoneNumber: info.phoneNumber, phoneDiscoveryEnabled: info.phoneDiscoveryEnabled, voiceMessages: info.voiceMessages, bio: info.bio, birthday: info.birthday, giftsAutoSave: info.giftsAutoSave, noPaidMessages: noPaidMessages, savedMusic: info.savedMusic, globalSettings: updated, accountRemovalTimeout: info.accountRemovalTimeout, messageAutoremoveTimeout: info.messageAutoremoveTimeout)))
                    }))
                }
            }))
        }, openPasscode: { [weak self] in
            if let context = self?.context {
                self?.navigationController?.push(SettingsNavigationHooks.shared.makePasscodeSettingsController(context))
            }
        }, openPasskey: { [weak self] passkeys in
            if #available(macOS 12.0, *) {
                showModal(with: SettingsNavigationHooks.shared.makePasskeysController(context, passkeys), for: context.window, morphSource: { [weak self] in
                    guard let self, let index = self.genericView.index(hash: PrivacyAndSecurityEntry.passkeys(sectionId: 0, passkeys: [], viewType: .singleItem).stableId) else { return nil }
                    return (self.genericView.viewNecessary(at: index) as? GeneralContainableRowView)?.containerView
                })
            }
        }, openTwoStepVerification: { [weak self] configuration in
            if let context = self?.context, let `self` = self {
                self.navigationController?.push(twoStepVerificationUnlockController(context: context, mode: .access(configuration), presentController: { [weak self] controller, isRoot, animated in
                    guard let `self` = self, let navigation = self.navigationController else {return}
                    if isRoot {
                        navigation.removeUntil(PrivacyAndSecurityViewController.self)
                    }

                    if !animated {
                        navigation.stackInsert(controller, at: navigation.stackCount)
                    } else {
                        navigation.push(controller)
                    }
                }))
            }
        }, openActiveSessions: { [weak self] sessions in
            if let context = self?.context {
                self?.navigationController?.push(SettingsNavigationHooks.shared.makeRecentSessionsController(context))
            }
        }, openWebAuthorizations: {
            pushControllerImpl(SettingsNavigationHooks.shared.makeWebSessionsController(context))
        }, setupAccountAutoremove: { [weak self, updateAccountTimeoutDisposable] in

            if let strongSelf = self {
                let signal = privacySettingsPromise.get()
                    |> take(1)
                    |> deliverOnMainQueue
                updateAccountTimeoutDisposable.set(signal.start(next: { [weak updateAccountTimeoutDisposable, weak strongSelf] privacySettingsValue in
                    if let _ = privacySettingsValue, let strongSelf = strongSelf {

                        let timeoutAction: (Int32) -> Void = { timeout in
                            if let updateAccountTimeoutDisposable = updateAccountTimeoutDisposable {
                                updateState { current in
                                    var current = current
                                    current.updatingAccountTimeoutValue = timeout
                                    return current
                                }
                                let applyTimeout: Signal<Void, NoError> = privacySettingsPromise.get()
                                    |> filter { $0 != nil }
                                    |> take(1)
                                    |> deliverOnMainQueue
                                    |> mapToSignal { value -> Signal<Void, NoError> in
                                        if let value = value {
                                            privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: value.globalSettings, accountRemovalTimeout: timeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                        }
                                        return .complete()
                                }
                                updateAccountTimeoutDisposable.set((context.engine.privacy.updateAccountRemovalTimeout(timeout: timeout)
                                    |> then(applyTimeout)
                                    |> deliverOnMainQueue).start())
                            }
                        }
                        let timeoutValues: [Int32] = [
                            1 * 30 * 24 * 60 * 60,
                            3 * 30 * 24 * 60 * 60,
                            180 * 24 * 60 * 60,
                            365 * 24 * 60 * 60,
                            548 * 24 * 60 * 60,
                            730 * 24 * 60 * 60
                        ]
                        var items: [ContextMenuItem] = []

                        items.append(ContextMenuItem(strings().timerMonthsOther(1), handler: {
                            timeoutAction(timeoutValues[0])
                        }))
                        items.append(ContextMenuItem(strings().timerMonthsOther(3), handler: {
                            timeoutAction(timeoutValues[1])
                        }))
                        items.append(ContextMenuItem(strings().timerMonthsOther(6), handler: {
                            timeoutAction(timeoutValues[2])
                        }))
                        items.append(ContextMenuItem(strings().timerMonthsOther(12), handler: {
                            timeoutAction(timeoutValues[3])
                        }))
                        items.append(ContextMenuItem(strings().timerMonthsOther(18), handler: {
                            timeoutAction(timeoutValues[4])
                        }))
                        items.append(ContextMenuItem(strings().timerMonthsOther(24), handler: {
                            timeoutAction(timeoutValues[5])
                        }))

                        let stableId = PrivacyAndSecurityEntry.accountTimeout(sectionId: 0, "", viewType: .singleItem).stableId
                        
                        if let index = strongSelf.genericView.index(hash: stableId) {
                            if let view = (strongSelf.genericView.viewNecessary(at: index) as? GeneralInteractedRowView)?.textView {
                                if let event = NSApp.currentEvent {
                                    let menu = ContextMenu()
                                    for item in items {
                                        menu.addItem(item)
                                    }
                                    let value = AppMenu(menu: menu)
                                    value.show(event: event, view: view)
                                }
                            }
                        }
                    }
                }))
            }
        }, setupGlobalAutoremove: { [weak self, updateAccountTimeoutDisposable, currentInfoDisposable] in
            if let strongSelf = self {
                let signal = loadedPrivacySettings
                currentInfoDisposable.set(signal.start(next: { [weak updateAccountTimeoutDisposable, weak strongSelf] privacySettingsValue in
                    if privacySettingsValue != nil, let strongSelf = strongSelf {

                        let timeoutAction: (Int32, Bool) -> Void = { timeout, save in
                            if let updateAccountTimeoutDisposable = updateAccountTimeoutDisposable {
                                updateState { current in
                                    var current = current
                                    current.updatingGlobalTimeoutValue = timeout
                                    return current
                                }
                                let applyTimeout: Signal<Void, NoError> = privacySettingsPromise.get()
                                    |> filter { $0 != nil }
                                    |> take(1)
                                    |> deliverOnMainQueue
                                    |> mapToSignal { value -> Signal<Void, NoError> in
                                        if let value = value {
                                            privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: timeout)))
                                        }
                                        return .complete()
                                }
                                updateAccountTimeoutDisposable.set((context.engine.privacy.updateGlobalMessageRemovalTimeout(timeout: timeout == 0 ? nil : timeout)
                                    |> then(applyTimeout)
                                    |> deliverOnMainQueue).start())
                            }
                        }
                        strongSelf.navigationController?.push(GlobalAutoremoveMessagesController(context: context, privacy: privacySettingsValue, updated: timeoutAction))
                    }
                }))
            }
            
        }, openProxySettings: { [weak self] in
            if let context = self?.context {

                let controller = SettingsNavigationHooks.shared.makeProxyListController(context, { servers in
                    var message: String = ""
                    for server in servers {
                        message += server.link + "\n\n"
                    }
                    message = message.trimmed

                    SettingsHooks.shared.shareLink(context, message)
                }, { controller in
                    pushControllerImpl(controller)
                })
                pushControllerImpl(controller)
            }
        }, togglePeerSuggestions: { enabled in
            _ = (context.engine.peers.updateRecentPeersEnabled(enabled: enabled) |> then(enabled ? (context.engine.peers.managedUpdatedRecentPeers() |> take(1)) : Signal<Void, NoError>.complete())).start()
        }, clearCloudDrafts: {
            verifyAlert_button(for: context.window, information: strings().privacyAndSecurityConfirmClearCloudDrafts, successHandler: { _ in
                _ = showModalProgress(signal: context.engine.messages.clearCloudDraftsInteractively(), for: context.window).start()
            })
        }, toggleSensitiveContent: { value in
            _ = updateRemoteContentSettingsConfiguration(postbox: context.account.postbox, network: context.account.network, sensitiveContentEnabled: value).start()
        }, toggleSecretChatWebPreview: { value in
            FastSettings.setSecretChatWebPreviewAvailable(for: context.account.id.int64, value: value)
        }, toggleAutoArchive: { value in
            _ = showModalProgress(signal: context.engine.privacy.updateAccountAutoArchiveChats(value: value), for: context.window).start()
        }, openGiftsPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .gifts, current: info.giftsAutoSave, callSettings: info.voiceCallsP2P, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, p2pUpdated, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: updated, noPaidMessages: value.noPaidMessages, savedMusic: value.savedMusic, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, openSavedMusicPrivacy: { [currentInfoDisposable] in
            let signal = loadedPrivacySettings
            currentInfoDisposable.set(signal.start(next: { [weak currentInfoDisposable] info in
                if let info = info {
                    pushControllerImpl(SelectivePrivacySettingsController(context, kind: .savedMusic, current: info.savedMusic, callSettings: info.voiceCallsP2P, phoneDiscoveryEnabled: nil, globalSettings: info.globalSettings, updated: { updated, p2pUpdated, _, globalSettings in
                        if let currentInfoDisposable = currentInfoDisposable {
                            let applySetting: Signal<Void, NoError> = privacySettingsPromise.get()
                                |> filter { $0 != nil }
                                |> take(1)
                                |> deliverOnMainQueue
                                |> mapToSignal { value -> Signal<Void, NoError> in
                                    if let value = value {
                                        privacySettingsPromise.set(.single(AccountPrivacySettings(presence: value.presence, groupInvitations: value.groupInvitations, voiceCalls: value.voiceCalls, voiceCallsP2P: p2pUpdated ?? value.voiceCallsP2P, profilePhoto: value.profilePhoto, forwards: value.forwards, phoneNumber: value.phoneNumber, phoneDiscoveryEnabled: value.phoneDiscoveryEnabled, voiceMessages: value.voiceMessages, bio: value.bio, birthday: value.birthday, giftsAutoSave: value.giftsAutoSave, noPaidMessages: value.noPaidMessages, savedMusic: updated, globalSettings: globalSettings ?? value.globalSettings, accountRemovalTimeout: value.accountRemovalTimeout, messageAutoremoveTimeout: value.messageAutoremoveTimeout)))
                                    }
                                    return .complete()
                            }
                            currentInfoDisposable.set(applySetting.start())
                        }
                    }))
                }
            }))
        }, setupLoginEmail: { [weak self] emailPattern in

            let setup:()->Void = { [weak self] in
                showModal(with: SettingsNavigationHooks.shared.makeSetupEmailController(context, emailPattern), for: context.window, morphSource: { [weak self] in
                    guard let self, let index = self.genericView.index(hash: PrivacyAndSecurityEntry.loginEmail(sectionId: 0, pattern: nil, viewType: .singleItem).stableId) else { return nil }
                    return (self.genericView.viewNecessary(at: index) as? GeneralContainableRowView)?.containerView
                })
            }
            
            if let emailPattern, !emailPattern.contains(" ") {
                verifyAlert(for: context.window, header: emailPattern, information: strings().privacySettingsLoginEmailAlertText, ok: strings().privacySettingsLoginEmailAlertChange, successHandler: { _ in
                    setup()
                })
            } else {
                setup()
            }
        })


        let previous:Atomic<[AppearanceWrapperEntry<PrivacyAndSecurityEntry>]> = Atomic(value: [])
        let initialSize = self.atomicSize

        let contentConfiguration: Signal<ContentSettingsConfiguration?, NoError> = .single(nil) |> then(contentSettingsConfiguration(network: context.account.network) |> map(Optional.init))

        // Prefixed with .single(nil) so the screen does not block on the twoStepAuthData network fetch; the
        // login-email row fills in when it returns. Every other input already emits an immediate initial.
        let loginEmail: Signal<String?, NoError> = .single(nil) |> then(context.engine.auth.twoStepAuthData()
        |> map(Optional.init)
        |> `catch` { _ -> Signal<TwoStepAuthData?, NoError> in
            return .single(nil)
        }
        |> map { data -> String? in
            return data?.loginEmailPattern
        })
        
        let passkeysDataValue = Promise<[TelegramPasskey]?>(nil)
        let hasPasskeysDataValue = passkeysDataValue.get()
        |> mapToSignal { data -> Signal<Bool?, NoError> in
            if let data = data {
                return .single(!data.isEmpty)
            } else {
                return .single(nil)
            }
        }

        let passkeys = Promise<Bool?>()
        passkeys.set(hasPasskeysDataValue)
        
        let updateHasPasskeys: () -> Void = {
            let signal = context.engine.auth.passkeysData()
            |> map { value -> [TelegramPasskey]? in
                return value
            }
            |> deliverOnMainQueue
            updatePasskeyDataDisposable.set(
                signal.start(next: { value in
                    passkeysDataValue.set(.single(value))
//                    if let value {
//                        updatedHasPasskeys?(!value.isEmpty)
//                    }
                })
            )
        }
        updateHasPasskeys()

           
        #if APP_STORE
        var displayPasskeys = false
        if let data = context.appConfiguration.data {
            if let _ = data["ios_display_passkeys"] {
                displayPasskeys = true
            } else if let isDev = data["dev"] as? Double, isDev == 1.0 {
                displayPasskeys = true
            }
        }
        #else
        let displayPasskeys = false
        #endif

        
        let signal = combineLatest(queue: .mainQueue(), statePromise.get(), contentConfiguration, appearanceSignal, settings, privacySettingsPromise.get(), context.webSessions.state, combineLatest(queue: .mainQueue(), context.engine.peers.recentPeers(), twoStepAccessConfiguration.get(), context.activeSessionsContext.state, context.sharedContext.accountManager.accessChallengeData()), context.blockedPeersContext.state, loginEmail, passkeysDataValue.get())
        |> map { state, contentConfiguration, appearance, proxy, privacySettings, webSessions, additional, blockedState, loginEmail, passkeysDataValue -> TableUpdateTransition in
            let entries = entries(state: state, contentConfiguration: contentConfiguration, privacySettings: privacySettings, webSessions: webSessions, blockedState: blockedState, proxy: proxy, recentPeers: additional.0, configuration: additional.1, activeSessions: additional.2, passcodeData: additional.3.data, context: context, loginEmail: loginEmail, passkeysDataValue: passkeysDataValue, displayPasskeys: displayPasskeys).map{AppearanceWrapperEntry(entry: $0, appearance: appearance)}
            return prepareTransition(left: previous.swap(entries), right: entries, initialSize: initialSize.modify {$0}, arguments: arguments)
        } |> afterDisposed {
            actionsDisposable.dispose()
        } |> deliverOnMainQueue
        
        disposable.set(signal.start(next: { [weak self] transition in
            self?.genericView.merge(with: transition)
            self?.readyOnce()
            if let focusOnItemTag = self?.focusOnItemTag {
                self?.genericView.scroll(to: .center(id: focusOnItemTag.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
                self?.focusOnItemTag = nil
            }
        }))
        
    }
    
    deinit {
        disposable.dispose()
    }
    
    private var focusOnItemTag: PrivacyAndSecurityEntryTag?
    private let disposable = MetaDisposable()
    public init(_ context: Context, initialSettings: AccountPrivacySettings?, focusOnItemTag: PrivacyAndSecurityEntryTag? = nil, twoStepVerificationConfiguration: TwoStepVeriticationAccessConfiguration?) {
        self.focusOnItemTag = focusOnItemTag
        self.twoStepAccessConfiguration.set(.single(twoStepVerificationConfiguration))
        super.init(context)
        
        let thenSignal:Signal<AccountPrivacySettings?, NoError> = context.engine.privacy.requestAccountPrivacySettings() |> map(Optional.init)
        
        self.privacySettingsPromise.set(.single(initialSettings) |> then(thenSignal))
    }
}

