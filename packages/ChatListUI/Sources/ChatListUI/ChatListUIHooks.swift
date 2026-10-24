import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import LocalAnimations
import ChatModeTypes
import ChatHistoryModel
import FolderSharingUI
import ChatUI

public protocol ChatListForwardAction: NavigationModalAction {
    var messages: [Message] { get }
}

public protocol ChatListPeerInfoController: ViewController {
    var peerId: PeerId { get }
    var threadInfo: ThreadInfo? { get }
}

public protocol ChatListChatController: ViewController {
    var chatLocation: ChatLocation { get }
    var chatInteraction: ChatInteraction { get }
}

protocol ChatListControllerKind: ViewController {
    var mode: PeerListMode { get }
}

public struct ChatListCrashReportCard {
    public let id: String
    public let title: String
    public let info: String
    public let icon: CGImage?
    public let action: () -> Void
    public let dismiss: () -> Void

    public init(id: String, title: String, info: String, icon: CGImage?, action: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.info = info
        self.icon = icon
        self.action = action
        self.dismiss = dismiss
    }
}

public enum ChatListInAppLink {
    case followResolvedName(link: String, username: String, postId: Int32?, forceProfile: Bool, context: any AccountContextProtocol, action: ChatInitialAction?, callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)
    case other
}

public struct ChatListUIHooks {
    public let makeShareLinkModal: (any AccountContextProtocol, String) -> ModalViewController
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let makePremiumStatusController: (any AccountContextProtocol, @escaping (TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?) -> Void, TelegramUser) -> ViewController
    public let makeChatListFilterController: (any AccountContextProtocol, ChatListFilter) -> ViewController
    public let makeChatListFiltersListController: (any AccountContextProtocol) -> ViewController
    public let filterContextMenuItems: (ChatListFilter, Int?, Bool?, any AccountContextProtocol) -> [ContextMenuItem]
    public let makeAddContactModal: (any AccountContextProtocol) -> ModalViewController
    public let composeCreateGroup: ((any AccountContextProtocol)?) -> Void
    public let composeCreateSecretChat: ((any AccountContextProtocol)?) -> Void
    public let composeCreateChannel: ((any AccountContextProtocol)?) -> Void
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?, Bool, Bool, ViewControllerStyle?) -> Void
    public let makeChatController: (any AccountContextProtocol, ChatLocation, ChatInitialAction?) -> ViewController
    public let makeChatControllerWithMode: (any AccountContextProtocol, ChatLocation, ChatMode, Atomic<ChatLocationContextHolder?>?) -> ViewController
    public let makeChatAdditionController: (any AccountContextProtocol, ChatLocation) -> ViewController
    public let makeChatAdditionControllerWithFocus: (any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?) -> ViewController
    public let makeChatAdditionControllerWithMode: (any AccountContextProtocol, ChatLocation, ChatMode) -> ViewController
    public let makeSharedFolderClosureController: (any AccountContextProtocol, JoinCloudFolderMode) -> ModalViewController
    public let openPrivacySettings: (any AccountContextProtocol) -> Void
    public let appPasslock: () -> Signal<Bool, NoError>?
    public let storyListViewClass: () -> AnyClass
    public let makeCommunityListController: (any AccountContextProtocol, PeerId) -> ViewController
    public let externalContext: (PeerId, AccountRecordId) -> (any AccountContextProtocol)?
    public let updateGlobalPeer: (any AccountContextProtocol) -> Void
    public let showFastChatSettings: (any AccountContextProtocol) -> Void
    public let chatListCollapseOrExpandArchive: (any AccountContextProtocol) -> Void
    public let chatListToggleHideArchive: (any AccountContextProtocol) -> Void
    public let chatListSetAnimateGroupNextTransition: (any AccountContextProtocol, EngineChatList.Group) -> Void
    public let chatListHidePromoItem: (any AccountContextProtocol, PeerId) -> Void
    public let openPeerInNewWindow: (any AccountContextProtocol, PeerId) -> Void
    public let chatListFilterId: (ChatListFilter) -> Int32
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker, NSAttributedString, NSColor?, Bool) -> TableRowItem
    public let inApp: (String, any AccountContextProtocol, PeerId?, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> ChatListInAppLink
    public let makeForwardMessagesModal: (any AccountContextProtocol, [Message]) -> ModalViewController
    public let multigift: (any AccountContextProtocol, [PeerId], (() -> NSView?)?) -> Void
    public let makeTabBadgeNode: (any AccountContextProtocol) -> Node
    public let makeTabAllBadgeNode: (any AccountContextProtocol) -> Node
    public let makeSearchAdAboutController: (any AccountContextProtocol) -> ModalViewController
    public let navigateToChatWithCallback: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, ChatInitialAction?, Atomic<ChatLocationContextHolder?>?, Bool, ViewControllerStyle?, @escaping (ViewController) -> Void) -> Void
    public var navigateToChatWithContext: ((NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, ChatInitialAction?, Atomic<ChatLocationContextHolder?>?, Bool, ViewControllerStyle?, @escaping (ViewController) -> Void) -> Void)?

    public func navigateToChatObserved(_ navigation: NavigationViewController?, _ context: any AccountContextProtocol, _ chatLocation: ChatLocation, _ mode: ChatMode, _ focusTarget: ChatFocusTarget?, _ initialAction: ChatInitialAction?, _ holder: Atomic<ChatLocationContextHolder?>?, _ additional: Bool, _ style: ViewControllerStyle?, callback: @escaping (ViewController) -> Void) {
        let completed: (ViewController) -> Void = { controller in
            do {
                callback(controller)
            }
        }
        if let navigateToChatWithContext {
            navigateToChatWithContext(navigation, context, chatLocation, mode, focusTarget, initialAction, holder, additional, style, completed)
        } else {
            navigateToChatWithCallback(navigation, context, chatLocation, mode, focusTarget, initialAction, holder, additional, style, completed)
        }
    }

    public let mainEffectiveNavigation: (any AccountContextProtocol) -> NavigationViewController
    public let makeChatListController: (any AccountContextProtocol, Bool, PeerListMode) -> ViewController
    public let makeCreateForumTopicController: (any AccountContextProtocol, PeerId) -> ViewController
    public let makeEditForumTopicController: (any AccountContextProtocol, PeerId, MessageHistoryThreadData, Int64) -> ViewController
    public let formatPhoneNumber: (any AccountContextProtocol, String) -> String
    public let crashReportCard: (any AccountContextProtocol) -> Signal<ChatListCrashReportCard?, NoError>

    public init(makeShareLinkModal: @escaping (any AccountContextProtocol, String) -> ModalViewController,
                pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                makePremiumStatusController: @escaping (any AccountContextProtocol, @escaping (TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?) -> Void, TelegramUser) -> ViewController,
                makeChatListFilterController: @escaping (any AccountContextProtocol, ChatListFilter) -> ViewController,
                makeChatListFiltersListController: @escaping (any AccountContextProtocol) -> ViewController,
                filterContextMenuItems: @escaping (ChatListFilter, Int?, Bool?, any AccountContextProtocol) -> [ContextMenuItem],
                makeAddContactModal: @escaping (any AccountContextProtocol) -> ModalViewController,
                composeCreateGroup: @escaping ((any AccountContextProtocol)?) -> Void,
                composeCreateSecretChat: @escaping ((any AccountContextProtocol)?) -> Void,
                composeCreateChannel: @escaping ((any AccountContextProtocol)?) -> Void,
                navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?, Bool, Bool, ViewControllerStyle?) -> Void,
                makeChatController: @escaping (any AccountContextProtocol, ChatLocation, ChatInitialAction?) -> ViewController,
                makeChatControllerWithMode: @escaping (any AccountContextProtocol, ChatLocation, ChatMode, Atomic<ChatLocationContextHolder?>?) -> ViewController,
                makeChatAdditionController: @escaping (any AccountContextProtocol, ChatLocation) -> ViewController,
                makeChatAdditionControllerWithFocus: @escaping (any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?) -> ViewController,
                makeChatAdditionControllerWithMode: @escaping (any AccountContextProtocol, ChatLocation, ChatMode) -> ViewController,
                makeSharedFolderClosureController: @escaping (any AccountContextProtocol, JoinCloudFolderMode) -> ModalViewController,
                openPrivacySettings: @escaping (any AccountContextProtocol) -> Void,
                appPasslock: @escaping () -> Signal<Bool, NoError>?,
                storyListViewClass: @escaping () -> AnyClass,
                makeCommunityListController: @escaping (any AccountContextProtocol, PeerId) -> ViewController,
                externalContext: @escaping (PeerId, AccountRecordId) -> (any AccountContextProtocol)?,
                updateGlobalPeer: @escaping (any AccountContextProtocol) -> Void,
                showFastChatSettings: @escaping (any AccountContextProtocol) -> Void,
                chatListCollapseOrExpandArchive: @escaping (any AccountContextProtocol) -> Void,
                chatListToggleHideArchive: @escaping (any AccountContextProtocol) -> Void,
                chatListSetAnimateGroupNextTransition: @escaping (any AccountContextProtocol, EngineChatList.Group) -> Void,
                chatListHidePromoItem: @escaping (any AccountContextProtocol, PeerId) -> Void,
                openPeerInNewWindow: @escaping (any AccountContextProtocol, PeerId) -> Void,
                chatListFilterId: @escaping (ChatListFilter) -> Int32,
                makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker, NSAttributedString, NSColor?, Bool) -> TableRowItem,
                inApp: @escaping (String, any AccountContextProtocol, PeerId?, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> ChatListInAppLink,
                makeForwardMessagesModal: @escaping (any AccountContextProtocol, [Message]) -> ModalViewController,
                multigift: @escaping (any AccountContextProtocol, [PeerId], (() -> NSView?)?) -> Void,
                makeTabBadgeNode: @escaping (any AccountContextProtocol) -> Node,
                makeTabAllBadgeNode: @escaping (any AccountContextProtocol) -> Node,
                makeSearchAdAboutController: @escaping (any AccountContextProtocol) -> ModalViewController,
                navigateToChatWithCallback: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, ChatInitialAction?, Atomic<ChatLocationContextHolder?>?, Bool, ViewControllerStyle?, @escaping (ViewController) -> Void) -> Void,
                mainEffectiveNavigation: @escaping (any AccountContextProtocol) -> NavigationViewController,
                makeChatListController: @escaping (any AccountContextProtocol, Bool, PeerListMode) -> ViewController,
                makeCreateForumTopicController: @escaping (any AccountContextProtocol, PeerId) -> ViewController,
                makeEditForumTopicController: @escaping (any AccountContextProtocol, PeerId, MessageHistoryThreadData, Int64) -> ViewController,
                formatPhoneNumber: @escaping (any AccountContextProtocol, String) -> String,
                crashReportCard: @escaping (any AccountContextProtocol) -> Signal<ChatListCrashReportCard?, NoError>) {
        self.makeShareLinkModal = makeShareLinkModal
        self.pushPeerInfo = pushPeerInfo
        self.makePremiumStatusController = makePremiumStatusController
        self.makeChatListFilterController = makeChatListFilterController
        self.makeChatListFiltersListController = makeChatListFiltersListController
        self.filterContextMenuItems = filterContextMenuItems
        self.makeAddContactModal = makeAddContactModal
        self.composeCreateGroup = composeCreateGroup
        self.composeCreateSecretChat = composeCreateSecretChat
        self.composeCreateChannel = composeCreateChannel
        self.navigateToChat = navigateToChat
        self.makeChatController = makeChatController
        self.makeChatControllerWithMode = makeChatControllerWithMode
        self.makeChatAdditionController = makeChatAdditionController
        self.makeChatAdditionControllerWithFocus = makeChatAdditionControllerWithFocus
        self.makeChatAdditionControllerWithMode = makeChatAdditionControllerWithMode
        self.makeSharedFolderClosureController = makeSharedFolderClosureController
        self.openPrivacySettings = openPrivacySettings
        self.appPasslock = appPasslock
        self.storyListViewClass = storyListViewClass
        self.makeCommunityListController = makeCommunityListController
        self.externalContext = externalContext
        self.updateGlobalPeer = updateGlobalPeer
        self.showFastChatSettings = showFastChatSettings
        self.chatListCollapseOrExpandArchive = chatListCollapseOrExpandArchive
        self.chatListToggleHideArchive = chatListToggleHideArchive
        self.chatListSetAnimateGroupNextTransition = chatListSetAnimateGroupNextTransition
        self.chatListHidePromoItem = chatListHidePromoItem
        self.openPeerInNewWindow = openPeerInNewWindow
        self.chatListFilterId = chatListFilterId
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.inApp = inApp
        self.makeForwardMessagesModal = makeForwardMessagesModal
        self.multigift = multigift
        self.makeTabBadgeNode = makeTabBadgeNode
        self.makeTabAllBadgeNode = makeTabAllBadgeNode
        self.makeSearchAdAboutController = makeSearchAdAboutController
        self.navigateToChatWithCallback = navigateToChatWithCallback
        self.mainEffectiveNavigation = mainEffectiveNavigation
        self.makeChatListController = makeChatListController
        self.makeCreateForumTopicController = makeCreateForumTopicController
        self.makeEditForumTopicController = makeEditForumTopicController
        self.formatPhoneNumber = formatPhoneNumber
        self.crashReportCard = crashReportCard
    }

    private static var _shared: ChatListUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatListUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatListUIHooks.install must be called before the chat list is used")
        return .placeholder
    }

    public static func install(_ hooks: ChatListUIHooks) {
        assert(Thread.isMainThread, "ChatListUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatListUIHooks(makeShareLinkModal: { _, _ in
        ModalViewController()
    }, pushPeerInfo: { _, _, _ in
    }, makePremiumStatusController: { _, _, _ in
        ViewController()
    }, makeChatListFilterController: { _, _ in
        ViewController()
    }, makeChatListFiltersListController: { _ in
        ViewController()
    }, filterContextMenuItems: { _, _, _, _ in
        []
    }, makeAddContactModal: { _ in
        ModalViewController()
    }, composeCreateGroup: { _ in
    }, composeCreateSecretChat: { _ in
    }, composeCreateChannel: { _ in
    }, navigateToChat: { _, _, _, _, _, _, _, _ in
    }, makeChatController: { _, _, _ in
        ViewController()
    }, makeChatControllerWithMode: { _, _, _, _ in
        ViewController()
    }, makeChatAdditionController: { _, _ in
        ViewController()
    }, makeChatAdditionControllerWithFocus: { _, _, _, _ in
        ViewController()
    }, makeChatAdditionControllerWithMode: { _, _, _ in
        ViewController()
    }, makeSharedFolderClosureController: { _, _ in
        ModalViewController()
    }, openPrivacySettings: { _ in
    }, appPasslock: {
        nil
    }, storyListViewClass: {
        View.self
    }, makeCommunityListController: { _, _ in
        ViewController()
    }, externalContext: { _, _ in
        nil
    }, updateGlobalPeer: { _ in
    }, showFastChatSettings: { _ in
    }, chatListCollapseOrExpandArchive: { _ in
    }, chatListToggleHideArchive: { _ in
    }, chatListSetAnimateGroupNextTransition: { _, _ in
    }, chatListHidePromoItem: { _, _ in
    }, openPeerInNewWindow: { _, _ in
    }, chatListFilterId: { filter in
        filter.id
    }, makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _ in
        TableRowItem(initialSize, stableId: stableId)
    }, inApp: { _, _, _, _ in
        .other
    }, makeForwardMessagesModal: { _, _ in
        ModalViewController()
    }, multigift: { _, _, _ in
    }, makeTabBadgeNode: { _ in
        Node()
    }, makeTabAllBadgeNode: { _ in
        Node()
    }, makeSearchAdAboutController: { _ in
        ModalViewController()
    }, navigateToChatWithCallback: { _, _, _, _, _, _, _, _, _, _ in
    }, mainEffectiveNavigation: { context in
        context.bindings.rootNavigation()
    }, makeChatListController: { _, _, _ in
        ViewController()
    }, makeCreateForumTopicController: { _, _ in
        ViewController()
    }, makeEditForumTopicController: { _, _, _, _ in
        ViewController()
    }, formatPhoneNumber: { _, number in
        number
    }, crashReportCard: { _ in
        .single(nil)
    })
}
