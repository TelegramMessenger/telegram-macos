import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import Localization
import SwiftSignalKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif
import ColorPalette

public struct PeerStatusStringTheme {
    public let titleFont:NSFont
    public let titleColor:NSColor
    public let statusFont:NSFont
    public let statusColor:NSColor
    public let highlightColor:NSColor
    public let highlightIfActivity:Bool
    public init(titleFont:NSFont = .normal(.title), titleColor:NSColor = theme.colors.text, statusFont:NSFont = .normal(.short), statusColor:NSColor = theme.colors.grayText, highlightColor:NSColor = theme.colors.accent, highlightIfActivity:Bool = true) {
        self.titleFont = titleFont
        self.titleColor = titleColor
        self.statusFont = statusFont
        self.statusColor = statusColor
        self.highlightColor = highlightColor
        self.highlightIfActivity = highlightIfActivity
    }

    public init(_ colors: ColorPalette, titleFont:NSFont = .normal(.title), statusFont:NSFont = .normal(.short), highlightIfActivity:Bool = true) {
        self.titleFont = .normal(.title)
        self.titleColor = colors.text
        self.statusFont = statusFont
        self.statusColor = colors.grayText
        self.highlightColor = colors.accent
        self.highlightIfActivity = highlightIfActivity
    }
}

public struct PeerStatusStringResult : Equatable {
    public let title:NSAttributedString
    public let status:NSAttributedString
    public let presence:TelegramUserPresence?
    public init(_ title:NSAttributedString, _ status:NSAttributedString, presence:TelegramUserPresence? = nil) {
        self.title = title
        self.status = status
        self.presence = presence
    }

    public func withUpdatedTitle(_ string: String) -> PeerStatusStringResult {
        let title = self.title.mutableCopy() as! NSMutableAttributedString
        title.replaceCharacters(in: title.range, with: string)
        return PeerStatusStringResult(title, self.status, presence: self.presence)
    }

    public func withUpdatedStatus(_ string: String) -> PeerStatusStringResult {
        let status = self.status.mutableCopy() as! NSMutableAttributedString
        status.replaceCharacters(in: status.range, with: string)
        return PeerStatusStringResult(self.title, status, presence: self.presence)
    }
}

public func ==(lhs: PeerStatusStringResult, rhs: PeerStatusStringResult) -> Bool {
    if !lhs.title.isEqual(to: rhs.title) {
        return false
    }
    if !lhs.status.isEqual(to: rhs.status) {
        return false
    }
    if let lhsPresence = lhs.presence, let rhsPresence = rhs.presence, !lhsPresence.isEqual(to: rhsPresence) {
        return false
    } else if (lhs.presence != nil) != (rhs.presence != nil)  {
        return false
    }
    return true
}

