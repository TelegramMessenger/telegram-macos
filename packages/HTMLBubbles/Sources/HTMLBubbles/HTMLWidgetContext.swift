import Foundation
import Postbox
import TelegramCore
import WidgetSandbox

public struct HTMLWidgetContext: Equatable {
    public let accountPeerId: PeerId
    public let basePath: String
    public let messageId: MessageId
    public let locale: String
    public let runtime: WidgetContext

    public init(accountPeerId: PeerId, basePath: String, messageId: MessageId, locale: String, runtime: WidgetContext = WidgetContext()) {
        self.accountPeerId = accountPeerId
        self.basePath = basePath
        self.messageId = messageId
        self.locale = HTMLWidgetContext.bcp47(locale)
        self.runtime = runtime
    }

    public init(accountPeerId: PeerId, basePath: String, message: Message, widget: TelegramMediaWidget, locale: String, viewer: TelegramUser?, isPremium: Bool, walletAvailable: Bool = false) {
        let peer = message.peers[message.id.peerId]
        let chatType: WidgetChatType?
        if widget.isCopy {
            chatType = nil
        } else if peer is TelegramGroup {
            chatType = .group
        } else if let channel = peer as? TelegramChannel {
            if case .broadcast = channel.info {
                chatType = .channel
            } else {
                chatType = .supergroup
            }
        } else if peer is TelegramUser || peer is TelegramSecretChat {
            chatType = .private
        } else {
            chatType = nil
        }
        let runtime = WidgetContext(isCopy: widget.isCopy, canQuery: widget.canQuery, backgroundQuery: widget.backgroundQuery, chatType: chatType, viewer: widget.canQuery ? WidgetViewer(id: accountPeerId.id._internalGetInt64Value(), firstName: viewer?.firstName, lastName: viewer?.lastName, username: viewer?.addressName, isPremium: isPremium) : nil, wallet: walletAvailable)
        self.init(accountPeerId: accountPeerId, basePath: basePath, messageId: message.id, locale: locale, runtime: runtime)
    }

    static func bcp47(_ code: String) -> String {
        let parts = code.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let first = parts.first, (2 ... 3).contains(first.count), first.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return "en-US"
        }
        var result = [first.lowercased()]
        for part in parts.dropFirst() where part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            if part.count == 2, part.allSatisfy({ $0.isLetter }) {
                result.append(part.uppercased())
            } else if part.count == 4, part.allSatisfy({ $0.isLetter }), result.count == 1 {
                result.append(part.prefix(1).uppercased() + part.dropFirst().lowercased())
            } else if part.count == 3, part.allSatisfy({ $0.isNumber }) {
                result.append(part)
            }
        }
        return result.joined(separator: "-")
    }
}
