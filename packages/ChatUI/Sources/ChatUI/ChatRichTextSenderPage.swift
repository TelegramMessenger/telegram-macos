import TelegramCore
import InstantPageUI

final class ChatRichTextSenderPage {
    private var cached: (original: InstantPage, shown: InstantPage)?

    func resolve(_ page: InstantPage, isIncoming: Bool, allowsLinks: Bool) -> InstantPage {
        guard isIncoming, !allowsLinks else {
            return page
        }
        if let cached, cached.original === page {
            return cached.shown
        }
        let shown = instantPageForSuspiciousSender(page)
        self.cached = (page, shown)
        return shown
    }

    static func allowsOpenURL(_ url: String, isIncoming: Bool, allowsLinks: Bool) -> Bool {
        return !isIncoming || allowsLinks || url.hasPrefix("tel:")
    }
}
