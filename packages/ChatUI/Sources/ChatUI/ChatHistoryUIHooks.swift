import Cocoa
import TGUIKit
import ColorPalette
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramLinks
import TelegramMediaUtils
import InputDataUI
import PhoneNumberUtils
import LocalAnimations
import ChatHistoryModel
import RichTextEditorCore
import RichTextEditorUI
import InlineStickerLayer
import ChatModeTypes
import SceneEffects

public enum ChatHistoryInAppLink {
    case external(link: String, Bool)
    case followResolvedName(link: String, username: String, postId: Int32?, forceProfile: Bool, context: any AccountContextProtocol, action: ChatInitialAction?, callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)
    case comments(link: String, username: String, context: any AccountContextProtocol, threadId: Int32, commentId: Int32?)
    case joinchat(link: String, String, context: any AccountContextProtocol, callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)
    case wallpaper(link: String, context: any AccountContextProtocol, preview: WallpaperPreview)
    case folder(link: String, slug: String, context: any AccountContextProtocol)
    case story(link: String, username: String, storyId: Int32, messageId: MessageId?, context: any AccountContextProtocol)
    case boost(link: String, username: String, context: any AccountContextProtocol)
    case other
}

public protocol ChatHistoryInAppLinkValue {
    var link: String { get }
    var chatHistoryInAppLink: ChatHistoryInAppLink { get }
}

public struct ChatHistoryEmojiSelectedItem : Equatable {
    public enum Selection : Equatable {
        case normal
        case transparent
    }
    public enum Source : Equatable {
        case builtin(String)
        case custom(Int64)
    }
    public let source : Source
    public let type: Selection
    public init(source: Source, type: Selection) {
        self.source = source
        self.type = type
    }
}

public protocol ChatHistoryReactionsWindow: AnyObject {
    func showChatHistoryReactions(_ initialView: NSView & StickerFramesCollector)
}

public enum ChatHistoryForwardResult {
    case draftPrepared
    case destinationReady
    case accepted
    case partiallyAccepted
    case rejected
    case acceptanceUnknown
    case sourceUnavailable
    case targetUnavailable
    case restricted
    case completionUnknown
}

public protocol ChatHistoryForwardMessagesObject: AnyObject {
    func chatHistoryPerform(to peerIds: [PeerId], threadId: Int64?) -> Signal<Never, String>
    func possibilityPerformTo(_ peer: Peer) -> Bool
    func chatHistoryPerformObserved(to peerId: PeerId, threadId: Int64?) -> Signal<ChatHistoryForwardResult, String>
}

public extension ChatHistoryForwardMessagesObject {
    func chatHistoryPerformObserved(to peerId: PeerId, threadId: Int64?) -> Signal<ChatHistoryForwardResult, String> {
        return Signal { subscriber in
            self.chatHistoryPerform(to: [peerId], threadId: threadId).start(error: { subscriber.putError($0) }, completed: {
                subscriber.putNext(.completionUnknown)
                subscriber.putCompletion()
            })
        }
    }
}

public protocol ChatHistoryAntiSpamBotConfiguration {
    var antiSpamBotId: EnginePeer.Id? { get }
}

