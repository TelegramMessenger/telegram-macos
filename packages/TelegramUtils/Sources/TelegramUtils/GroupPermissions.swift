import Foundation
import Postbox
import TelegramCore
import TGUIKit
import Localization

public let internal_allPossibleGroupPermissionList: [(TelegramChatBannedRightsFlags, TelegramChannelPermission)] = [
    (.banSendText, .banMembers),
    (.banSendMedia, .banMembers),
    (.banSendPhotos, .banMembers),
    (.banSendVideos, .banMembers),
    (.banSendGifs, .banMembers),
    (.banSendMusic, .banMembers),
    (.banSendFiles, .banMembers),
    (.banSendVoice, .banMembers),
    (.banSendInstantVideos, .banMembers),
    (.banEmbedLinks, .banMembers),
    (.banSendPolls, .banMembers),
    (.banSendReactions, .banMembers),
    (.banAddMembers, .banMembers),
    (.banPinMessages, .pinMessages),
    (.banEditRank, .banMembers),
    (.banManageTopics, .manageTopics),
    (.banChangeInfo, .changeInfo)
]

public func allGroupPermissionList(peer: Peer) -> [(TelegramChatBannedRightsFlags, TelegramChannelPermission)] {
    if let channel = peer as? TelegramChannel, channel.flags.contains(.isForum) {
        return [
            (.banSendText, .banMembers),
            (.banSendMedia, .banMembers),
            (.banAddMembers, .banMembers),
            (.banPinMessages, .pinMessages),
            (.banEditRank, .banMembers),
            (.banManageTopics, .manageTopics),
            (.banChangeInfo, .changeInfo)
        ]
    } else {
        return [
            (.banSendText, .banMembers),
            (.banSendMedia, .banMembers),
            (.banAddMembers, .banMembers),
            (.banPinMessages, .pinMessages),
            (.banEditRank, .banMembers),
            (.banChangeInfo, .changeInfo)
        ]
    }
}

public func banSendMediaSubList() -> [(TelegramChatBannedRightsFlags, TelegramChannelPermission)] {
    return [
        (.banSendPhotos, .banMembers),
        (.banSendVideos, .banMembers),
        (.banSendGifs, .banMembers),
        (.banSendMusic, .banMembers),
        (.banSendFiles, .banMembers),
        (.banSendVoice, .banMembers),
        (.banSendInstantVideos, .banMembers),
        (.banEmbedLinks, .banMembers),
        (.banSendPolls, .banMembers),
        (.banSendReactions, .banMembers),
    ]
}

public let publicGroupRestrictedPermissions: TelegramChatBannedRightsFlags = [
    .banPinMessages,
    .banChangeInfo
]

public func canBypassChatRestrictions(_ cachedData: CachedPeerData?) -> Bool {
    guard let cachedData = cachedData as? CachedChannelData,
          let required = cachedData.boostsToUnrestrict, required > 0,
          let applied = cachedData.appliedBoosts else {
        return false
    }
    return applied >= required
}

public func checkMediaPermission(_ media: Media, for peer: Peer?, cachedData: CachedPeerData? = nil) -> String? {
    guard let peer = peer else {
        return nil
    }
    switch media {
    case _ as TelegramMediaPoll:
        return permissionText(from: peer, for: .banSendPolls, cachedData: cachedData)
    case _ as TelegramMediaImage:
        return permissionText(from: peer, for: .banSendPhotos, cachedData: cachedData)
    case let file as TelegramMediaFile:
        if file.isAnimated && file.isVideo {
            return permissionText(from: peer, for: .banSendGifs, cachedData: cachedData)
        } else if file.isStaticSticker {
            return permissionText(from: peer, for: .banSendStickers, cachedData: cachedData)
        } else if file.isMusic {
            return permissionText(from: peer, for: .banSendMusic, cachedData: cachedData)
        } else if file.isVoice {
            return permissionText(from: peer, for: .banSendVoice, cachedData: cachedData)
        } else if file.isInstantVideo {
            return permissionText(from: peer, for: .banSendInstantVideos, cachedData: cachedData)
        } else if file.isVideo {
            return permissionText(from: peer, for: .banSendVideos, cachedData: cachedData)
        } else {
            return permissionText(from: peer, for: .banSendFiles, cachedData: cachedData)
        }
    case _ as TelegramMediaGame:
        return permissionText(from: peer, for: .banSendGames, cachedData: cachedData)
    default:
        return nil
    }
}

