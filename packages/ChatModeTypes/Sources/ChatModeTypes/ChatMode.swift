import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import Localization
import TelegramUtils
import InputView

public enum ReplyThreadMode : Equatable {
    case replies(origin: MessageId)
    case comments(origin: MessageId)
    case topic(origin: MessageId)
    case savedMessages(origin: MessageId)
    case saved(origin: MessageId)
    public var originId: MessageId {
        switch self {
        case let .replies(id), let .comments(id), let .topic(id), let .savedMessages(id), let .saved(id):
            return id
        }
    }
}

public enum ChatCustomContentsKind: Equatable {
    case greetingMessageInput
    case awayMessageInput
    case quickReplyMessageInput(shortcut: String)
    case welcomeMessages
    case searchHashtag(hashtag: String, onlyMy: Bool)
    case htmlDemo(title: String, status: String)
    public var text: String {
        switch self {
        case .greetingMessageInput:
            return strings().chatTitleBusinessGreetingMessages
        case .awayMessageInput:
            return strings().chatTitleBusinessAwayMessages
        case .quickReplyMessageInput(let shortcut):
            return shortcut
        case .welcomeMessages:
            return strings().welcomeMessageTitle
        case let .searchHashtag(hashtag, _):
            return "#\(hashtag)"
        case let .htmlDemo(title, _):
            return title
        }
    }

    public var status: String {
        switch self {
        case let .htmlDemo(_, status):
            return status
        default:
            return ""
        }
    }

    public var isHTMLDemo: Bool {
        if case .htmlDemo = self {
            return true
        }
        return false
    }
    
    public var hashtag: String? {
        switch self {
        case let .searchHashtag(hashtag, _):
            return "#\(hashtag)"
        default:
            return nil
        }
    }
}

public protocol ChatCustomContentsProtocol: AnyObject {
    var kind: ChatCustomContentsKind { get }
    var messageLimit: Int? { get }
    var historyView: Signal<(MessageHistoryView, ViewUpdateType), NoError> { get }

    func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?],NoError>
    func deleteMessages(ids: [EngineMessage.Id])
    func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool)
    
    func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError>

    
    func hashtagSearchUpdate(query: String)
    var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void { get set }

    func loadMore()
}

public class ChatCustomLinkContent  {
    public var link: String
    public var text: ChatTextInputState
    public var name: String {
        didSet {
            interfaceUpdate?()
        }
    }

    
    public var editName: (()->Void)? = nil
    public var interfaceUpdate:(()->Void)? = nil
    public var saveText:((ChatTextInputState)->Void)? = nil

    public init(link: String, name: String, text: ChatTextInputState) {
        self.link = link
        self.name = name
        self.text = text
    }
}

public enum ChatMode : Equatable {
    public static func == (lhs: ChatMode, rhs: ChatMode) -> Bool {
        switch lhs {
        case .history:
            if case .history = rhs {
                return true
            } else {
                return false
            }
        case .scheduled:
            if case .scheduled = rhs {
                return true
            } else {
                return false
            }
        case .pinned:
            if case .pinned = rhs {
                return true
            } else {
                return false
            }
        case let .thread(mode):
            if case .thread(mode) = rhs {
                return true
            } else {
                return false
            }
        case .customChatContents:
            if case .customChatContents = rhs {
                return true
            } else {
                return false
            }
        case .customLink:
            if case .customLink = rhs {
                return true
            } else {
                return false
            }
        case .preview:
            if case .preview = rhs {
                return true
            } else {
                return false
            }
        }
    }
    
    case history
    case scheduled
    case pinned
    case preview
    case thread(mode: ReplyThreadMode)
    case customChatContents(contents: ChatCustomContentsProtocol)
    case customLink(contents: ChatCustomLinkContent)
    
    public var customChatContents: ChatCustomContentsProtocol? {
        switch self {
        case let .customChatContents(contents):
            return contents
        default:
            return nil
        }
    }
    
    public var customChatLink: ChatCustomLinkContent? {
        switch self {
        case let .customLink(contents):
            return contents
        default:
            return nil
        }
    }

    public var threadMode: ReplyThreadMode? {
        switch self {
        case let .thread(mode):
            return mode
        default:
            return nil
        }
    }
    public var isSavedMessagesThread: Bool {
        switch self {
        case let .thread(mode):
            switch mode {
            case .savedMessages:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    public var isSavedMode: Bool {
        switch self {
        case let .thread(mode):
            switch mode {
            case .saved:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    
    public func activityCategory(_ threadId: Int64?) -> PeerActivitySpace.Category {
        let activityCategory: PeerActivitySpace.Category
        if let threadId {
            activityCategory = .thread(threadId)
        } else {
            activityCategory = .global
        }
        return activityCategory
    }
    
    public var tagMask: MessageTags? {
        switch self {
        case .pinned:
            return .pinned
        default:
            return nil
        }
    }
    
    public var isThreadMode: Bool {
        switch self {
        case let .thread(mode):
            switch mode {
            case .topic, .savedMessages:
                return false
            default:
                return true
            }
        default:
            return false
        }
    }
    public var isTopicMode: Bool {
        switch self {
        case let .thread(mode):
            switch mode {
            case .topic:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    public var originId: MessageId? {
        switch self {
        case let .thread(mode):
            return mode.originId
        default:
            return nil
        }
    }
}