public func stringStatus(for peerView:PeerView, context: any AccountContextProtocol, theme:PeerStatusStringTheme = PeerStatusStringTheme(), onlineMemberCount: Int32? = nil, memberCount preciseMemberCount: Int32? = nil, expanded: Bool = false, ignoreActivity: Bool = false) -> PeerStatusStringResult {


    let mainPeer = peerViewMainPeer(peerView)
    let monoforumPeer = peerViewMonoforumMainPeer(peerView)

    var effectivePeer: Peer? = mainPeer

    if let mainPeer = mainPeer as? TelegramChannel, mainPeer.isMonoForum {
        effectivePeer = monoforumPeer

    }

    if let peer = effectivePeer {
        let title:NSAttributedString = .initialize(string: TelegramUtilsHooks.shared.peerTitle(peer), color: theme.titleColor, font: theme.titleFont)
        if let user = peer as? TelegramUser {
            if user.phone == "42777" || user.phone == "42470" || user.phone == "4240004" {
                return PeerStatusStringResult(title, .initialize(string: strings().peerServiceNotifications,  color: theme.statusColor, font: theme.statusFont))
            }
            if user.id == TelegramUtilsHooks.shared.repliesPeerId() {
                return PeerStatusStringResult(title, .initialize(string: strings().peerRepliesNotifications,  color: theme.statusColor, font: theme.statusFont))
            } else if user.flags.contains(.isSupport) {
                return PeerStatusStringResult(title, .initialize(string: strings().presenceSupport,  color: theme.statusColor, font: theme.statusFont))
            } else if let _ = user.botInfo {
                let string: String
                if let subscriberCount = user.subscriberCount {
                    string = strings().peerStatusUsersOther(Int(subscriberCount)).replacingOccurrences(of: "\(subscriberCount)", with: subscriberCount.formattedWithSeparator)
                } else {
                    string = strings().presenceBot
                }
                return PeerStatusStringResult(title, .initialize(string: string,  color: theme.statusColor, font: theme.statusFont))
            } else if let presence = peerView.peerPresences[peer.id] as? TelegramUserPresence, !ignoreActivity {
                let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                let (string, activity, _) = userPresenceText(presence, timeDifference: context.timeDifference, relativeTo: Int32(timestamp), expanded: expanded)

                return PeerStatusStringResult(title, .initialize(string: string, color: activity && theme.highlightIfActivity ? theme.highlightColor : theme.statusColor, font: theme.statusFont), presence: presence)

            } else {
                return PeerStatusStringResult(title, .initialize(string: strings().peerStatusRecently, color: theme.statusColor, font: theme.statusFont))
            }
        } else if let group = peer as? TelegramGroup {
            var onlineCount = 0
            if let cachedGroupData = peerView.cachedData as? CachedGroupData, let participants = cachedGroupData.participants {
                let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                for participant in participants.participants {
                    if let presence = peerView.peerPresences[participant.peerId] as? TelegramUserPresence {
                        let relativeStatus = relativeUserPresenceStatus(presence, timeDifference: context.timeDifference, relativeTo: Int32(timestamp))
                        switch relativeStatus {
                        case .online:
                            onlineCount += 1
                        default:
                            break
                        }
                    }
                }
            }
            if onlineCount > 1 {
                let string = NSMutableAttributedString()

                let _ = string.append(string: "\(strings().peerStatusMemberOther(group.participantCount).replacingOccurrences(of: "\(group.participantCount)", with: group.participantCount.formattedWithSeparator)), ", color: theme.statusColor, font: theme.statusFont)
                let _ = string.append(string: strings().peerStatusMemberOnlineOther(onlineCount), color: theme.statusColor, font: theme.statusFont)
                return PeerStatusStringResult(title, string)
            } else {
                let string = NSAttributedString.initialize(string: strings().peerStatusMemberOther(group.participantCount).replacingOccurrences(of: "\(group.participantCount)", with: group.participantCount.formattedWithSeparator), color: theme.statusColor, font: theme.statusFont)
                return PeerStatusStringResult(title, string)
            }
        } else if let channel = peer as? TelegramChannel {

            let onlineCount: Int = Int(onlineMemberCount ?? 0)
            if let cachedChannelData = peerView.cachedData as? CachedChannelData, let memberCount = preciseMemberCount ?? cachedChannelData.participantsSummary.memberCount {


                let membersLocalized: String
                if channel.isChannel {
                    membersLocalized = strings().peerStatusSubscribersOther(Int(memberCount))
                } else {
                    if memberCount > 0 {
                        membersLocalized = strings().peerStatusMemberOther(Int(memberCount))
                    } else {
                        membersLocalized = strings().peerStatusGroup
                    }
                }

                let countString = membersLocalized.replacingOccurrences(of: "\(memberCount)", with: memberCount.formattedWithSeparator)
                if onlineCount > 1, case .group = channel.info {
                    let string = NSMutableAttributedString()
                    let _ = string.append(string: "\(countString), ", color: theme.statusColor, font: theme.statusFont)
                    let _ = string.append(string: strings().peerStatusMemberOnlineOther(onlineCount), color: theme.statusColor, font: theme.statusFont)
                    return PeerStatusStringResult(title, string)
                } else {

                    let string = NSAttributedString.initialize(string: countString, color: theme.statusColor, font: theme.statusFont)
                    return PeerStatusStringResult(title, string)
                }

            } else {
                switch channel.info {
                case .group:
                    let string = NSAttributedString.initialize(string: strings().peerStatusGroup, color: theme.statusColor, font: theme.statusFont)
                    return PeerStatusStringResult(title, string)

                case .broadcast:
                    let string = NSAttributedString.initialize(string: strings().peerStatusChannel, color: theme.statusColor, font: theme.statusFont)
                    return PeerStatusStringResult(title, string)
                }
            }
        }

    }
    return PeerStatusStringResult(NSAttributedString(), NSAttributedString())
}

public func peerViewMonoforumMainPeer(_ view: PeerView) -> Peer? {
    if let channel = view.peers[view.peerId] as? TelegramChannel, channel.isMonoForum, let linkedMonoforumId = channel.linkedMonoforumId {
        return view.peers[linkedMonoforumId]
    }
    return nil
}
