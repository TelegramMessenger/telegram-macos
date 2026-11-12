import TelegramCore
import Localization

func channelAdminRightsErrorText(_ error: UpdateChannelAdminRightsError, isGroup: Bool) -> String {
    switch error {
    case .notMemberCannotInvite:
        return strings().channelAdminsPromoteUnmemberAdminError
    case .userBlocked:
        return isGroup ? strings().groupErrorAddBlocked : strings().channelErrorAddBlocked
    case .adminsTooMuch, .generic:
        return strings().channelAdminsAddAdminError
    case let .addMemberError(error):
        switch error {
        case .notMutualContact:
            return isGroup ? strings().groupInfoAddUserLeftError : strings().channelInfoAddUserLeftError
        case .limitExceeded:
            return strings().channelErrorAddTooMuch
        case .botDoesntSupportGroups:
            return strings().channelBotDoesntSupportGroups
        case .tooMuchBots:
            return strings().channelTooMuchBots
        case .tooMuchJoined:
            return strings().inviteChannelsTooMuch
        case .restricted:
            return isGroup ? strings().groupErrorAddBlocked : strings().channelErrorAddBlocked
        case .kicked:
            return strings().channelAddAdminKickedError
        case .bot, .generic:
            return strings().channelAdminsAddAdminError
        }
    }
}
