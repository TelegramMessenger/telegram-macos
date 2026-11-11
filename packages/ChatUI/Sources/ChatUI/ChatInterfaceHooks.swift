import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramLinks
import InputDataUI
import ChatHistoryModel
import TelegramCallsCore
import ChatModeTypes
import AppAnalytics

public protocol ChatInterfaceSyntaxTheme: AnyObject {
}

public protocol ChatInterfaceForwardAction: NavigationModalAction {
    var ids: [MessageId] { get }
}

public protocol ChatInterfaceInlineResultAction: NavigationModalAction {
    var payload: String { get }
}

public protocol ChatInterfaceController: ViewController {
    var chatInteraction: ChatInteraction { get }
    func inheritAnalyticsContext(_ inherited: AnalyticsContext)
}

public enum ChatInterfaceInAppLink {
    case external(link: String, Bool)
    case followResolvedName(link: String, username: String, postId: Int32?, forceProfile: Bool, context: any AccountContextProtocol, action: ChatInitialAction?, callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)
    case joinchat(link: String, String, context: any AccountContextProtocol, callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)
    case wallpaper(link: String, context: any AccountContextProtocol, preview: WallpaperPreview)
    case theme(link: String, context: any AccountContextProtocol, name: String)
    case instantView(link: String, webpage: TelegramMediaWebpage, anchor: String?)
    case other
}

public struct ChatInterfaceHooks {
    public let freezeAlert: (any AccountContextProtocol) -> Void
    public let resolveUsername: (String, any AccountContextProtocol) -> Signal<Peer?, NoError>
    public let makeGroupCallPanelData: (any AccountContextProtocol, PeerId, Bool, GroupCallSummary) -> Signal<GroupCallPanelData?, GetCurrentGroupCallError>
    public let setChatInterfaceTempState: (any AccountContextProtocol, ChatInterfaceTempState, PeerId) -> Void
    public let inputSource: (any AccountContextProtocol) -> InputSources
    public let executeUrl: (ChatInteraction, String) -> Void
    public let executeConfirmedUrl: (ChatInteraction, String) -> Void
    public let shareSwitchInlineQuery: (any AccountContextProtocol, ReplyMarkupButtonAction.PeerTypes, String) -> Void
    public let showLoginWidgetConfirmation: (any AccountContextProtocol, String, EnginePeer, MessageActionUrlAuthResult.ClientData?, MessageActionUrlAuthResult.Flags, MessageActionUrlSubject, [String]?, EnginePeer.Id?) -> Void
    public let makeNewPollController: (ChatInteraction, Bool?) -> InputDataModalController
    public let makeTopicIconFile: (String, Int32, Bool) -> TelegramMediaFile
    public let peerIsForum: (Peer) -> Bool
    public let urlPreviewInAppLink: (String, any AccountContextProtocol) -> ChatInterfaceInAppLink

    public init(freezeAlert: @escaping (any AccountContextProtocol) -> Void,
                resolveUsername: @escaping (String, any AccountContextProtocol) -> Signal<Peer?, NoError>,
                makeGroupCallPanelData: @escaping (any AccountContextProtocol, PeerId, Bool, GroupCallSummary) -> Signal<GroupCallPanelData?, GetCurrentGroupCallError>,
                setChatInterfaceTempState: @escaping (any AccountContextProtocol, ChatInterfaceTempState, PeerId) -> Void,
                inputSource: @escaping (any AccountContextProtocol) -> InputSources,
                executeUrl: @escaping (ChatInteraction, String) -> Void,
                executeConfirmedUrl: @escaping (ChatInteraction, String) -> Void,
                shareSwitchInlineQuery: @escaping (any AccountContextProtocol, ReplyMarkupButtonAction.PeerTypes, String) -> Void,
                showLoginWidgetConfirmation: @escaping (any AccountContextProtocol, String, EnginePeer, MessageActionUrlAuthResult.ClientData?, MessageActionUrlAuthResult.Flags, MessageActionUrlSubject, [String]?, EnginePeer.Id?) -> Void,
                makeNewPollController: @escaping (ChatInteraction, Bool?) -> InputDataModalController,
                makeTopicIconFile: @escaping (String, Int32, Bool) -> TelegramMediaFile,
                peerIsForum: @escaping (Peer) -> Bool,
                urlPreviewInAppLink: @escaping (String, any AccountContextProtocol) -> ChatInterfaceInAppLink) {
        self.freezeAlert = freezeAlert
        self.resolveUsername = resolveUsername
        self.makeGroupCallPanelData = makeGroupCallPanelData
        self.setChatInterfaceTempState = setChatInterfaceTempState
        self.inputSource = inputSource
        self.executeUrl = executeUrl
        self.executeConfirmedUrl = executeConfirmedUrl
        self.shareSwitchInlineQuery = shareSwitchInlineQuery
        self.showLoginWidgetConfirmation = showLoginWidgetConfirmation
        self.makeNewPollController = makeNewPollController
        self.makeTopicIconFile = makeTopicIconFile
        self.peerIsForum = peerIsForum
        self.urlPreviewInAppLink = urlPreviewInAppLink
    }

    private static var _shared: ChatInterfaceHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatInterfaceHooks {
        if let value = _shared {
            return value
        }
        preconditionFailure("ChatInterfaceHooks.install must be called before chat interface is used")
    }

    public static func install(_ hooks: ChatInterfaceHooks) {
        assert(Thread.isMainThread, "ChatInterfaceHooks.install must be called on the main thread")
        _shared = hooks
    }
}

public func installChatInterfaceHooks(_ hooks: ChatInterfaceHooks) {
    ChatInterfaceHooks.install(hooks)
}
