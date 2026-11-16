import Cocoa
import TelegramCore
import TGUIKit
import Postbox

extension PixelDimensions {
    public var size: CGSize {
        return CGSize(width: CGFloat(self.width), height: CGFloat(self.height))
    }
    public init(_ size: CGSize) {
        self.init(width: Int32(abs(size.width)), height: Int32(abs(size.height)))
    }
    public init(_ width: Int32, _ height: Int32) {
        self.init(width: width, height: height)
    }
}
extension CGSize {
    public var pixel: PixelDimensions {
        return PixelDimensions(self)
    }
}

public enum AppLogEvents : String {
    case imageEditor = "image_editor_used"
}


extension Peer {
    /// Effective `displayForumAsTabs` for UI decisions: forces `true` when
    /// the chat-list column is in `.minimisize`, because the narrow layout
    /// can't render the forum subview hierarchy and tabs are the only way
    /// to navigate threads.
    public func displayForumAsTabs(splitState: SplitViewState) -> Bool {
        if splitState == .minimisize {
            return true
        }
        return self.displayForumAsTabs
    }

    public var isUser:Bool {
        return self is TelegramUser
    }
    public var isSecretChat:Bool {
        return self is TelegramSecretChat
    }
    public var isGroup:Bool {
        return self is TelegramGroup
    }
    public var canManageDestructTimer: Bool {
        if self is TelegramSecretChat {
            return true
        }
        if self.isUser && !self.isBot {
            return true
        }
        if self.isMonoForum {
            return false
        }
        
        if let peer = self as? TelegramChannel {
            if let adminRights = peer.adminRights, adminRights.rights.contains(.canDeleteMessages) {
                return true
            } else if peer.groupAccess.isCreator {
                return true
            }
            return false
        }
        if (self as? TelegramGroup) != nil {
            return true
        }
        return false
    }
    
    public var storyArchived: Bool {
        if let user = self as? TelegramUser {
            return user.storiesHidden ?? false
        }
        if let user = self as? TelegramChannel {
            return user.storiesHidden ?? false
        }
        return false
    }

    public var canClearHistory: Bool {
        if self.isGroup || self.isUser || (self.isSupergroup && self.addressName == nil) {
            if let peer = self as? TelegramChannel, peer.flags.contains(.hasGeo) {} else {
                return true
            }
        }
        if self is TelegramSecretChat {
            return true
        }
        return false
    }
    
    public var restrictionInfo: PeerAccessRestrictionInfo? {
        if let peer = self as? TelegramChannel {
            return peer.restrictionInfo
        } else if let peer = self as? TelegramUser {
            return peer.restrictionInfo
        } else {
            return nil
        }
    }
    
    public func isRestrictedChannel(_ contentSettings: ContentSettings) -> Bool {
        if let restrictionInfo = self.restrictionInfo {
            for rule in restrictionInfo.rules {
                #if APP_STORE || STABLE || BETA
                if rule.appliesTo(platform: "ios", contentSettings: contentSettings), rule.reason != "sensitive", !contentSettings.ignoreContentRestrictionReasons.contains(rule.reason) {
                    return true
                }
                #endif
            }
        }
        return false
    }
    
    
    public func restrictionText(_ contentSettings: ContentSettings?) -> String? {
        if let restrictionInfo = self.restrictionInfo, self.isRestrictedChannel(contentSettings ?? .default) {
            for rule in restrictionInfo.rules {
                if rule.appliesTo(platform: "ios", contentSettings: contentSettings ?? .default), rule.reason != "sensitive" {
                    if let contentSettings {
                        if !contentSettings.ignoreContentRestrictionReasons.contains(rule.reason) {
                            return rule.text
                        }
                    } else {
                        return rule.text
                    }
                }
            }
        }
        return nil
    }
    
    public var botInfo: BotUserInfo? {
        if let peer = self as? TelegramUser {
            return peer.botInfo
        }
        return nil
    }
    
    public var isSupergroup:Bool {
        if let peer = self as? TelegramChannel {
            switch peer.info {
            case .group:
                return true
            default:
                return false
            }
        }
        return false
    }
    public var isBot:Bool {
        if let user = self as? TelegramUser {
            return user.botInfo != nil
        }
        return false
    }

    public var canCall:Bool {
        return isUser && !isBot && ((self as! TelegramUser).phone != "42777") && ((self as! TelegramUser).phone != "42470") && ((self as! TelegramUser).phone != "4240004")
    }
    public var isChannel:Bool {
        if let peer = self as? TelegramChannel {
            switch peer.info {
            case .broadcast:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    public var isAdmin: Bool {
        if let peer = self as? TelegramChannel {
            return peer.adminRights != nil || peer.flags.contains(.isCreator)
        }
        return false
    }
    
    public var isOwner: Bool {
        if let peer = self as? TelegramChannel {
            return peer.flags.contains(.isCreator)
        }
        return false
    }
    
    public var isGigagroup:Bool {
        if let peer = self as? TelegramChannel {
            return peer.flags.contains(.isGigagroup)
        }
        return false
    }
}