public func permissionText(from peer: Peer?, for flags: TelegramChatBannedRightsFlags, cachedData: CachedPeerData? = nil) -> String? {
    guard let peer = peer else {
        return nil
    }
    var bannedPermission: (Int32, Bool)?
    
    let ignoreDefault = canBypassChatRestrictions(cachedData)
    
    let get:(TelegramChatBannedRightsFlags) -> (Int32, Bool)? = { flags in
        if let channel = peer as? TelegramChannel {
            return channel.hasBannedPermission(flags, ignoreDefault: ignoreDefault)
        } else if let group = peer as? TelegramGroup {
            if group.hasBannedPermission(flags) {
                return (Int32.max, false)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    bannedPermission = get(flags)
    if bannedPermission == nil, banSendMediaSubList().contains(where: { $0.0 == flags }) {
        bannedPermission = get(.banSendMedia)
    }
    
    if let (untilDate, personal) = bannedPermission {
        
        switch flags {
        case .banSendText:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendMessagesUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendMessagesForever
            } else {
                return strings().channelPersmissionDeniedSendMessagesDefaultRestrictedText
            }
        case .banSendStickers:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendStickersUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendStickersForever
            } else {
                return strings().channelPersmissionDeniedSendStickersDefaultRestrictedText
            }
        case .banSendGifs:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendGifsUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendGifsForever
            } else {
                return strings().channelPersmissionDeniedSendGifsDefaultRestrictedText
            }
        case .banSendMedia:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendMediaUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendMediaForever
            } else {
                return strings().channelPersmissionDeniedSendMediaDefaultRestrictedText
            }
        case .banSendPolls:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendPollUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendPollForever
            } else {
                return strings().channelPersmissionDeniedSendPollDefaultRestrictedText
            }
        case .banSendInline:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendInlineUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendInlineForever
            } else {
                return strings().channelPersmissionDeniedSendInlineDefaultRestrictedText
            }
        case .banSendVoice:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendVoiceUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendVoiceForever
            } else {
                return strings().channelPersmissionDeniedSendVoiceDefaultRestrictedText
            }
        case .banSendInstantVideos:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendInstantVideoUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendInstantVideoForever
            } else {
                return strings().channelPersmissionDeniedSendInstantVideoDefaultRestrictedText
            }
        case .banSendVideos:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendVideoUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendVideoForever
            } else {
                return strings().channelPersmissionDeniedSendVideoDefaultRestrictedText
            }
        case .banSendPhotos:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendPhotoUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendPhotoForever
            } else {
                return strings().channelPersmissionDeniedSendPhotoDefaultRestrictedText
            }
        case .banSendFiles:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendFileUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendFileForever
            } else {
                return strings().channelPersmissionDeniedSendFileDefaultRestrictedText
            }
        case .banSendMusic:
            if personal && untilDate != 0 && untilDate != Int32.max {
                return strings().channelPersmissionDeniedSendMusicUntil(stringForFullDate(timestamp: untilDate))
            } else if personal {
                return strings().channelPersmissionDeniedSendMusicForever
            } else {
                return strings().channelPersmissionDeniedSendMusicDefaultRestrictedText
            }
        default:
            return nil
        }
        
        
    }
    
    return nil
}

public extension Peer {
    func canSendMessage(_ isThreadMode: Bool = false, media: Media? = nil, threadData: MessageHistoryThreadData? = nil, cachedData: CachedPeerData? = nil) -> Bool {
        if self.id == repliesPeerId {
            return false
        }
        let ignoreDefault = canBypassChatRestrictions(cachedData)
        if let channel = self as? TelegramChannel {
            if case .broadcast(_) = channel.info {
                if let media = media, channel.hasPermission(.sendSomething) {
                    return checkMediaPermission(media, for: channel, cachedData: cachedData) == nil
                } else {
                    return channel.hasPermission(.sendText)
                }
            } else if case .group = channel.info {
                
                if let data = threadData {
                    if data.isClosed, channel.adminRights == nil && !channel.flags.contains(.isCreator) && !data.isOwnedByMe {
                        return false
                    }
                }
                
                switch channel.participationStatus {
                case .member:
                    if let media = media {
                        return channel.hasPermission(.sendSomething, ignoreDefault: ignoreDefault) && checkMediaPermission(media, for: channel, cachedData: cachedData) == nil
                    }
                    return channel.hasPermission(.sendText, ignoreDefault: ignoreDefault)
                case .left:
                    if isThreadMode {
                        if let media = media {
                            return channel.hasPermission(.sendSomething, ignoreDefault: ignoreDefault) && checkMediaPermission(media, for: channel, cachedData: cachedData) == nil
                        }
                        return channel.hasPermission(.sendText, ignoreDefault: ignoreDefault)
                    }
                    return false
                case .kicked:
                    return false
                }
            }
        } else if let group = self as? TelegramGroup {
            if let media = media {
                return group.membership == .Member && group.hasPermission(.sendSomething) && checkMediaPermission(media, for: group) == nil
            }
            return group.membership == .Member && !group.hasBannedPermission(.banSendText)
        } else if let secret = self as? TelegramSecretChat {
            switch secret.embeddedState {
            case .terminated:
                return false
            case .handshake:
                return false
            default:
                return true
            }
        }
        
        return true
    }
}