public enum ChatHistoryLink {
    public static func peerInfo(link: String, peerId: PeerId, action: ChatInitialAction?, openChat: Bool, postId: Int32?, callback: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any {
        return ChatHistoryUIHooks.shared.peerInfoLink(link, peerId, action, openChat, postId, callback)
    }

    public static func followResolvedName(link: String, username: String, postId: Int32?, forceProfile: Bool, context: any AccountContextProtocol, action: ChatInitialAction?, callback: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any {
        return ChatHistoryUIHooks.shared.followResolvedNameLink(link, username, postId, forceProfile, context, action, callback)
    }

    public static func botCommand(_ command: String, _ callback: @escaping (String) -> Void) -> Any {
        return ChatHistoryUIHooks.shared.botCommandLink(command, callback)
    }

    public static func code(_ code: String, _ callback: @escaping (String) -> Void) -> Any {
        return ChatHistoryUIHooks.shared.codeLink(code, callback)
    }

    public static func hashtag(_ hashtag: String, _ callback: @escaping (String) -> Void) -> Any {
        return ChatHistoryUIHooks.shared.hashtagLink(hashtag, callback)
    }

    public static func external(link: String, _ confirm: Bool) -> ChatHistoryInAppLinkValue {
        return ChatHistoryUIHooks.shared.externalLink(link, confirm)
    }

    public static func gift(link: String, slug: String, context: any AccountContextProtocol) -> ChatHistoryInAppLinkValue {
        return ChatHistoryUIHooks.shared.giftLink(link, slug, context)
    }

    public static func inApp(for url: NSString, context: (any AccountContextProtocol)? = nil, peerId: PeerId? = nil, messageId: MessageId? = nil, openInfo: ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)? = nil, hashtag: ((String) -> Void)? = nil, command: ((String) -> Void)? = nil, applyProxy: ((ProxyServerSettings) -> Void)? = nil, confirm: Bool = false) -> ChatHistoryInAppLinkValue {
        return ChatHistoryUIHooks.shared.inAppLink(url, context, peerId, messageId, openInfo, hashtag, command, applyProxy, confirm)
    }

    public static func execute(inapp: Any) {
        if let executeLinkWithContext = ChatHistoryUIHooks.shared.executeLinkWithContext {
            executeLinkWithContext(inapp)
        } else {
            ChatHistoryUIHooks.shared.executeLink(inapp)
        }
    }

    public static func detectLinks(_ string: NSMutableAttributedString, type: ParsingType, onlyInApp: Bool = false, context: (any AccountContextProtocol)? = nil, color: NSColor = theme.colors.link, openInfo: ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)? = nil, hashtag: ((String) -> Void)? = nil, command: ((String) -> Void)? = nil, applyProxy: ((ProxyServerSettings) -> Void)? = nil, dotInMention: Bool = false) {
        ChatHistoryUIHooks.shared.detectLinks(string, type, onlyInApp, context, color, openInfo, hashtag, command, applyProxy, dotInMention)
    }

    public static func copyContextText(from type: LinkType) -> String {
        return ChatHistoryUIHooks.shared.copyContextText(type)
    }
}

@available(macOS 10.15, *)
public protocol ChatWalletCardView: View {
    var onDiamondLanding: ((CGFloat) -> Void)? { get set }
    func update(amount: Int64, isIncoming: Bool, name: String, address: String)
    func updateShimmer(visible: Bool, repeating: Bool, animated: Bool, completion: (() -> Void)?)
    func updateTransferState(isSending: Bool, isPending: Bool, animateCompletion: Bool)
    func resetTransferState()
    func setAwaitingTransferFlight(_ awaiting: Bool, animated: Bool)
    func transferDiamondTarget(in view: NSView) -> (center: NSPoint, width: CGFloat)?
    func acceptTransferDiamond(_ diamond: InteractiveDiamondView)
    func setCovered(_ covered: Bool)
    var onArrivalInterrupted: (() -> Void)? { get set }
    var isDiamondExpanded: Bool { get }
    func prepareIncomingTransferAnimation()
    func updateIncomingTransferAnimation(startTime: CFTimeInterval, at timestamp: CFTimeInterval) -> Double
    func finishIncomingTransferAnimation()
}

@available(macOS 10.15, *)
public struct ChatHistoryWalletHooks {
    public let walletContext: (any AccountContextProtocol) -> (any ChatWalletContext)?
    public let makeWalletTransactionController: (any AccountContextProtocol, any ChatWalletContext, ChatServiceItem.WalletTransferData, Int32, Bool) -> InputDataModalController
    public let makeWalletGramInfoController: (any AccountContextProtocol, any ChatWalletContext) -> InputDataModalController
    public let makeCardView: (NSRect) -> any ChatWalletCardView
    public let resolveTonAddress: (any AccountContextProtocol, any ChatWalletContext, String) -> Signal<ChatWalletTonAddress?, NoError>

    public init(walletContext: @escaping (any AccountContextProtocol) -> (any ChatWalletContext)?,
                makeWalletTransactionController: @escaping (any AccountContextProtocol, any ChatWalletContext, ChatServiceItem.WalletTransferData, Int32, Bool) -> InputDataModalController,
                makeWalletGramInfoController: @escaping (any AccountContextProtocol, any ChatWalletContext) -> InputDataModalController,
                makeCardView: @escaping (NSRect) -> any ChatWalletCardView,
                resolveTonAddress: @escaping (any AccountContextProtocol, any ChatWalletContext, String) -> Signal<ChatWalletTonAddress?, NoError>) {
        self.walletContext = walletContext
        self.makeWalletTransactionController = makeWalletTransactionController
        self.makeWalletGramInfoController = makeWalletGramInfoController
        self.makeCardView = makeCardView
        self.resolveTonAddress = resolveTonAddress
    }
}

