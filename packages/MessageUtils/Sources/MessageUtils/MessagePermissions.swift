import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import ChatModeTypes
import InAppSettings
import TelegramTheme

public func canDeleteMessage(_ message:Message, account:Account, chatLocation: ChatLocation, mode: ChatMode, ranks: CachedChannelAdminRanks? = nil) -> Bool {

    if case .searchHashtag = mode.customChatContents?.kind {
        return false
    }

    if mode.customChatContents != nil {
        return true
    }
    if chatLocation.threadMsgId == message.id {
        return false
    }
    if message.adAttribute != nil {
        return false
    }
    if mode.isSavedMode {
        return false
    }


    if message.id.peerId.namespace == Namespaces.Peer.CloudChannel || chatLocation.peerId.namespace == Namespaces.Peer.CloudChannel {
        if let channel = (message.peers[message.id.peerId] ?? message.peers[chatLocation.peerId]) as? TelegramChannel {
            if case .broadcast = channel.info {
                if channel.flags.contains(.isCreator) {
                    return true
                }
                return channel.hasPermission(.deleteAllMessages)
            }
            if channel.flags.contains(.isCreator) {
                return true
            }
            if message.author?.id == channel.id {
                return false
            }
            if let authorId = message.author?.id, let rank = ranks?.ranks[authorId], case .owner = rank {
                return false
            }
            if channel.hasPermission(.deleteAllMessages) {
                return true
            }
            return !message.effectivelyIncoming(account.peerId)
        } else {
            return !message.effectivelyIncoming(account.peerId)
        }
    } else if (message.peers[message.id.peerId] ?? message.peers[chatLocation.peerId]) is TelegramGroup {
        return true
    } else if (message.peers[message.id.peerId] ?? message.peers[chatLocation.peerId]) is TelegramUser {
        return true
    } else if message.peers[message.id.peerId] is TelegramSecretChat {
        return true
    } else {
        return true
    }
}

public func canForwardMessage(_ sourceMessage: Message, chatInteraction: any MessagePermissionSource) -> Bool {
    let message = messageForForwarding(sourceMessage)

    if let attribute = message.attributes.first(where: { $0 is EphemeralMessageAttribute }) as? EphemeralMessageAttribute, attribute.isForwardingDisabled {
        return false
    }
        
    if message.peers[message.id.peerId] is TelegramSecretChat {
        return false
    }
    
    if let customChatContents = chatInteraction.permissionMode.customChatContents {
        if case .searchHashtag = customChatContents.kind {
        } else {
            return false
        }
    }
    
    if message.isExpiredStory {
        return false
    }
    
    
    if message.consumableContent != nil, let autoclear = message.autoclearTimeout, autoclear.timeout <= 60 || autoclear.timeout == viewOnceTimeout {
        return false
    }
    
    if message.flags.contains(.Failed) || message.flags.contains(.Unsent) {
        return false
    }
    if message.isScheduledMessage {
        return false
    }
    if message.adAttribute != nil {
        return false
    }
    if message.isCopyProtected(cachedData: chatInteraction.permissionCachedData) {
        return false
    }

    if message.extendedMedia is TelegramMediaAction {
        return false
    }
    
    if let peer = message.peers[message.id.peerId] as? TelegramGroup {
        if peer.flags.contains(.copyProtectionEnabled) {
            return false
        }
    }
    if let peer = message.peers[message.id.peerId] as? TelegramChannel {
        if peer.flags.contains(.copyProtectionEnabled) {
            return false
        }
    }
    
    if let peer = message.peers[message.id.peerId] as? TelegramUser {
        if peer.isUser, let timer = message.autoremoveAttribute {
            if timer.timeout <= 60 {
                return false;
            }
        }
    }
    
    return true
}

public struct ChatAvailableMessageActionOptions: OptionSet {
    public var rawValue: Int32
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = 0
    }
    
    public static let deleteLocally = ChatAvailableMessageActionOptions(rawValue: 1 << 0)
    public static let deleteGlobally = ChatAvailableMessageActionOptions(rawValue: 1 << 1)
    public static let unsendPersonal = ChatAvailableMessageActionOptions(rawValue: 1 << 7)
}

