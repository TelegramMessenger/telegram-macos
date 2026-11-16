import Cocoa
import Postbox
import TelegramCore
import PremiumStatusUI
import TelegramTheme

struct ChatAuthorVerification {
    static let spacing: CGFloat = 4

    static func peer(author: Peer?, chatId: PeerId, displaysAuthor: Bool) -> Peer? {
        guard displaysAuthor, let author, author.id != chatId, author.verificationIconFileId != nil else { return nil }
        return author
    }

    static func color(incoming: Bool, bubbled: Bool, presentation: TelegramPresentationTheme) -> NSColor {
        return presentation.chat.linkColor(incoming, bubbled)
    }

    static func inset(for peer: Peer?) -> CGFloat {
        guard let peer, let size = PremiumStatusControl.controlSize(peer, false, left: true) else { return 0 }
        return size.width + spacing
    }

    static func frame(nameOrigin: NSPoint, nameHeight: CGFloat, size: NSSize) -> NSRect {
        return NSRect(x: nameOrigin.x - spacing - size.width, y: nameOrigin.y + floor((nameHeight - size.height) / 2), width: size.width, height: size.height)
    }
}
