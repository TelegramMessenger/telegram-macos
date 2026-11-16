import AppKit
import Postbox
import TelegramCore

struct ChatTitleLeadingIcons {
    static func badgePeer(_ peer: Peer?, allowed: Bool) -> Peer? {
        guard allowed, let peer, peer.verificationIconFileId != nil else { return nil }
        return peer
    }

    static func badgeInset(_ width: CGFloat?) -> CGFloat {
        return width.map { $0 + 2 } ?? 0
    }

    static func insets(base: CGFloat, badgeWidth: CGFloat?, hasLock: Bool) -> (text: CGFloat, title: CGFloat) {
        let inset = badgeInset(badgeWidth)
        return hasLock ? (base + inset, 0) : (base, inset)
    }

    static func verificationFrame(title: CGRect, lockWidth: CGFloat?, badgeSize: CGSize) -> CGRect {
        let lockInset = lockWidth.map { $0 + 4 } ?? 0
        return CGRect(x: title.minX - lockInset - badgeSize.width - 2, y: title.minY + 1,
                      width: badgeSize.width, height: badgeSize.height)
    }
}