public func canDeleteForEveryoneMessage(_ message:Message, context: any AccountContextProtocol) -> Bool {
    if message.peers[message.id.peerId] is TelegramChannel || message.peers[message.id.peerId] is TelegramSecretChat {
        return false
    } else if let user = message.peers[message.id.peerId] as? TelegramUser, user.isBot {
        return false
    } else if message.peers[message.id.peerId] is TelegramUser || message.peers[message.id.peerId] is TelegramGroup {
        if message.id.peerId == TelegramUtilsHooks.shared.repliesPeerId() {
            return false
        }
        if context.limitConfiguration.canRemoveIncomingMessagesInPrivateChats && message.peers[message.id.peerId] is TelegramUser {
            
            if message.anyMedia is TelegramMediaDice, message.peers[message.id.peerId] is TelegramUser {
                if Int(message.timestamp) + 24 * 60 * 60 > context.timestamp {
                    return false
                }
            }
            
            return true
        }
        if let peer = message.peers[message.id.peerId] as? TelegramGroup {
            switch peer.role {
            case .creator, .admin:
                return true
            default:
                if Int(context.limitConfiguration.maxMessageEditingInterval) + Int(message.timestamp) > Int(Date().timeIntervalSince1970) {
                    if context.account.peerId == message.effectiveAuthor?.id {
                        return !(message.extendedMedia is TelegramMediaAction)
                    }
                }
                return false
            }
            
        } else if Int(context.limitConfiguration.maxMessageEditingInterval) + Int(message.timestamp) > Int(Date().timeIntervalSince1970) {
            if context.account.peerId == message.author?.id {
                return !(message.extendedMedia is TelegramMediaAction)
            }
        }
    }
    return false
}

public func mustDeleteForEveryoneMessage(_ message:Message) -> Bool {
    if message.peers[message.id.peerId] is TelegramChannel || message.peers[message.id.peerId] is TelegramSecretChat {
        return true
    }
    return false
}

public func canReplyMessage(_ message: Message, peerId: PeerId, chatLocation: ChatLocation, mode: ChatMode, threadData: MessageHistoryThreadData? = nil) -> Bool {
    if let peer = coreMessageMainPeer(message) {
        if message.isScheduledMessage {
            return false
        }
        if mode.customChatContents != nil, message.id.namespace == Namespaces.Message.Local {
            return false
        }
        if peerId == message.id.peerId, !message.flags.contains(.Unsent) && !message.flags.contains(.Failed) && (message.id.namespace != Namespaces.Message.Local || message.id.peerId.namespace == Namespaces.Peer.SecretChat) {
            
            switch mode {
            case .history, .customChatContents:
                if let channel = peer as? TelegramChannel, channel.hasPermission(.sendSomething) {
                    return true
                } else {
                    return true//peer.canSendMessage(false, threadData: threadData)
                }
            case .scheduled:
                return false
            case let .thread(mode):
                if case let .thread(data) = chatLocation {
                    switch mode {
                    case .comments, .replies, .topic:
                        if message.id.id == data.threadId {
                            return false
                        }
                        if let channel = peer as? TelegramChannel, channel.hasPermission(.sendSomething) {
                            return true
                        } else {
                            return MessagePermissionHooks.shared.canSendMessage(peer, false, threadData)
                        }
                    case .savedMessages:
                        return false
                    case .saved:
                        return false
                    }
                }
            case .pinned:
                return false
            case .customLink:
                return false
            case .preview:
                return false
            }
        }
    }
    return false
}