@available(macOS 12, *)
public struct ChatHistoryRichTextHooks {
    public let blocksFromInAppPasteboard: () -> [Block]?
    public let installSyntaxHighlighter: (RichTextEditorView, @escaping () -> TelegramPresentationTheme) -> Void
    public let makeMediaContentView: (Media, CGFloat, Bool, any AccountContextProtocol, ChatInteraction) -> NSView
    public let makeCollageTileView: (Media, NSSize, Bool, any AccountContextProtocol, ChatInteraction) -> NSView
    public let makeSliderView: ([String], CGFloat, @escaping (String) -> Media?, any AccountContextProtocol) -> NSView?
    public let makeSpoilerEffect: () -> SpoilerEffect

    public init(blocksFromInAppPasteboard: @escaping () -> [Block]?,
                installSyntaxHighlighter: @escaping (RichTextEditorView, @escaping () -> TelegramPresentationTheme) -> Void,
                makeMediaContentView: @escaping (Media, CGFloat, Bool, any AccountContextProtocol, ChatInteraction) -> NSView,
                makeCollageTileView: @escaping (Media, NSSize, Bool, any AccountContextProtocol, ChatInteraction) -> NSView,
                makeSliderView: @escaping ([String], CGFloat, @escaping (String) -> Media?, any AccountContextProtocol) -> NSView?,
                makeSpoilerEffect: @escaping () -> SpoilerEffect) {
        self.blocksFromInAppPasteboard = blocksFromInAppPasteboard
        self.installSyntaxHighlighter = installSyntaxHighlighter
        self.makeMediaContentView = makeMediaContentView
        self.makeCollageTileView = makeCollageTileView
        self.makeSliderView = makeSliderView
        self.makeSpoilerEffect = makeSpoilerEffect
    }
}

public enum ChatHistoryTranslationSource {
    case richMessage(MessageId?, InstantPage?)
    case poll(MessageId?)
    case message(MessageId?)
    case selectedText
    case transcription(MessageId?)

    var messageId: MessageId? {
        switch self {
        case let .richMessage(id, _), let .poll(id), let .message(id), let .transcription(id): return id
        case .selectedText: return nil
        }
    }
}

public struct ChatHistoryUIHooks {
    public let peerInfoLink: (String, PeerId, ChatInitialAction?, Bool, Int32?, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any
    public let followResolvedNameLink: (String, String, Int32?, Bool, any AccountContextProtocol, ChatInitialAction?, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any
    public let botCommandLink: (String, @escaping (String) -> Void) -> Any
    public let codeLink: (String, @escaping (String) -> Void) -> Any
    public let hashtagLink: (String, @escaping (String) -> Void) -> Any
    public let externalLink: (String, Bool) -> ChatHistoryInAppLinkValue
    public let giftLink: (String, String, any AccountContextProtocol) -> ChatHistoryInAppLinkValue
    public let inAppLink: (NSString, (any AccountContextProtocol)?, PeerId?, MessageId?, ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)?, ((String) -> Void)?, ((String) -> Void)?, ((ProxyServerSettings) -> Void)?, Bool) -> ChatHistoryInAppLinkValue
    public let executeLink: (Any) -> Void
    public var executeLinkWithContext: ((Any) -> Void)?
    public let detectLinks: (NSMutableAttributedString, ParsingType, Bool, (any AccountContextProtocol)?, NSColor, ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)?, ((String) -> Void)?, ((String) -> Void)?, ((ProxyServerSettings) -> Void)?, Bool) -> Void
    public let copyContextText: (LinkType) -> String
    public let applyCodeSyntax: (NSMutableAttributedString, NSRange, String?, Message?, Bool, Bool, Bool, NSColor, CGFloat, [CodeSyntaxKey : CodeSyntaxResult], @escaping (MessageId, NSRange, String, String, ChatInterfaceSyntaxTheme) -> Void) -> Void
    public let generateSyntaxThemeParams: (TelegramPresentationTheme, Bool, Bool) -> [String: NSColor]
    public let makeShareMessageModal: (any AccountContextProtocol, Message) -> ModalViewController
    public let makeShareGroupedMessagesModal: (any AccountContextProtocol, Message, [Message]) -> ModalViewController
    public var makeShareMessagesModalWithContext: ((any AccountContextProtocol, Message, [Message]?) -> ModalViewController)?

