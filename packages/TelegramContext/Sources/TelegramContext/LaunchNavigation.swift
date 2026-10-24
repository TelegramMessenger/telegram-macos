import Foundation
import Postbox
import TelegramCore

public enum LaunchNavigation : Equatable {
    case chat(PeerId, necessary: Bool)
    case thread(MessageId, MessageId?, MessageHistoryThreadData?, necessary: Bool)
    case profile(EnginePeer, necessary: Bool)
    case settings
    case story(PeerId)
}
