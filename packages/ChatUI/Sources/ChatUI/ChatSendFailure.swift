import Foundation
import Postbox
import TelegramCore
import TelegramTheme
import TelegramUtils
import Localization

struct ChatSendFailure {
    let text: String
    let offersSpamBot: Bool
    let allowsRetry: Bool

    init(code: String, peer: Peer?) {
        let reason = sendMessageReasonForError(code)
        self.offersSpamBot = reason == .flood || reason == .publicBan
        switch reason {
        case .flood:
            self.text = strings().chatSendMessageErrorFlood
        case .publicBan:
            self.text = peer?.isChannel == true ? strings().chatSendFailureChannelRestricted : strings().chatSendMessageErrorGroupRestricted
        case .mediaRestricted:
            if code == "CHAT_SEND_PLAIN_FORBIDDEN" {
                self.text = strings().chatSendFailurePlainForbidden
            } else {
                self.text = strings().chatSendFailureMediaForbidden
            }
        case .slowmodeActive:
            if code.hasPrefix("SLOWMODE_WAIT_"), let seconds = Int(code.dropFirst("SLOWMODE_WAIT_".count)), seconds > 0 {
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.unitsStyle = .full
                let wait = formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)"
                self.text = strings().chatSendFailureSlowModeWait(wait)
            } else {
                self.text = strings().chatSendMessageSlowmodeError
            }
        case .tooMuchScheduled:
            self.text = strings().chatSendMessageErrorTooMuchScheduled
        case .voiceMessagesForbidden:
            self.text = strings().chatSendVoicePrivacyError(peer?.compactDisplayTitle ?? "")
        case .sendingTooFast:
            self.text = strings().chatSendMessageErrorTooFast
        case .nonPremiumMessagesForbidden:
            self.text = strings().chatSendMessageErrorNonPremiumForbidden(peer?.compactDisplayTitle ?? "")
        case nil:
            switch code {
            case "CHAT_RESTRICTED", "CHAT_WRITE_FORBIDDEN":
                self.text = peer?.isChannel == true ? strings().chatSendFailureChannelWriteForbidden : strings().chatSendFailureChatWriteForbidden
            case "CHANNEL_INVALID", "CHANNEL_PRIVATE":
                self.text = strings().chatSendFailureChatInaccessible
            case "CHAT_ADMIN_REQUIRED":
                self.text = strings().chatSendFailureAdminRequired
            case "CHAT_GUEST_SEND_FORBIDDEN":
                self.text = strings().chatSendFailureGuestSendForbidden
            case "CHAT_FORWARDS_RESTRICTED":
                self.text = strings().chatSendFailureForwardsRestricted
            case "TOPIC_CLOSED":
                self.text = strings().chatInputTopicClosed
            case "TOPIC_DELETED":
                self.text = strings().chatSendFailureTopicDeleted
            case "MESSAGE_TOO_LONG":
                self.text = strings().chatSendFailureMessageTooLong
            case "ENTITIES_TOO_LONG":
                self.text = strings().chatSendFailureEntitiesTooLong
            case "PREMIUM_ACCOUNT_REQUIRED":
                self.text = strings().chatSendFailurePremiumRequired
            case "USER_IS_BLOCKED":
                self.text = strings().chatSendFailureUserBlocked
            case "internal", "":
                self.text = strings().chatSendFailureGeneric
            default:
                if code.hasPrefix("FILE_REFERENCE_") || code.hasPrefix("FILEREF_INVALID") {
                    self.text = strings().chatSendFailureFileReferenceExpired
                } else {
                    self.text = strings().chatSendFailureServerError(code)
                }
            }
        }

        switch code {
        case "CHAT_RESTRICTED", "CHAT_WRITE_FORBIDDEN", "CHANNEL_INVALID", "CHANNEL_PRIVATE", "CHAT_ADMIN_REQUIRED",
             "CHAT_GUEST_SEND_FORBIDDEN", "CHAT_FORWARDS_RESTRICTED", "TOPIC_CLOSED", "TOPIC_DELETED",
             "MESSAGE_TOO_LONG", "ENTITIES_TOO_LONG", "USER_IS_BLOCKED", "PREMIUM_ACCOUNT_REQUIRED":
            self.allowsRetry = false
        default:
            self.allowsRetry = reason != .publicBan && reason != .mediaRestricted
        }
    }
}