    public func makeShareMessagesModalObserved(_ context: any AccountContextProtocol, _ message: Message, groupedMessages: [Message]? = nil) -> ModalViewController {
        let controller: ModalViewController
        if let makeShareMessagesModalWithContext {
            controller = makeShareMessagesModalWithContext(context, message, groupedMessages)
        } else if let groupedMessages {
            controller = makeShareGroupedMessagesModal(context, message, groupedMessages)
        } else {
            controller = makeShareMessageModal(context, message)
        }
        return controller
    }
    public let pushReactionPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId, MessageId) -> Void
    public var pushReactionPeerInfoWithContext: ((NavigationViewController, any AccountContextProtocol, PeerId, MessageId) -> Void)?
    public func pushReactionPeerInfoObserved(_ navigation: NavigationViewController, _ context: any AccountContextProtocol, _ peerId: PeerId, _ messageId: MessageId) {
        if let pushReactionPeerInfoWithContext {
            pushReactionPeerInfoWithContext(navigation, context, peerId, messageId)
        } else {
            pushReactionPeerInfo(navigation, context, peerId, messageId)
        }
    }
    public let pushEditPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let openTopic: (Int64, PeerId, any AccountContextProtocol, MessageId?) -> Signal<Bool, NoError>
    public let makeChannelParticipantController: (any AccountContextProtocol, PeerId, RenderedChannelParticipant) -> InputDataModalController
    public var makeChannelParticipantControllerWithContext: ((any AccountContextProtocol, PeerId, RenderedChannelParticipant) -> InputDataModalController)?
    public func makeChannelParticipantControllerObserved(_ context: any AccountContextProtocol, _ peerId: PeerId, _ participant: RenderedChannelParticipant) -> InputDataModalController {
        if let makeChannelParticipantControllerWithContext {
            return makeChannelParticipantControllerWithContext(context, peerId, participant)
        } else {
            return makeChannelParticipantController(context, peerId, participant)
        }
    }

    public let makeRestrictedModalController: (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?, @escaping (TelegramChatBannedRights) -> Void) -> InputDataModalController
    public let makeChannelAdminModalController: (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?, @escaping (TelegramChatAdminRights?) -> Void, @escaping (PeerId, @escaping () -> Void) -> Void) -> InputDataModalController
    public let makeFragmentAdsInfoController: (any AccountContextProtocol, Message?, ChatInteraction?) -> InputDataModalController
    public let makeRichMessageTranslateModal: (any AccountContextProtocol, String?, String, String, [MessageTextEntity], MessageId?, InstantPage?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController
    public let makePollTranslateModal: (any AccountContextProtocol, String?, String, String, [MessageTextEntity], MessageId?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController
    public let makeMessageTranslateModal: (any AccountContextProtocol, String?, String, String, [MessageTextEntity], MessageId?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController
    public let makeSelectedTextTranslateModal: (any AccountContextProtocol, String?, String, String, [MessageTextEntity], ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController
    public let makeTranscriptionTranslateModal: (any AccountContextProtocol, String?, String, String, MessageId?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController
    public var makeTranslateModalWithContext: ((any AccountContextProtocol, String?, String, String, [MessageTextEntity], ChatHistoryTranslationSource, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController)?

    public func makeTranslateModalObserved(_ context: any AccountContextProtocol, _ from: String?, _ toLang: String, _ text: String, _ entities: [MessageTextEntity], source: ChatHistoryTranslationSource, onToneChanged: ((TranslationTone) -> Void)?, translateEntireChat: (() -> Void)?) -> InputDataModalController {
        let tone: ((TranslationTone) -> Void)? = onToneChanged.map { callback in
            return { value in
                callback(value)
            }
        }
        let entire: (() -> Void)? = translateEntireChat.map { callback in
            return {
                callback()
            }
        }
        if let makeTranslateModalWithContext {
            return makeTranslateModalWithContext(context, from, toLang, text, entities, source, tone, entire)
        }
        switch source {
        case let .richMessage(id, page): return makeRichMessageTranslateModal(context, from, toLang, text, entities, id, page, tone, entire)
        case let .poll(id): return makePollTranslateModal(context, from, toLang, text, entities, id, tone, entire)
        case let .message(id): return makeMessageTranslateModal(context, from, toLang, text, entities, id, tone, entire)
        case .selectedText: return makeSelectedTextTranslateModal(context, from, toLang, text, entities, tone, entire)
        case let .transcription(id): return makeTranscriptionTranslateModal(context, from, toLang, text, id, tone, entire)
        }
    }

    public let communityFilterCategories: (Account) -> Signal<[PeerId: ChatListFilterPeerCategories], NoError>
    public let chatListFilterPredicate: (ChatListFilter?, [PeerId: ChatListFilterPeerCategories]) -> ChatListFilterPredicate?
    public let chatListFilterIsAllChats: (ChatListFilter) -> Bool
    public let forumChatListItems: (PeerId, Account) -> Signal<[EngineChatList.Item], NoError>
    public let makeDownloadSearch: (any AccountContextProtocol) -> Void
    public let folderEmoticonDrawable: (FolderEmoticon) -> MenuAnimation
    public let makeForwardMessagesObject: (any AccountContextProtocol, [Message], Bool, (([MessageId], Bool) -> Signal<[Message], NoError>)?) -> ChatHistoryForwardMessagesObject
    public var makeForwardMessagesObjectWithContext: ((any AccountContextProtocol, [Message], Bool, (([MessageId], Bool) -> Signal<[Message], NoError>)?) -> ChatHistoryForwardMessagesObject)?

    public func makeForwardMessagesObjectObserved(_ context: any AccountContextProtocol, _ messages: [Message], _ album: Bool, _ getMessages: (([MessageId], Bool) -> Signal<[Message], NoError>)?) -> ChatHistoryForwardMessagesObject {
        let lookup = getMessages.map { lookup in
            return { (ids: [MessageId], album: Bool) -> Signal<[Message], NoError> in
                return (lookup(ids, album))
            }
        }
        if let makeForwardMessagesObjectWithContext {
            return makeForwardMessagesObjectWithContext(context, messages, album, lookup)
        }
        return makeForwardMessagesObject(context, messages, album, lookup)
    }

    public let antiSpamBotConfiguration: (AppConfiguration) -> ChatHistoryAntiSpamBotConfiguration
    public let checkForUpdates: () -> Void
    public let navigateToScheduledChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void
    public let requestPhoneCall: (any AccountContextProtocol, PeerId, Bool) -> Disposable
    public let joinConferenceCall: (any AccountContextProtocol, GroupCallInfo, InternalGroupCallReference) -> Disposable
    public let storyLayoutViewSize: () -> NSSize
    public let giftStickers: (any AccountContextProtocol) -> Signal<[TelegramMediaFile], NoError>
    public let messageNewReactions: (Message, UpdateMessageReaction, Bool) -> [UpdateMessageReaction]
    public let makeReactionsWindow: (any AccountContextProtocol, PeerId, [ChatHistoryEmojiSelectedItem], [RecentReactionItem]?, @escaping (StickerPackItem, NSRect?) -> Void, ((StickerPackItem, NSRect?) -> Void)?) -> ChatHistoryReactionsWindow
    public let currencyAmount: (any AccountContextProtocol, CurrencyAmount, Double) -> CurrencyAmount
    public let currentCountriesConfiguration: (any AccountContextProtocol) -> Atomic<CountriesConfiguration>
    public let reactionSettings: (any AccountContextProtocol) -> ReactionSettings
    public let chatListFilterTitle: (ChatListFilter) -> String
    public let showCommunityView: (any AccountContextProtocol, PeerId) -> Void
    public let emptyChatControllerType: () -> ViewController.Type
    public let wallet: Any?
    public let richText: Any?

    public init(peerInfoLink: @escaping (String, PeerId, ChatInitialAction?, Bool, Int32?, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any,
                followResolvedNameLink: @escaping (String, String, Int32?, Bool, any AccountContextProtocol, ChatInitialAction?, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any,
                botCommandLink: @escaping (String, @escaping (String) -> Void) -> Any,
                codeLink: @escaping (String, @escaping (String) -> Void) -> Any,
                hashtagLink: @escaping (String, @escaping (String) -> Void) -> Any,
                externalLink: @escaping (String, Bool) -> ChatHistoryInAppLinkValue,
                giftLink: @escaping (String, String, any AccountContextProtocol) -> ChatHistoryInAppLinkValue,
                inAppLink: @escaping (NSString, (any AccountContextProtocol)?, PeerId?, MessageId?, ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)?, ((String) -> Void)?, ((String) -> Void)?, ((ProxyServerSettings) -> Void)?, Bool) -> ChatHistoryInAppLinkValue,
                executeLink: @escaping (Any) -> Void,
                detectLinks: @escaping (NSMutableAttributedString, ParsingType, Bool, (any AccountContextProtocol)?, NSColor, ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)?, ((String) -> Void)?, ((String) -> Void)?, ((ProxyServerSettings) -> Void)?, Bool) -> Void,
                copyContextText: @escaping (LinkType) -> String,
                applyCodeSyntax: @escaping (NSMutableAttributedString, NSRange, String?, Message?, Bool, Bool, Bool, NSColor, CGFloat, [CodeSyntaxKey : CodeSyntaxResult], @escaping (MessageId, NSRange, String, String, ChatInterfaceSyntaxTheme) -> Void) -> Void,
                generateSyntaxThemeParams: @escaping (TelegramPresentationTheme, Bool, Bool) -> [String: NSColor],
                makeShareMessageModal: @escaping (any AccountContextProtocol, Message) -> ModalViewController,
                makeShareGroupedMessagesModal: @escaping (any AccountContextProtocol, Message, [Message]) -> ModalViewController,
                pushReactionPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId, MessageId) -> Void,
                pushEditPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                openTopic: @escaping (Int64, PeerId, any AccountContextProtocol, MessageId?) -> Signal<Bool, NoError>,
                makeChannelParticipantController: @escaping (any AccountContextProtocol, PeerId, RenderedChannelParticipant) -> InputDataModalController,
                makeRestrictedModalController: @escaping (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?, @escaping (TelegramChatBannedRights) -> Void) -> InputDataModalController,
                makeChannelAdminModalController: @escaping (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?, @escaping (TelegramChatAdminRights?) -> Void, @escaping (PeerId, @escaping () -> Void) -> Void) -> InputDataModalController,
                makeFragmentAdsInfoController: @escaping (any AccountContextProtocol, Message?, ChatInteraction?) -> InputDataModalController,
                makeRichMessageTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, [MessageTextEntity], MessageId?, InstantPage?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController,
                makePollTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, [MessageTextEntity], MessageId?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController,
                makeMessageTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, [MessageTextEntity], MessageId?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController,
                makeSelectedTextTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, [MessageTextEntity], ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController,
                makeTranscriptionTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, MessageId?, ((TranslationTone) -> Void)?, (() -> Void)?) -> InputDataModalController,
                communityFilterCategories: @escaping (Account) -> Signal<[PeerId: ChatListFilterPeerCategories], NoError>,
                chatListFilterPredicate: @escaping (ChatListFilter?, [PeerId: ChatListFilterPeerCategories]) -> ChatListFilterPredicate?,
                chatListFilterIsAllChats: @escaping (ChatListFilter) -> Bool,
                forumChatListItems: @escaping (PeerId, Account) -> Signal<[EngineChatList.Item], NoError>,
                makeDownloadSearch: @escaping (any AccountContextProtocol) -> Void,
                folderEmoticonDrawable: @escaping (FolderEmoticon) -> MenuAnimation,
                makeForwardMessagesObject: @escaping (any AccountContextProtocol, [Message], Bool, (([MessageId], Bool) -> Signal<[Message], NoError>)?) -> ChatHistoryForwardMessagesObject,
                antiSpamBotConfiguration: @escaping (AppConfiguration) -> ChatHistoryAntiSpamBotConfiguration,
                checkForUpdates: @escaping () -> Void,
                navigateToScheduledChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void,
                requestPhoneCall: @escaping (any AccountContextProtocol, PeerId, Bool) -> Disposable,
                joinConferenceCall: @escaping (any AccountContextProtocol, GroupCallInfo, InternalGroupCallReference) -> Disposable,
                storyLayoutViewSize: @escaping () -> NSSize,
                giftStickers: @escaping (any AccountContextProtocol) -> Signal<[TelegramMediaFile], NoError>,
                messageNewReactions: @escaping (Message, UpdateMessageReaction, Bool) -> [UpdateMessageReaction],
                makeReactionsWindow: @escaping (any AccountContextProtocol, PeerId, [ChatHistoryEmojiSelectedItem], [RecentReactionItem]?, @escaping (StickerPackItem, NSRect?) -> Void, ((StickerPackItem, NSRect?) -> Void)?) -> ChatHistoryReactionsWindow,
                currencyAmount: @escaping (any AccountContextProtocol, CurrencyAmount, Double) -> CurrencyAmount,
                currentCountriesConfiguration: @escaping (any AccountContextProtocol) -> Atomic<CountriesConfiguration>,
                reactionSettings: @escaping (any AccountContextProtocol) -> ReactionSettings,
                chatListFilterTitle: @escaping (ChatListFilter) -> String,
                showCommunityView: @escaping (any AccountContextProtocol, PeerId) -> Void,
                emptyChatControllerType: @escaping () -> ViewController.Type,
                wallet: Any?,
                richText: Any?) {
        self.peerInfoLink = peerInfoLink
        self.followResolvedNameLink = followResolvedNameLink
        self.botCommandLink = botCommandLink
        self.codeLink = codeLink
        self.hashtagLink = hashtagLink
        self.externalLink = externalLink
        self.giftLink = giftLink
        self.inAppLink = inAppLink
        self.executeLink = executeLink
        self.detectLinks = detectLinks
        self.copyContextText = copyContextText
        self.applyCodeSyntax = applyCodeSyntax
        self.generateSyntaxThemeParams = generateSyntaxThemeParams
        self.makeShareMessageModal = makeShareMessageModal
        self.makeShareGroupedMessagesModal = makeShareGroupedMessagesModal
        self.pushReactionPeerInfo = pushReactionPeerInfo
        self.pushEditPeerInfo = pushEditPeerInfo
        self.openTopic = openTopic
        self.makeChannelParticipantController = makeChannelParticipantController
        self.makeRestrictedModalController = makeRestrictedModalController
        self.makeChannelAdminModalController = makeChannelAdminModalController
        self.makeFragmentAdsInfoController = makeFragmentAdsInfoController
        self.makeRichMessageTranslateModal = makeRichMessageTranslateModal
        self.makePollTranslateModal = makePollTranslateModal
        self.makeMessageTranslateModal = makeMessageTranslateModal
        self.makeSelectedTextTranslateModal = makeSelectedTextTranslateModal
        self.makeTranscriptionTranslateModal = makeTranscriptionTranslateModal
        self.communityFilterCategories = communityFilterCategories
        self.chatListFilterPredicate = chatListFilterPredicate
        self.chatListFilterIsAllChats = chatListFilterIsAllChats
        self.forumChatListItems = forumChatListItems
        self.makeDownloadSearch = makeDownloadSearch
        self.folderEmoticonDrawable = folderEmoticonDrawable
        self.makeForwardMessagesObject = makeForwardMessagesObject
        self.antiSpamBotConfiguration = antiSpamBotConfiguration
        self.checkForUpdates = checkForUpdates
        self.navigateToScheduledChat = navigateToScheduledChat
        self.requestPhoneCall = requestPhoneCall
        self.joinConferenceCall = joinConferenceCall
        self.storyLayoutViewSize = storyLayoutViewSize
        self.giftStickers = giftStickers
        self.messageNewReactions = messageNewReactions
        self.makeReactionsWindow = makeReactionsWindow
        self.currencyAmount = currencyAmount
        self.currentCountriesConfiguration = currentCountriesConfiguration
        self.reactionSettings = reactionSettings
        self.chatListFilterTitle = chatListFilterTitle
        self.showCommunityView = showCommunityView
        self.emptyChatControllerType = emptyChatControllerType
        self.wallet = wallet
        self.richText = richText
    }

    @available(macOS 10.15, *)
    public var walletHooks: ChatHistoryWalletHooks {
        return wallet as! ChatHistoryWalletHooks
    }

    @available(macOS 12, *)
    public var richTextHooks: ChatHistoryRichTextHooks {
        return richText as! ChatHistoryRichTextHooks
    }

    private static var _shared: ChatHistoryUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatHistoryUIHooks {
        if let value = _shared {
            return value
        }
        preconditionFailure("ChatHistoryUIHooks.install must be called before chat history rows are used")
    }

    public static func install(_ hooks: ChatHistoryUIHooks) {
        assert(Thread.isMainThread, "ChatHistoryUIHooks.install must be called on the main thread")
        _shared = hooks
    }
}

