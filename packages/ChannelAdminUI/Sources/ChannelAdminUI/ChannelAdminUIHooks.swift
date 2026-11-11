import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import AudioPlayerCore
import SwiftSignalKit

public struct ChannelAdminUIHooks {
    public let messageWithUpdatedTimestamp: (Message, Int32) -> Message
    public let getAudioPlayer: (any AccountContextProtocol) -> APController?
    public let makeInlineAudioPlayerContextObject: (APController, any AccountContextProtocol, TableView?, TableView?) -> Any
    public let showInlineAudioPlayer: (APController, any AccountContextProtocol, TableView?, TableView?) -> Void
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let participantModerationMenuItems: (any AccountContextProtocol, TelegramChannel, Peer, ChannelParticipant?) -> [ContextMenuItem]

    public init(messageWithUpdatedTimestamp: @escaping (Message, Int32) -> Message,
                getAudioPlayer: @escaping (any AccountContextProtocol) -> APController?,
                makeInlineAudioPlayerContextObject: @escaping (APController, any AccountContextProtocol, TableView?, TableView?) -> Any,
                showInlineAudioPlayer: @escaping (APController, any AccountContextProtocol, TableView?, TableView?) -> Void,
                pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                participantModerationMenuItems: @escaping (any AccountContextProtocol, TelegramChannel, Peer, ChannelParticipant?) -> [ContextMenuItem]) {
        self.messageWithUpdatedTimestamp = messageWithUpdatedTimestamp
        self.getAudioPlayer = getAudioPlayer
        self.makeInlineAudioPlayerContextObject = makeInlineAudioPlayerContextObject
        self.showInlineAudioPlayer = showInlineAudioPlayer
        self.pushPeerInfo = pushPeerInfo
        self.participantModerationMenuItems = participantModerationMenuItems
    }

    private static var _shared: ChannelAdminUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChannelAdminUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChannelAdminUIHooks.install must be called before channel admin screens are used")
        return .placeholder
    }

    public static func install(_ hooks: ChannelAdminUIHooks) {
        assert(Thread.isMainThread, "ChannelAdminUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChannelAdminUIHooks(messageWithUpdatedTimestamp: { message, _ in
        message
    }, getAudioPlayer: { _ in
        nil
    }, makeInlineAudioPlayerContextObject: { controller, _, _, _ in
        controller
    }, showInlineAudioPlayer: { _, _, _, _ in
    }, pushPeerInfo: { _, _, _ in
    }, participantModerationMenuItems: { _, _, _, _ in
        []
    })
}
