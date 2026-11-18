import Foundation
import TelegramCore
import Postbox
import Localization

public func makeThreadIdMessageId(peerId: PeerId, threadId: Int64) -> MessageId {
    let messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId))
    return messageId
}

public func makeThreadReplySubject(peerId: PeerId, threadId: Int64?, isMonoforum: Bool) -> EngineMessageReplySubject? {
    guard let threadId, !isMonoforum, threadId != Message.newTopicThreadId else {
        return nil
    }
    return EngineMessageReplySubject(messageId: makeThreadIdMessageId(peerId: peerId, threadId: threadId), quote: nil, innerSubject: nil)
}

public extension SuggestedPostMessageAttribute {
    
    static let commandDecline = "_suggest_decline"
    static let commandApprove = "_suggest_approve"
    static let commandChanges = "_suggest_changes"

    func replyMarkup(isIncoming: Bool) -> ReplyMarkupMessageAttribute {
        
        var rows: [ReplyMarkupRow] = []
        
        if let _ = state {
            
        } else {
            if isIncoming {
                rows.append(.init(buttons: [
                    .init(title: strings().chatMessageSuggestMarkupDecline, titleWhenForwarded: nil, action: .url(SuggestedPostMessageAttribute.commandDecline), style: nil),
                    .init(title: strings().chatMessageSuggestMarkupApprove, titleWhenForwarded: nil, action: .url(SuggestedPostMessageAttribute.commandApprove), style: nil)
                ]))
                rows.append(.init(buttons: [
                    .init(title: strings().chatMessageSuggestMarkupSuggestChanges, titleWhenForwarded: nil, action: .url(SuggestedPostMessageAttribute.commandChanges), style: nil)
                ]))
            } else {
                rows.append(.init(buttons: [
                    .init(title: strings().chatMessageSuggestMarkupEdit, titleWhenForwarded: nil, action: .url(SuggestedPostMessageAttribute.commandChanges), style: nil)
                ]))
            }
        }
        
        return ReplyMarkupMessageAttribute.init(rows: rows, flags: [], placeholder: nil)
    }
}

public extension MessageHistoryView {
    func index(for messageId: MessageId) -> Int? {
        for i in 0 ..< entries.count {
            if entries[i].index.id == messageId {
                return i
            }
        }
        return nil
    }
    
}

public extension MessageReaction.Reaction {
    func toUpdate(_ file: TelegramMediaFile? = nil) -> UpdateMessageReaction {
        switch self {
        case let .custom(fileId):
            return .custom(fileId: fileId, file: file)
        case let .builtin(emoji):
            return .builtin(emoji)
        case .stars:
            return .stars
        }
    }
    var isEmpty: Bool {
        switch self {
        case let .builtin(value):
            return value.isEmpty
        default:
            return false
        }
    }
    var string: String {
        switch self {
        case let .builtin(value):
            return value
        default:
            return ""
        }
    }
}

public extension MessageId {
    var string: String  {
        return "_id_\(id)_\(peerId.id._internalGetInt64Value())"
    }
}

public extension ReplyMarkupMessageAttribute {
    var hasButtons:Bool {
        return !self.rows.isEmpty
    }
}

public extension EngineMessageReplyInnerSubject {
    var id: Int32 {
        switch self {
        case let .todoItem(id):
            return id
        case let .pollOption(data):
            return data.withUnsafeBytes { ptr in
                guard ptr.count >= 4 else {
                    var value: Int32 = 0
                    memcpy(&value, ptr.baseAddress!, ptr.count)
                    return value
                }
                return ptr.load(as: Int32.self)
            }
        }
    }
}

/// A predicate selecting which medias belong in a shared-media tab. Used to filter a rich message's
/// instant-page medias (`effectiveMedia`) down to the medias relevant for the given tab's tag.