public func canEditMessage(_ message:Message, chatInteraction: any MessagePermissionSource, context: any AccountContextProtocol, ignorePoll: Bool = false) -> Bool {
    
    
    if case .searchHashtag = chatInteraction.permissionMode.customChatContents?.kind {
        return false
    }
    
    if case .welcomeMessages = chatInteraction.permissionMode.customChatContents?.kind {
        return message.id.namespace == Namespaces.Message.WelcomeMessageCloud
            && !message.flags.contains(.Unsent)
            && !message.flags.contains(.Failed)
    }

    if chatInteraction.permissionMode.customChatContents != nil {
        return true
    }
    
    if message.forwardInfo != nil {
        return false
    }
    
    if message.flags.contains(.Unsent) || message.flags.contains(.Failed) || message.id.namespace == Namespaces.Message.Local {
        return false
    }
    
    if message.media.first is TelegramMediaStory {
        return false
    }
    
    if message.peers[message.id.peerId] is TelegramSecretChat {
        return false
    }
    
    if let media = message.anyMedia {
        if let file = media as? TelegramMediaFile {
            if file.isStaticSticker || (file.isAnimatedSticker && !file.isEmojiAnimatedSticker) {
                return false
            }
            if file.isInstantVideo {
                return false
            }
//            if file.isVoice {
//                return false
//            }
        }
        if media is TelegramMediaContact {
            return false
        }
        if media is TelegramMediaAction {
            return false
        }
        if media is TelegramMediaMap {
            return false
        }
        if media is TelegramMediaPoll, !ignorePoll {
            return false
        }
        if media is TelegramMediaDice {
            return false
        }
    }
    
    for attr in message.attributes {
        if attr is InlineBotMessageAttribute {
            return false
        } else if let attr = attr as? AutoremoveTimeoutMessageAttribute, attr.timeout <= 60 {
            return false
        }
    }
//    if !chatInteraction.hasSetDestructiveTimer {
//        return false
//    }
    
    var timeInCondition = Int(message.timestamp) + Int(context.limitConfiguration.maxMessageEditingInterval) > context.account.network.getApproximateRemoteTimestamp()
    
    if message.media.first is TelegramMediaTodo {
        timeInCondition = true
    }
    if let attr = message.suggestPostAttribute, attr.state == nil {
        timeInCondition = true
    }
    
    if let peer = coreMessageMainPeer(message) as? TelegramChannel {
        if case .broadcast = peer.info {
            if message.isScheduledMessage {
                return peer.hasPermission(.sendText) || peer.hasPermission(.editAllMessages)
            }
            if peer.hasPermission(.pinMessages) {
                timeInCondition = true
            }
            if peer.hasPermission(.editAllMessages) {
                return timeInCondition
            } else if peer.hasPermission(.sendText) {
                return timeInCondition && message.author?.id == chatInteraction.permissionContext.peerId
            }
            return false
        } else if case .group = peer.info {
            if !message.flags.contains(.Incoming) {
                if peer.hasPermission(.pinMessages) {
                    return true
                }
                return timeInCondition
            }
        }
    }
    
    if message.id.peerId == context.account.peerId {
        return true
    }
    
    
    
    if message.effectivelyIncoming(context.peerId) {
        return false
    }
    
    
    if !timeInCondition {
        return false
    }
    
    
    
    return !message.flags.contains(.Unsent) && !message.flags.contains(.Failed)
}

public func canFactCheck(_ message: Message) -> Bool {
    
    if let media = message.anyMedia {
        if let file = media as? TelegramMediaFile {
            if file.isStaticSticker || file.isAnimatedSticker || file.isEmojiAnimatedSticker {
                return false
            }
            if file.isInstantVideo {
                return false
            }
        }
        if media is TelegramMediaContact {
            return false
        }
        if media is TelegramMediaAction {
            return false
        }
        if media is TelegramMediaMap {
            return false
        }
        if media is TelegramMediaPoll {
            return false
        }
        if media is TelegramMediaDice {
            return false
        }
    }
    
    
    return true
}

public func canPinMessage(_ message:Message, for peer:Peer, account:Account) -> Bool {
    return false
}

public func canReportMessage(_ message: Message, _ context: any AccountContextProtocol) -> Bool {
    if message.isScheduledMessage || message.flags.contains(.Failed) || message.flags.contains(.Sending) {
        return false
    }
    if message.id.namespace == Namespaces.Message.Local {
        return false
    }
//    if let peer = message.peers[message.id.peerId], peer.isUser {
//        if context.timestamp - message.timestamp < 12 * 60 * 60 {
//            return true
//        }
//    }
    if let peer = coreMessageMainPeer(message), message.author?.id != context.peerId {
        if message.flags.contains(.Incoming) {
            return peer.isChannel || peer.isGroup || peer.isSupergroup || (message.chatPeer(context.peerId)?.isBot == true)
        }
    }
    return false
}

public func mustManageDeleteMessages(_ messages:[Message], for peer:Peer, account: Account) -> Bool {
    
    if let peer = peer as? TelegramChannel, peer.isSupergroup, peer.hasPermission(.deleteAllMessages) {
        for message in messages {
            let peerId:PeerId? = message.effectiveAuthor?.id
            if account.peerId != peerId {
                if !message.flags.contains(.Incoming) {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }
    
    return false
}
