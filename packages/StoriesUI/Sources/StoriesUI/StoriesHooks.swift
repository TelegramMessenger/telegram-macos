import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import ColorPalette
import ThemeSettings
import LocalAnimations
import ChatModeTypes

public enum StoriesInAppLink {
    case external(link: String, Bool)
}

public protocol StoryMediaParentView: AnyObject {
    var mainTable: TableView? { get }
}

public protocol StoryMediaParentController: AnyObject {
    associatedtype ParentView: StoryMediaParentView
    var genericView: ParentView { get }
    var currentMainTableView: ((TableView?, Bool, Bool)->Void)? { get }
    func changeState()
}

public struct StoriesHooks {
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let pushStoryMedia: (any AccountContextProtocol, PeerId, PeerStoryListContext, Bool, Bool) -> Void
    public let generateLiveStreamBadge: (CGFloat, NSColor?) -> CGImage
    public let showListStory: (any AccountContextProtocol, StoryListContext, PeerId, StoryInitialIndex?) -> Void
    public var showListStoryWithContext: ((any AccountContextProtocol, StoryListContext, PeerId, StoryInitialIndex?, AnalyticsContext) -> Void)?
    public func showListStoryObserved(_ context: any AccountContextProtocol, _ listContext: StoryListContext, _ peerId: PeerId, _ initialId: StoryInitialIndex?, analyticsContext: AnalyticsContext) {
        var origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        if let initialId { origin = origin.restricting(peerId: initialId.peerId) }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let showListStoryWithContext {
            showListStoryWithContext(context, listContext, peerId, initialId, origin)
        } else {
            showListStory(context, listContext, peerId, initialId)
        }
    }
    public let makeStoryMonthRowItem: (NSSize, AnyHashable, any AccountContextProtocol, Bool, PeerId, PeerReference, [StoryListContextState.Item], Set<StoryId>?, [Int32], Int, GeneralViewType, @escaping (StoryInitialIndex?) -> Void, @escaping (StoryId) -> Void, @escaping (StoryListContextState.Item) -> [ContextMenuItem], TelegramPresentationTheme) -> TableRowItem
    public let executeInApp: (StoriesInAppLink) -> Void
    public let showShareLink: (any AccountContextProtocol, String, Window) -> Void
    public let generateTheme: (ColorPalette, TelegramTheme?, Bool, CGFloat, ThemeWallpaper) -> TelegramPresentationTheme
    public let pushPeerInfoIfNeeded: (any AccountContextProtocol, PeerId) -> Void
    public let showShareStory: (any AccountContextProtocol, TelegramMediaStory, Bool, StoryId, @escaping () -> Void, TelegramPresentationTheme) -> Void
    public let findShareModal: (ModalViewController?) -> ModalViewController?
    public let makeInAppLink: (NSString, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any
    public let executeInAppLink: (Any, @escaping (Bool) -> Void) -> Void
    public let makeSliderContextMenuItem: (CGFloat, CGFloat, CGFloat, CGFloat?, LocalAnimatedSticker, LocalAnimatedSticker, ((CGFloat, Bool) -> Void)?) -> ContextMenuItem
    public let storiesBlockedPeersContext: (any AccountContextProtocol) -> BlockedPeersContext

    public init(navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void,
                pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                pushStoryMedia: @escaping (any AccountContextProtocol, PeerId, PeerStoryListContext, Bool, Bool) -> Void,
                generateLiveStreamBadge: @escaping (CGFloat, NSColor?) -> CGImage,
                showListStory: @escaping (any AccountContextProtocol, StoryListContext, PeerId, StoryInitialIndex?) -> Void,
                makeStoryMonthRowItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, Bool, PeerId, PeerReference, [StoryListContextState.Item], Set<StoryId>?, [Int32], Int, GeneralViewType, @escaping (StoryInitialIndex?) -> Void, @escaping (StoryId) -> Void, @escaping (StoryListContextState.Item) -> [ContextMenuItem], TelegramPresentationTheme) -> TableRowItem,
                executeInApp: @escaping (StoriesInAppLink) -> Void,
                showShareLink: @escaping (any AccountContextProtocol, String, Window) -> Void,
                generateTheme: @escaping (ColorPalette, TelegramTheme?, Bool, CGFloat, ThemeWallpaper) -> TelegramPresentationTheme,
                pushPeerInfoIfNeeded: @escaping (any AccountContextProtocol, PeerId) -> Void,
                showShareStory: @escaping (any AccountContextProtocol, TelegramMediaStory, Bool, StoryId, @escaping () -> Void, TelegramPresentationTheme) -> Void,
                findShareModal: @escaping (ModalViewController?) -> ModalViewController?,
                makeInAppLink: @escaping (NSString, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Any,
                executeInAppLink: @escaping (Any, @escaping (Bool) -> Void) -> Void,
                makeSliderContextMenuItem: @escaping (CGFloat, CGFloat, CGFloat, CGFloat?, LocalAnimatedSticker, LocalAnimatedSticker, ((CGFloat, Bool) -> Void)?) -> ContextMenuItem,
                storiesBlockedPeersContext: @escaping (any AccountContextProtocol) -> BlockedPeersContext) {
        self.navigateToChat = navigateToChat
        self.pushPeerInfo = pushPeerInfo
        self.pushStoryMedia = pushStoryMedia
        self.generateLiveStreamBadge = generateLiveStreamBadge
        self.showListStory = showListStory
        self.makeStoryMonthRowItem = makeStoryMonthRowItem
        self.executeInApp = executeInApp
        self.showShareLink = showShareLink
        self.generateTheme = generateTheme
        self.pushPeerInfoIfNeeded = pushPeerInfoIfNeeded
        self.showShareStory = showShareStory
        self.findShareModal = findShareModal
        self.makeInAppLink = makeInAppLink
        self.executeInAppLink = executeInAppLink
        self.makeSliderContextMenuItem = makeSliderContextMenuItem
        self.storiesBlockedPeersContext = storiesBlockedPeersContext
    }

    private static var _shared: StoriesHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: StoriesHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("StoriesHooks.install must be called before stories screens are used")
        return .placeholder
    }

    public static func install(_ hooks: StoriesHooks) {
        assert(Thread.isMainThread, "StoriesHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = StoriesHooks(navigateToChat: { _, _, _ in
    }, pushPeerInfo: { _, _, _ in
    }, pushStoryMedia: { _, _, _, _, _ in
    }, generateLiveStreamBadge: { _, _ in
        generateImage(NSMakeSize(1, 1), rotatedContext: { size, ctx in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        })!
    }, showListStory: { _, _, _, _ in
    }, makeStoryMonthRowItem: { initialSize, stableId, _, _, _, _, _, _, _, _, viewType, _, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId, viewType: viewType)
    }, executeInApp: { _ in
    }, showShareLink: { _, _, _ in
    }, generateTheme: { _, _, _, _, _ in
        theme
    }, pushPeerInfoIfNeeded: { _, _ in
    }, showShareStory: { _, _, _, _, _, _ in
    }, findShareModal: { _ in
        nil
    }, makeInAppLink: { link, _, _ in
        link
    }, executeInAppLink: { _, _ in
    }, makeSliderContextMenuItem: { _, _, _, _, _, _, _ in
        ContextMenuItem("")
    }, storiesBlockedPeersContext: { context in
        BlockedPeersContext(account: context.account, subject: .stories)
    })
}
