import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramLinks
import TelegramCallsCore
import TelegramMediaUtils
import AudioPlayerCore
import ChatHistoryModel
import ChatModeTypes
import AppAnalytics

public struct ChatUIEmojiSelectedItem : Equatable {
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

public protocol ChatUIBadgeNode: AnyObject {
    var view: View? { get }
    var xInset: CGFloat { get set }
}

protocol ChatControllerKind: ViewController {
    var chatInteraction: ChatInteraction { get }
    var genericView: ChatControllerView { get }
    #if DEBUG
    func debugRebuildFloatingAvatars()
    #endif
}

protocol ChatAdditionControllerKind: ViewController {
}

protocol ChatScheduleControllerKind: ViewController {
}

public struct ChatUIHooks {
    public let clearNotifies: (PeerId, MessageId) -> Void
    public let closeEntertainmentPopover: (any AccountContextProtocol) -> Void
    public let updateEntertainment: (any AccountContextProtocol, ChatInteraction) -> Void
    public let showMessageEffectsWindow: (any AccountContextProtocol, PeerId, [ChatUIEmojiSelectedItem], @escaping (StickerPackItem, NSRect?) -> Void, NSView & StickerFramesCollector) -> Void
    public let makeForwardMessagesShareModal: (any AccountContextProtocol, [Message], @escaping ([MessageId], Bool) -> Signal<[Message], NoError>) -> ModalViewController
    public var makeForwardMessagesShareModalWithContext: ((any AccountContextProtocol, [Message], @escaping ([MessageId], Bool) -> Signal<[Message], NoError>, AnalyticsContext) -> ModalViewController)?
    public var makeForwardMessagesShareModalWithSource: ((any AccountContextProtocol, [Message], @escaping ([MessageId], Bool) -> Signal<[Message], NoError>, AnalyticsContext, AnalyticsFlows.ChatForwardPicker.EntryPoint) -> ModalViewController)?
    public var attachForwardJourney: (ModalViewController, AnalyticsForwardPickerJourney) -> Void = { _, journey in journey.discard() }
    public func makeForwardMessagesShareModalObserved(_ context: any AccountContextProtocol, _ messages: [Message], _ getMessages: @escaping ([MessageId], Bool) -> Signal<[Message], NoError>, analyticsContext: AnalyticsContext) -> ModalViewController {
        return makeForwardMessagesShareModalObserved(context, messages, getMessages, analyticsContext: analyticsContext, entry: nil)
    }
    public func makeForwardMessagesShareModalObserved(_ context: any AccountContextProtocol, _ messages: [Message], _ getMessages: @escaping ([MessageId], Bool) -> Signal<[Message], NoError>, analyticsContext: AnalyticsContext, entry: AnalyticsFlows.ChatForwardPicker.EntryPoint?) -> ModalViewController {
        return makeForwardMessagesShareModalObserved(context, messages, getMessages, analyticsContext: analyticsContext, entry: entry, journey: nil)
    }
    public func makeForwardMessagesShareModalObserved(_ context: any AccountContextProtocol, _ messages: [Message], _ getMessages: @escaping ([MessageId], Bool) -> Signal<[Message], NoError>, analyticsContext: AnalyticsContext, entry: AnalyticsFlows.ChatForwardPicker.EntryPoint?, journey: AnalyticsForwardPickerJourney?) -> ModalViewController {
        var origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        for message in messages {
            if message.containsSecretMedia { origin = Analytics.shared.unresolvedContext() }
            origin = origin.restricting(peerId: message.id.peerId)
        }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let lookup: ([MessageId], Bool) -> Signal<[Message], NoError> = { ids, album in
            var lookupOrigin = origin
            for id in ids { lookupOrigin = lookupOrigin.restricting(peerId: id.peerId) }
            let presentation = lookupOrigin.beginPresentation()
            defer { presentation.end() }
            return lookupOrigin.preservingPresentation(getMessages(ids, album) |> mapToSignal { messages in
                var resultOrigin = lookupOrigin
                for message in messages {
                    if message.containsSecretMedia { resultOrigin = Analytics.shared.unresolvedContext() }
                    resultOrigin = resultOrigin.restricting(peerId: message.id.peerId)
                }
                return resultOrigin.preservingPresentation(.single(messages))
            })
        }
        let controller: ModalViewController
        if journey == nil, let entry, let makeForwardMessagesShareModalWithSource {
            controller = makeForwardMessagesShareModalWithSource(context, messages, lookup, origin, entry)
        } else if let makeForwardMessagesShareModalWithContext {
            controller = makeForwardMessagesShareModalWithContext(context, messages, lookup, origin)
        } else {
            controller = makeForwardMessagesShareModal(context, messages, lookup)
        }
        var controllerOrigin = origin
        if !origin.isExcluded, let childContext = controller.analyticsContext {
            let childOrigin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: childContext)
            if childOrigin.isExcluded || childOrigin.scope == nil { controllerOrigin = childOrigin }
        }
        controller.analyticsContext = controllerOrigin
        if let journey {
            let lifetime = controllerOrigin.beginPresentation()
            defer { lifetime.end() }
            journey.restrict(to: controllerOrigin)
            attachForwardJourney(controller, journey)
        }
        return controller
    }
    public let makeReplyForwardShareModal: (any AccountContextProtocol, Message, EngineMessageReplySubject) -> ModalViewController
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void
    public let navigateToChatWithFocus: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?) -> Void
    public let navigateToChatWithFocusAdditional: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?, Bool) -> Void
    public let makeThreadPeerMediaController: (any AccountContextProtocol, PeerId, ThreadInfo?, Bool) -> ViewController
    public let makePeerMediaController: (any AccountContextProtocol, PeerId, Bool) -> ViewController
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId, ThreadInfo?, PeerExpiringStoryListContext?, PeerMediaCollectionMode?, Int32?) -> Void
    public var navigateToChatWithContext: ((NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?, Bool, AnalyticsContext) -> Void)?
    public func navigateToChatObserved(_ navigation: NavigationViewController?, _ context: any AccountContextProtocol, _ location: ChatLocation, _ focus: ChatFocusTarget?, _ action: ChatInitialAction?, _ additional: Bool, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: location.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let navigateToChatWithContext {
            navigateToChatWithContext(navigation, context, location, focus, action, additional, origin)
        } else if additional {
            navigateToChatWithFocusAdditional(navigation, context, location, focus, action, additional)
        } else {
            navigateToChatWithFocus(navigation, context, location, focus, action)
        }
    }
    public var pushPeerInfoWithContext: ((NavigationViewController, any AccountContextProtocol, PeerId, ThreadInfo?, PeerExpiringStoryListContext?, PeerMediaCollectionMode?, Int32?, AnalyticsContext) -> Void)?
    public func pushPeerInfoObserved(_ navigation: NavigationViewController, _ context: any AccountContextProtocol, _ peerId: PeerId, _ thread: ThreadInfo?, _ stories: PeerExpiringStoryListContext?, _ mode: PeerMediaCollectionMode?, _ album: Int32?, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let pushPeerInfoWithContext {
            pushPeerInfoWithContext(navigation, context, peerId, thread, stories, mode, album, origin)
        } else {
            pushPeerInfo(navigation, context, peerId, thread, stories, mode, album)
        }
    }
    public var makePeerMediaControllerWithContext: ((any AccountContextProtocol, PeerId, ThreadInfo?, Bool, AnalyticsContext) -> ViewController)?
    public func makePeerMediaControllerObserved(_ context: any AccountContextProtocol, _ peerId: PeerId, threadInfo: ThreadInfo? = nil, isBot: Bool, analyticsContext: AnalyticsContext) -> ViewController {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let controller: ViewController
        if let makePeerMediaControllerWithContext {
            controller = makePeerMediaControllerWithContext(context, peerId, threadInfo, isBot, origin)
        } else if let threadInfo {
            controller = makeThreadPeerMediaController(context, peerId, threadInfo, isBot)
        } else {
            controller = makePeerMediaController(context, peerId, isBot)
        }
        if let current = controller.analyticsContext, current.isExcluded || (!origin.isExcluded && current.scope?.isValid != true) {
            controller.analyticsContext = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: current)
        } else {
            controller.analyticsContext = origin
        }
        return controller
    }
    public let showSingleStory: (any AccountContextProtocol, StoryId, StoryInitialIndex?, (() -> Void)?) -> Void
    public var showSingleStoryWithContext: ((any AccountContextProtocol, StoryId, StoryInitialIndex?, (() -> Void)?, AnalyticsContext) -> Void)?
    public func showSingleStoryObserved(_ context: any AccountContextProtocol, _ storyId: StoryId, _ initialId: StoryInitialIndex?, _ emptyCallback: (() -> Void)?, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: storyId.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let showSingleStoryWithContext {
            showSingleStoryWithContext(context, storyId, initialId, emptyCallback, origin)
        } else {
            showSingleStory(context, storyId, initialId, emptyCallback)
        }
    }
    public var showStoriesWithContext: ((any AccountContextProtocol, Bool, StoryInitialIndex?, Bool, AnalyticsContext) -> Void)?
    public func showStoriesObserved(_ context: any AccountContextProtocol, _ isHidden: Bool, _ initialId: StoryInitialIndex?, _ singlePeer: Bool, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: initialId?.peerId ?? context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let showStoriesWithContext {
            showStoriesWithContext(context, isHidden, initialId, singlePeer, origin)
        } else {
            showStories(context, isHidden, initialId, singlePeer)
        }
    }
    public let showStories: (any AccountContextProtocol, Bool, StoryInitialIndex?, Bool) -> Void
    public let showInlineAudioPlayer: (APController, any AccountContextProtocol, TableView?) -> Void
    public let getAudioPlayer: (any AccountContextProtocol) -> APController?
    public let makeInlineAudioPlayerContextObject: (APController, any AccountContextProtocol, TableView?) -> Any
    public let makeSendAudioModal: (any AccountContextProtocol, ChatInteraction) -> ModalViewController
    public let makePreviewSender: ([URL], ChatInteraction, Bool, NSAttributedString?, AnalyticsContext) -> ModalViewController
    public var attachPreviewJourney: (ModalViewController, AnalyticsMediaJourney) -> Void = { _, journey in journey.discard() }
    public var bindPreviewSendValidation: (ModalViewController, @escaping () -> Bool) -> Bool = { _, _ in false }
    public let removeChatInteractively: (any AccountContextProtocol, PeerId, PeerId?) -> Signal<Bool, NoError>
    public let removeThreadInteractively: (any AccountContextProtocol, PeerId, Int64?, PeerId?) -> Signal<Bool, NoError>
    public let joinChannel: (any AccountContextProtocol, PeerId) -> Void
    public let requestOrJoinGroupCall: (any AccountContextProtocol, PeerId?, PeerId, CachedChannelData.ActiveCall?, GroupCallInfo?, String?, InternalGroupCallReference?) -> Signal<ChatGroupCallJoinResult, NoError>
    public let createVoiceChat: (any AccountContextProtocol, PeerId) -> Void
    public let createVoiceChatCanBeScheduled: (any AccountContextProtocol, PeerId, Bool) -> Void
    public let makeCodeSyntaxKey: (MessageId, NSRange, String, ChatInterfaceSyntaxTheme) -> CodeSyntaxKey
    public let highlightCodeSyntax: (String, String, ChatInterfaceSyntaxTheme) -> NSAttributedString
    public let makeDiceRollController: (any AccountContextProtocol, ChatInteraction) -> ModalViewController
    public let editForumTopic: (PeerId, MessageHistoryThreadData, Int64, any AccountContextProtocol) -> Void
    public let openForum: (PeerId, Bool, any AccountContextProtocol) -> Void
    public let createForumTopic: (PeerId, any AccountContextProtocol) -> Void
    public let getGroupCallPanelData: (any AccountContextProtocol, PeerId) -> Signal<GroupCallPanelData?, NoError>
    public let savedMessagesChatListItems: (PeerId, Account) -> Signal<[EngineChatList.Item]?, NoError>
    public let forumChatListItems: (PeerId, Account) -> Signal<[EngineChatList.Item]?, NoError>
    public var addForumMembers: ((any AccountContextProtocol, PeerId) -> Disposable)? = nil
    public var forumSidebarToggleImage: ((Bool) -> NSImage)? = nil
    public var makeForumSidebarRows: ((any AccountContextProtocol, @escaping (Int64?, MessageId?) -> Void) -> any ForumSidebarRowsContent)? = nil
    public var updateForumSidebarPane: ((any AccountContextProtocol, ViewController, ViewController?, Bool) -> Void)? = nil
    public let botForumChatListItems: (PeerId, Account) -> Signal<[EngineChatList.Item]?, NoError>
    public let createGroupDirectly: (any AccountContextProtocol, [PeerId]) -> Void
    public let openSpamBot: (any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void
    public let makeChatTitleBadgeNode: (any AccountContextProtocol, PeerId, @escaping () -> Void) -> ChatUIBadgeNode
    public let makeGroupBadgeNode: (any AccountContextProtocol, PeerGroupId, @escaping () -> Void) -> ChatUIBadgeNode
    public let generateLiveStreamBadge: (CGFloat, NSColor?) -> CGImage
    public let showAboutCocoonModal: (any AccountContextProtocol) -> Void
    public let executeInAppLink: (NSString, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void
    public let appIsLocked: () -> Signal<Bool, NoError>?
    public let appIsLockedValue: () -> Bool?
    public let makeChannelAdminModal: (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?) -> ModalViewController

    public init(clearNotifies: @escaping (PeerId, MessageId) -> Void,
                closeEntertainmentPopover: @escaping (any AccountContextProtocol) -> Void,
                updateEntertainment: @escaping (any AccountContextProtocol, ChatInteraction) -> Void,
                showMessageEffectsWindow: @escaping (any AccountContextProtocol, PeerId, [ChatUIEmojiSelectedItem], @escaping (StickerPackItem, NSRect?) -> Void, NSView & StickerFramesCollector) -> Void,
                makeForwardMessagesShareModal: @escaping (any AccountContextProtocol, [Message], @escaping ([MessageId], Bool) -> Signal<[Message], NoError>) -> ModalViewController,
                makeReplyForwardShareModal: @escaping (any AccountContextProtocol, Message, EngineMessageReplySubject) -> ModalViewController,
                navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void,
                navigateToChatWithFocus: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?) -> Void,
                navigateToChatWithFocusAdditional: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?, Bool) -> Void,
                makeThreadPeerMediaController: @escaping (any AccountContextProtocol, PeerId, ThreadInfo?, Bool) -> ViewController,
                makePeerMediaController: @escaping (any AccountContextProtocol, PeerId, Bool) -> ViewController,
                pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId, ThreadInfo?, PeerExpiringStoryListContext?, PeerMediaCollectionMode?, Int32?) -> Void,
                showSingleStory: @escaping (any AccountContextProtocol, StoryId, StoryInitialIndex?, (() -> Void)?) -> Void,
                showStories: @escaping (any AccountContextProtocol, Bool, StoryInitialIndex?, Bool) -> Void,
                showInlineAudioPlayer: @escaping (APController, any AccountContextProtocol, TableView?) -> Void,
                getAudioPlayer: @escaping (any AccountContextProtocol) -> APController?,
                makeInlineAudioPlayerContextObject: @escaping (APController, any AccountContextProtocol, TableView?) -> Any,
                makeSendAudioModal: @escaping (any AccountContextProtocol, ChatInteraction) -> ModalViewController,
                makePreviewSender: @escaping ([URL], ChatInteraction, Bool, NSAttributedString?, AnalyticsContext) -> ModalViewController,
                removeChatInteractively: @escaping (any AccountContextProtocol, PeerId, PeerId?) -> Signal<Bool, NoError>,
                removeThreadInteractively: @escaping (any AccountContextProtocol, PeerId, Int64?, PeerId?) -> Signal<Bool, NoError>,
                joinChannel: @escaping (any AccountContextProtocol, PeerId) -> Void,
                requestOrJoinGroupCall: @escaping (any AccountContextProtocol, PeerId?, PeerId, CachedChannelData.ActiveCall?, GroupCallInfo?, String?, InternalGroupCallReference?) -> Signal<ChatGroupCallJoinResult, NoError>,
                createVoiceChat: @escaping (any AccountContextProtocol, PeerId) -> Void,
                createVoiceChatCanBeScheduled: @escaping (any AccountContextProtocol, PeerId, Bool) -> Void,
                makeCodeSyntaxKey: @escaping (MessageId, NSRange, String, ChatInterfaceSyntaxTheme) -> CodeSyntaxKey,
                highlightCodeSyntax: @escaping (String, String, ChatInterfaceSyntaxTheme) -> NSAttributedString,
                makeDiceRollController: @escaping (any AccountContextProtocol, ChatInteraction) -> ModalViewController,
                editForumTopic: @escaping (PeerId, MessageHistoryThreadData, Int64, any AccountContextProtocol) -> Void,
                openForum: @escaping (PeerId, Bool, any AccountContextProtocol) -> Void,
                createForumTopic: @escaping (PeerId, any AccountContextProtocol) -> Void,
                getGroupCallPanelData: @escaping (any AccountContextProtocol, PeerId) -> Signal<GroupCallPanelData?, NoError>,
                savedMessagesChatListItems: @escaping (PeerId, Account) -> Signal<[EngineChatList.Item]?, NoError>,
                forumChatListItems: @escaping (PeerId, Account) -> Signal<[EngineChatList.Item]?, NoError>,
                botForumChatListItems: @escaping (PeerId, Account) -> Signal<[EngineChatList.Item]?, NoError>,
                createGroupDirectly: @escaping (any AccountContextProtocol, [PeerId]) -> Void,
                openSpamBot: @escaping (any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void,
                makeChatTitleBadgeNode: @escaping (any AccountContextProtocol, PeerId, @escaping () -> Void) -> ChatUIBadgeNode,
                makeGroupBadgeNode: @escaping (any AccountContextProtocol, PeerGroupId, @escaping () -> Void) -> ChatUIBadgeNode,
                generateLiveStreamBadge: @escaping (CGFloat, NSColor?) -> CGImage,
                showAboutCocoonModal: @escaping (any AccountContextProtocol) -> Void,
                executeInAppLink: @escaping (NSString, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void,
                appIsLocked: @escaping () -> Signal<Bool, NoError>?,
                appIsLockedValue: @escaping () -> Bool?,
                makeChannelAdminModal: @escaping (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?) -> ModalViewController) {
        self.clearNotifies = clearNotifies
        self.closeEntertainmentPopover = closeEntertainmentPopover
        self.updateEntertainment = updateEntertainment
        self.showMessageEffectsWindow = showMessageEffectsWindow
        self.makeForwardMessagesShareModal = makeForwardMessagesShareModal
        self.makeReplyForwardShareModal = makeReplyForwardShareModal
        self.navigateToChat = navigateToChat
        self.navigateToChatWithFocus = navigateToChatWithFocus
        self.navigateToChatWithFocusAdditional = navigateToChatWithFocusAdditional
        self.makeThreadPeerMediaController = makeThreadPeerMediaController
        self.makePeerMediaController = makePeerMediaController
        self.pushPeerInfo = pushPeerInfo
        self.showSingleStory = showSingleStory
        self.showStories = showStories
        self.showInlineAudioPlayer = showInlineAudioPlayer
        self.getAudioPlayer = getAudioPlayer
        self.makeInlineAudioPlayerContextObject = makeInlineAudioPlayerContextObject
        self.makeSendAudioModal = makeSendAudioModal
        self.makePreviewSender = makePreviewSender
        self.removeChatInteractively = removeChatInteractively
        self.removeThreadInteractively = removeThreadInteractively
        self.joinChannel = joinChannel
        self.requestOrJoinGroupCall = requestOrJoinGroupCall
        self.createVoiceChat = createVoiceChat
        self.createVoiceChatCanBeScheduled = createVoiceChatCanBeScheduled
        self.makeCodeSyntaxKey = makeCodeSyntaxKey
        self.highlightCodeSyntax = highlightCodeSyntax
        self.makeDiceRollController = makeDiceRollController
        self.editForumTopic = editForumTopic
        self.openForum = openForum
        self.createForumTopic = createForumTopic
        self.getGroupCallPanelData = getGroupCallPanelData
        self.savedMessagesChatListItems = savedMessagesChatListItems
        self.forumChatListItems = forumChatListItems
        self.botForumChatListItems = botForumChatListItems
        self.createGroupDirectly = createGroupDirectly
        self.openSpamBot = openSpamBot
        self.makeChatTitleBadgeNode = makeChatTitleBadgeNode
        self.makeGroupBadgeNode = makeGroupBadgeNode
        self.generateLiveStreamBadge = generateLiveStreamBadge
        self.showAboutCocoonModal = showAboutCocoonModal
        self.executeInAppLink = executeInAppLink
        self.appIsLocked = appIsLocked
        self.appIsLockedValue = appIsLockedValue
        self.makeChannelAdminModal = makeChannelAdminModal
    }

    private static var _shared: ChatUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatUIHooks.install must be called before the chat screen is used")
        return .placeholder
    }

    public static func install(_ hooks: ChatUIHooks) {
        assert(Thread.isMainThread, "ChatUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatUIHooks(clearNotifies: { _, _ in
    }, closeEntertainmentPopover: { _ in
    }, updateEntertainment: { _, _ in
    }, showMessageEffectsWindow: { _, _, _, _, _ in
    }, makeForwardMessagesShareModal: { _, _, _ in
        ModalViewController()
    }, makeReplyForwardShareModal: { _, _, _ in
        ModalViewController()
    }, navigateToChat: { _, _, _ in
    }, navigateToChatWithFocus: { _, _, _, _, _ in
    }, navigateToChatWithFocusAdditional: { _, _, _, _, _, _ in
    }, makeThreadPeerMediaController: { _, _, _, _ in
        ViewController()
    }, makePeerMediaController: { _, _, _ in
        ViewController()
    }, pushPeerInfo: { _, _, _, _, _, _, _ in
    }, showSingleStory: { _, _, _, _ in
    }, showStories: { _, _, _, _ in
    }, showInlineAudioPlayer: { _, _, _ in
    }, getAudioPlayer: { _ in
        nil
    }, makeInlineAudioPlayerContextObject: { controller, _, _ in
        controller
    }, makeSendAudioModal: { _, _ in
        ModalViewController()
    }, makePreviewSender: { _, _, _, _, _ in
        ModalViewController()
    }, removeChatInteractively: { _, _, _ in
        .single(false)
    }, removeThreadInteractively: { _, _, _, _ in
        .single(false)
    }, joinChannel: { _, _ in
    }, requestOrJoinGroupCall: { _, _, _, _, _, _, _ in
        .single(.fail)
    }, createVoiceChat: { _, _ in
    }, createVoiceChatCanBeScheduled: { _, _, _ in
    }, makeCodeSyntaxKey: { _, _, _, _ in
        preconditionFailure("ChatUIHooks not installed")
    }, highlightCodeSyntax: { code, _, _ in
        NSAttributedString(string: code)
    }, makeDiceRollController: { _, _ in
        ModalViewController()
    }, editForumTopic: { _, _, _, _ in
    }, openForum: { _, _, _ in
    }, createForumTopic: { _, _ in
    }, getGroupCallPanelData: { _, _ in
        .single(nil)
    }, savedMessagesChatListItems: { _, _ in
        .single(nil)
    }, forumChatListItems: { _, _ in
        .single(nil)
    }, botForumChatListItems: { _, _ in
        .single(nil)
    }, createGroupDirectly: { _, _ in
    }, openSpamBot: { _, _ in
    }, makeChatTitleBadgeNode: { _, _, _ in
        ChatUIPlaceholderBadgeNode()
    }, makeGroupBadgeNode: { _, _, _ in
        ChatUIPlaceholderBadgeNode()
    }, generateLiveStreamBadge: { _, _ in
        preconditionFailure("ChatUIHooks not installed")
    }, showAboutCocoonModal: { _ in
    }, executeInAppLink: { _, _, _ in
    }, appIsLocked: {
        return nil
    }, appIsLockedValue: {
        return nil
    }, makeChannelAdminModal: { _, _, _, _ in
        ModalViewController()
    })
}

private final class ChatUIPlaceholderBadgeNode: ChatUIBadgeNode {
    let view: View? = View()
    var xInset: CGFloat = 0
}
