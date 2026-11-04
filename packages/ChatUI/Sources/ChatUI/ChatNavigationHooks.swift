import Cocoa
import ColorPalette
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramCore
import TelegramContext
import TelegramCallsCore
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import ImageCanvasUI
import ThemeSettings
import InputView
import InstantPageUI
import GeneralRows

public protocol ChatMediaEditControl: NSView {
}

public enum ChatDateSelectorMode {
    public struct Action {
        public var string: String
        public var callback: () -> Void
        public init(string: String, callback: @escaping () -> Void) {
            self.string = string
            self.callback = callback
        }
    }
    case schedule(PeerId)
    case date(title: String, doneTitle: String)
    case dateAction(title: String, done: (Date) -> String, action: Action)
}

public enum ChatGalleryAppearType: Equatable {
    case alone
    case history
    case profile(PeerId)
    case secret
    case recentDownloaded
    case messages([Message])
}

public enum ChatBrowserTab {
    case webapp(bot: EnginePeer, peerId: PeerId, buttonText: String, url: String?, payload: String?, threadId: Int64?, replyTo: MessageId?, fromMenu: Bool)
    case simple(bot: EnginePeer, url: String?, buttonText: String, source: RequestSimpleWebViewSource)
    case straight(bot: EnginePeer, peerId: PeerId, title: String, result: RequestWebViewResult)
    case instantView(url: String, webPage: TelegramMediaWebpage, anchor: String?)
    case game(url: String, peerId: PeerId, messageId: MessageId)
}

public enum ChatTodoSource {
    case create
    case edit(Message, taskId: Int32?)
    case addOption(Message)
}

public enum ChatPollSource {
    case new
    case addOption(messageId: MessageId, existingOptions: [String])
}

public enum ChatGroupCallJoinResult {
    case success(any GroupCallContextProtocol)
    case fail
    case samePeer(any GroupCallContextProtocol)
}

public protocol ChatBirthdayCalendar: ViewController {
    var date: Date { get }
    func hideYear()
}

public protocol ChatQuickReplyRow: AnyObject {
    var reply: ShortcutMessageList.Item { get }
}

public struct ChatNewContactState: Equatable {
    public let stateInited: Bool
    public let firstName: String
    public let lastName: String
    public let phone: String?
    public let representation: TelegramMediaImageRepresentation?
    public let peer: Peer?
    public let peerStatusSettings: PeerStatusSettings?
    public let addToException: Bool
    public let note: Updated_ChatTextInputState

    public init(stateInited: Bool = false, firstName: String = "", lastName: String = "", phone: String? = nil, representation: TelegramMediaImageRepresentation? = nil, peer: Peer? = nil, peerStatusSettings: PeerStatusSettings? = nil, addToException: Bool = false, note: Updated_ChatTextInputState = .init()) {
        self.stateInited = stateInited
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.representation = representation
        self.peer = peer
        self.peerStatusSettings = peerStatusSettings
        self.addToException = addToException
        self.note = note
    }

    public static func == (lhs: ChatNewContactState, rhs: ChatNewContactState) -> Bool {
        if let lhsPeer = lhs.peer, let rhsPeer = rhs.peer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.peer != nil) != (rhs.peer != nil) {
            return false
        }
        return lhs.stateInited == rhs.stateInited && lhs.firstName == rhs.firstName && lhs.lastName == rhs.lastName && lhs.phone == rhs.phone && lhs.representation == rhs.representation && lhs.peerStatusSettings == rhs.peerStatusSettings && lhs.addToException == rhs.addToException && lhs.note == rhs.note
    }

    public func withUpdatedFirstName(_ firstName: String) -> ChatNewContactState {
        return ChatNewContactState(stateInited: stateInited, firstName: firstName, lastName: lastName, phone: phone, representation: representation, peer: peer, peerStatusSettings: peerStatusSettings, addToException: addToException, note: note)
    }
    public func withUpdatedLastName(_ lastName: String) -> ChatNewContactState {
        return ChatNewContactState(stateInited: stateInited, firstName: firstName, lastName: lastName, phone: phone, representation: representation, peer: peer, peerStatusSettings: peerStatusSettings, addToException: addToException, note: note)
    }
    public func withUpdatedAddToException(_ addToException: Bool) -> ChatNewContactState {
        return ChatNewContactState(stateInited: stateInited, firstName: firstName, lastName: lastName, phone: phone, representation: representation, peer: peer, peerStatusSettings: peerStatusSettings, addToException: addToException, note: note)
    }
    public func withUpdatedNotes(_ note: Updated_ChatTextInputState) -> ChatNewContactState {
        return ChatNewContactState(stateInited: stateInited, firstName: firstName, lastName: lastName, phone: phone, representation: representation, peer: peer, peerStatusSettings: peerStatusSettings, addToException: addToException, note: note)
    }
    public func withUpdatedPeerView(_ peerView: PeerView) -> ChatNewContactState {
        let cachedData = peerView.cachedData as? CachedUserData
        let peer = peerView.peers[peerView.peerId] as? TelegramUser
        return ChatNewContactState(stateInited: true, firstName: stateInited ? firstName : peer?.firstName ?? firstName, lastName: stateInited ? lastName : peer?.lastName ?? lastName, phone: peer?.phone, representation: peer?.smallProfileImage, peer: peer, peerStatusSettings: cachedData?.peerStatusSettings, addToException: addToException, note: note)
    }
}

public struct ChatNavigationHooks {
    public var showAddTonBalance: (any AccountContextProtocol, Int64, Window) -> Void = { _, _, _ in }
    public var makeCalendarPopover: (any AccountContextProtocol, PeerId, Int64?, Date, @escaping (Date) -> Void) -> ViewController? = { _, _, _, _, _ in nil }
    public var makeBirthdayCalendar: (Window, Date) -> (any ChatBirthdayCalendar)? = { _, _ in nil }
    public var makeDateSelector: (any AccountContextProtocol, Date?, Int32?, ChatDateSelectorMode, @escaping (Date, Int32?) -> Void, TextViewLayout?) -> ModalViewController = { _, _, _, _, _, _ in ModalViewController() }
    public var showGigagroupLanding: (any AccountContextProtocol, PeerId, Window) -> Void = { _, _, _ in }
    public var pushGroupsInCommon: (any AccountContextProtocol, PeerId) -> Void = { _, _ in }
    public var pushGroupsInCommonWithContext: ((any AccountContextProtocol, PeerId) -> Void)?
    public func pushGroupsInCommonObserved(_ context: any AccountContextProtocol, _ peerId: PeerId) {
        if let pushGroupsInCommonWithContext {
            pushGroupsInCommonWithContext(context, peerId)
        } else {
            pushGroupsInCommon(context, peerId)
        }
    }
    public var showInactiveChannelsOnJoin: (any AccountContextProtocol) -> Void = { _ in }
    public var showInactiveChannelsOnJoinWithContext: ((any AccountContextProtocol) -> Void)?

    public func showInactiveChannelsOnJoinObserved(_ context: any AccountContextProtocol) {
        if let showInactiveChannelsOnJoinWithContext {
            showInactiveChannelsOnJoinWithContext(context)
        } else {
            showInactiveChannelsOnJoin(context)
        }
    }

    public var showFrozenAccount: (any AccountContextProtocol, Window) -> Void = { _, _ in }
    public var pushMessageStats: (any AccountContextProtocol, MessageId) -> Void = { _, _ in }
    public var pushMessageStatsWithContext: ((any AccountContextProtocol, MessageId) -> Void)?
    public func pushMessageStatsObserved(_ context: any AccountContextProtocol, _ message: Message) {
        if let pushMessageStatsWithContext {
            pushMessageStatsWithContext(context, message.id)
        } else {
            pushMessageStats(context, message.id)
        }
    }
    public var showVerifyAgeAlert: (any AccountContextProtocol, Window) -> Void = { _, _ in }
    public var chatExportMenuTitle: () -> String = { "" }
    public var showChatExport: (any AccountContextProtocol, Peer) -> Void = { _, _ in }
    public var canExportChat: (Peer, CachedPeerData?) -> Bool = { _, _ in false }
    public var makeRequestJoinMemberListController: (any AccountContextProtocol, PeerId, PeerInvitationImportersContext, @escaping () -> Void) -> ViewController = { _, _, _, _ in ViewController() }
    public var makeInviteLinksController: (any AccountContextProtocol, PeerId, Bool) -> ViewController = { _, _, _ in ViewController() }
    public var showPaymentsReceipt: (any AccountContextProtocol, MessageId, TelegramMediaInvoice, Window) -> Void = { _, _, _, _ in }
    public var showPaymentsCheckout: (any AccountContextProtocol, MessageId, TelegramMediaInvoice, Window) -> Void = { _, _, _, _ in }
    public var showPaymentsReceiptWithContext: ((any AccountContextProtocol, MessageId, TelegramMediaInvoice, Window) -> Void)?
    public var showPaymentsCheckoutWithContext: ((any AccountContextProtocol, MessageId, TelegramMediaInvoice, Window) -> Void)?

    public func showPaymentsReceiptObserved(_ context: any AccountContextProtocol, _ messageId: MessageId, _ invoice: TelegramMediaInvoice, _ window: Window) {
        if let showPaymentsReceiptWithContext {
            showPaymentsReceiptWithContext(context, messageId, invoice, window)
        } else {
            showPaymentsReceipt(context, messageId, invoice, window)
        }
    }

    public func showPaymentsCheckoutObserved(_ context: any AccountContextProtocol, _ messageId: MessageId, _ invoice: TelegramMediaInvoice, _ window: Window) {
        if let showPaymentsCheckoutWithContext {
            showPaymentsCheckoutWithContext(context, messageId, invoice, window)
        } else {
            showPaymentsCheckout(context, messageId, invoice, window)
        }
    }

    public var applyExternalProxy: (ProxyServerSettings, AccountManager<TelegramAccountManagerTypes>) -> Void = { _, _ in }
    public var makeProxyListController: (AccountManager<TelegramAccountManagerTypes>, Network, @escaping (ViewController) -> Void) -> ViewController = { _, _, _ in ViewController() }
    public var showWallpaperPreview: (any AccountContextProtocol, Wallpaper, MessageId, @escaping () -> Void, Window) -> Void = { _, _, _, _, _ in }
    public var showChatWallpaperSelector: (any AccountContextProtocol, Wallpaper, Peer, @escaping () -> Void, Window) -> Void = { _, _, _, _, _ in }
    public var pushBusinessQuickReplies: (any AccountContextProtocol) -> Void = { _ in }
    public var pushBusinessChatbot: (any AccountContextProtocol) -> Void = { _ in }
    public var makeQuickReplyRowItem: (NSSize, AnyHashable, ShortcutMessageList.Item, any AccountContextProtocol, String?) -> TableRowItem = { size, stableId, _, _, _ in GeneralRowItem(size, stableId: stableId) }
    public var showEditTagLabel: (any AccountContextProtocol, MessageReaction.Reaction, String?, Window) -> Void = { _, _, _, _ in }
    public var showEditTagLabelWithContext: ((any AccountContextProtocol, MessageReaction.Reaction, String?, Window) -> Void)?
    public func showEditTagLabelObserved(_ context: any AccountContextProtocol, _ reaction: MessageReaction.Reaction, _ label: String?, _ window: Window) {
        if let showEditTagLabelWithContext {
            showEditTagLabelWithContext(context, reaction, label, window)
        } else {
            showEditTagLabel(context, reaction, label, window)
        }
    }

    public var showUserTagInfo: (any AccountContextProtocol, String, String, String, AdminBadgeType, Window) -> Void = { _, _, _, _, _, _ in }
    public var showUserTagInfoWithContext: ((any AccountContextProtocol, String, String, String, AdminBadgeType, Window) -> Void)?
    public func showUserTagInfoObserved(_ context: any AccountContextProtocol, _ tag: String, _ authorName: String, _ groupName: String, _ badgeType: AdminBadgeType, _ window: Window) {
        if let showUserTagInfoWithContext {
            showUserTagInfoWithContext(context, tag, authorName, groupName, badgeType, window)
        } else {
            showUserTagInfo(context, tag, authorName, groupName, badgeType, window)
        }
    }

    public var showReportDetails: (any AccountContextProtocol, ReportReasonValue, @escaping (ReportReasonValue) -> Void, Window) -> Void = { _, _, _, _ in }
    public var reportSponsoredAd: (any AccountContextProtocol, Data, @escaping () -> Void, Window) -> Void = { _, _, _, _ in }
    public var reportMessages: (any AccountContextProtocol, [MessageId], String) -> Void = { _, _, _ in }
    public var selectChannelOwner: (any AccountContextProtocol, Peer, String, String) -> Signal<(PeerId, ChannelParticipant?)?, NoError> = { _, _, _, _ in .single(nil) }
    public var selectSpecificPeer: (any AccountContextProtocol, ReplyMarkupButtonRequestPeerType, MessageId, Int32, Int32) -> Void = { _, _, _, _, _ in }
    public var pushTwoStepVerificationUnlock: (any AccountContextProtocol, @escaping (ViewController, Bool, Bool) -> Void) -> Void = { _, _ in }
    public var updateAccountBirthday: (Date, any AccountContextProtocol) -> Void = { _, _ in }
    public var makeEditAccountInfoItem: (NSSize, AnyHashable, Account, ChatNewContactState, @escaping (String, String) -> Void) -> TableRowItem = { size, stableId, _, _, _ in GeneralRowItem(size, stableId: stableId) }
    public var makeSelectColorController: (any AccountContextProtocol, Peer) -> ViewController = { _, _ in ViewController() }
    public var showAutoremoveMessages: (any AccountContextProtocol, Peer, Window) -> Void = { _, _, _ in }
    public var generateChatThemeThumb: (ColorPalette, Bool, TableBackgroundMode) -> Signal<CGImage, NoError> = { _, _, _ in .complete() }
    public var showChatGallery: (any AccountContextProtocol, Message, InteractionContentViewProtocol?, ChatMediaLayoutParameters?, ChatGalleryAppearType, Bool, ChatMode?, ChatLocation?, Atomic<ChatLocationContextHolder?>, CachedPeerData?) -> Void = { _, _, _, _, _, _, _, _, _, _ in }
    public var showChatGalleryWithContext: ((any AccountContextProtocol, Message, InteractionContentViewProtocol?, ChatMediaLayoutParameters?, ChatGalleryAppearType, Bool, ChatMode?, ChatLocation?, Atomic<ChatLocationContextHolder?>, CachedPeerData?) -> Void)?
    public var showPhotosGallery: (any AccountContextProtocol, PeerId, AnyHashable, InteractionContentViewProtocol?, ChatMediaLayoutParameters?) -> Void = { _, _, _, _, _ in }
    public var showInstantViewGallery: (any AccountContextProtocol, [InstantPageMedia], Int, AnyHashable?, Message?, InteractionContentViewProtocol?, ChatMediaLayoutParameters?) -> Void = { _, _, _, _, _, _, _ in }
    public var showGalleryMedia: (any AccountContextProtocol, [Media], Message, Int, AnyHashable?, InteractionContentViewProtocol?, ChatMediaLayoutParameters?) -> Void = { _, _, _, _, _, _, _ in }
    public var roundToStandardQuality: (Int) -> Int = { $0 }
    public var startPhoneCall: (any AccountContextProtocol, PeerId, Bool) -> Disposable = { _, _, _ in EmptyDisposable }
    public var showJoinVoiceChatAlert: (any AccountContextProtocol, GroupCallPanelData, Peer, @escaping () -> Void, Window) -> Void = { _, _, _, _, _ in }
    public var selectGroupCallJoiner: (any AccountContextProtocol, PeerId, @escaping (PeerId, Date?, Bool) -> Void) -> Void = { _, _, _ in }
    public var applyGroupCallResult: (any SharedAccountContextProtocol, any GroupCallContextProtocol) -> Void = { _, _ in }
    public var showNewTodo: (ChatInteraction, ChatTodoSource, Window, (() -> NSView?)?) -> Void = { _, _, _, _ in }
    public var showNewPoll: (ChatInteraction, ChatPollSource, Window, (() -> NSView?)?) -> Void = { _, _, _, _ in }
    public var showPollResult: (any AccountContextProtocol, Message, Data?, Window) -> Void = { _, _, _, _ in }
    public var pushMessagePollStats: (any AccountContextProtocol, MessageId) -> Void = { _, _ in }
    public var showLocationPreview: (any AccountContextProtocol, TelegramMediaMap, Peer?, MessageId, Window) -> Void = { _, _, _, _, _ in }
    public var showLocationPicker: (ChatInteraction, Window, (() -> NSView?)?) -> Void = { _, _, _ in }
    public var showLocationSelector: (ChatInteraction, @escaping (TelegramMediaMap) -> Void, Window) -> Void = { _, _, _ in }
    public var showLocationSelectorWithContext: ((ChatInteraction, @escaping (TelegramMediaMap) -> Void, Window) -> Void)?

    public func showLocationSelectorObserved(_ interaction: ChatInteraction, _ select: @escaping (TelegramMediaMap) -> Void, _ window: Window) {
        let context = interaction.interactionContext
        let selected: (TelegramMediaMap) -> Void = { map in
            select(map)
        }
        if let showLocationSelectorWithContext {
            showLocationSelectorWithContext(interaction, selected, window)
        } else {
            showLocationSelector(interaction, selected, window)
        }
    }
    public var openPhotoEditor: (any AccountContextProtocol, TelegramMediaImage) -> Void = { _, _ in }
    public var editImage: (any AccountContextProtocol, URL, EditedImageData?) -> Signal<(URL, EditedImageData?), NoError> = { _, _, _ in .never() }
    public var editImageWithContext: ((any AccountContextProtocol, URL, EditedImageData?) -> Signal<(URL, EditedImageData?), NoError>)?
    public var editImageWithEvents: ((any AccountContextProtocol, URL, EditedImageData?, @escaping () -> Void, @escaping () -> Void) -> Signal<(URL, EditedImageData?), NoError>)?

    public func editImageObserved(_ context: any AccountContextProtocol, _ url: URL, _ data: EditedImageData?) -> Signal<(URL, EditedImageData?), NoError> {
        return editImageObserved(context, url, data, cancelled: {}, dismissed: {})
    }

    public func editImageObserved(_ context: any AccountContextProtocol, _ url: URL, _ data: EditedImageData?, cancelled: @escaping () -> Void, dismissed: @escaping () -> Void) -> Signal<(URL, EditedImageData?), NoError> {
        let resolved = Atomic(value: false)
        let finish: (Bool) -> Void = { wasCancelled in
            guard !resolved.swap(true) else { return }
            if wasCancelled { cancelled() } else { dismissed() }
        }
        let result = editImageWithEvents?(context, url, data, { finish(true) }, { finish(false) }) ?? editImageWithContext?(context, url, data) ?? editImage(context, url, data)
        return (result |> map { value in
            _ = resolved.swap(true)
            return value
        } |> afterCompleted {
            finish(false)
        })
    }

    public var setPeerPhoto: (any AccountContextProtocol, PeerId) -> Void = { _, _ in }
    public var openBrowserTab: (any AccountContextProtocol, ChatBrowserTab) -> Void = { _, _ in }
    public var installAttachMenuBot: (any AccountContextProtocol, Peer, @escaping (Bool) -> Void) -> Void = { _, _, _ in }
    public var openBrowserTabWithContext: ((any AccountContextProtocol, ChatBrowserTab) -> Void)?
    public var installAttachMenuBotWithContext: ((any AccountContextProtocol, Peer, @escaping (Bool) -> Void) -> Void)?

    public func openBrowserTabObserved(_ context: any AccountContextProtocol, _ tab: ChatBrowserTab) {
        if let openBrowserTabWithContext {
            openBrowserTabWithContext(context, tab)
        } else {
            openBrowserTab(context, tab)
        }
    }

    public func installAttachMenuBotObserved(_ context: any AccountContextProtocol, _ peer: Peer, completion: @escaping (Bool) -> Void) {
        let resolved = Atomic(value: false)
        let callback: (Bool) -> Void = { value in
            guard !resolved.swap(true) else { return }
            completion(value)
        }
        if let installAttachMenuBotWithContext {
            installAttachMenuBotWithContext(context, peer, callback)
        } else {
            installAttachMenuBot(context, peer, callback)
        }
    }

    public var openJoinChatBotWebView: (any AccountContextProtocol, PeerId, String?, Int64, PeerId?) -> Void = { _, _, _, _, _ in }
    public var openJoinChatBotWebViewWithContext: ((any AccountContextProtocol, PeerId, String?, Int64, PeerId?) -> Void)?

    public func openJoinChatBotWebViewObserved(_ context: any AccountContextProtocol, _ botId: PeerId, _ url: String?, _ queryId: Int64, _ joinedPeerId: PeerId?) {
        if let openJoinChatBotWebViewWithContext {
            openJoinChatBotWebViewWithContext(context, botId, url, queryId, joinedPeerId)
        } else {
            openJoinChatBotWebView(context, botId, url, queryId, joinedPeerId)
        }
    }

    public var makeInlineWebViewRowItem: (NSSize, String, String, Account, @escaping () -> Void) -> TableRowItem = { size, _, _, _, _ in GeneralRowItem(size) }
    #if DEBUG
    public var showFirstGramsModal: (any AccountContextProtocol, Window) -> Void = { _, _ in }
    #endif

    public init() {}

    private static var storage = ChatNavigationHooks()
    public private(set) static var isInstalled = false
    public static var shared: ChatNavigationHooks {
        return storage
    }
    public static func install(_ hooks: ChatNavigationHooks) {
        storage = hooks
        isInstalled = true
    }
}

func showChatGallery(context: any AccountContextProtocol, message: Message, _ delegate: InteractionContentViewProtocol? = nil, _ contentInteractions: ChatMediaLayoutParameters? = nil, type: ChatGalleryAppearType = .history, reversed: Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, contextHolder: Atomic<ChatLocationContextHolder?> = Atomic(value: nil), cachedPeerData: CachedPeerData? = nil) {
    if let show = ChatNavigationHooks.shared.showChatGalleryWithContext {
        show(context, message, delegate, contentInteractions, type, reversed, chatMode, chatLocation, contextHolder, cachedPeerData)
    } else {
        ChatNavigationHooks.shared.showChatGallery(context, message, delegate, contentInteractions, type, reversed, chatMode, chatLocation, contextHolder, cachedPeerData)
    }
}

func showPhotosGallery(context: any AccountContextProtocol, peerId: PeerId, firstStableId: AnyHashable, _ delegate: InteractionContentViewProtocol? = nil, _ contentInteractions: ChatMediaLayoutParameters? = nil) {
    ChatNavigationHooks.shared.showPhotosGallery(context, peerId, firstStableId, delegate, contentInteractions)
}

func showInstantViewGallery(context: any AccountContextProtocol, medias: [InstantPageMedia], firstIndex: Int, firstStableId: AnyHashable? = nil, parent: Message? = nil, _ delegate: InteractionContentViewProtocol? = nil, _ contentInteractions: ChatMediaLayoutParameters? = nil) {
    ChatNavigationHooks.shared.showInstantViewGallery(context, medias, firstIndex, firstStableId, parent, delegate, contentInteractions)
}

func showGalleryMedia(context: any AccountContextProtocol, medias: [Media], parent: Message, firstIndex: Int, firstStableId: AnyHashable? = nil, _ delegate: InteractionContentViewProtocol? = nil, _ contentInteractions: ChatMediaLayoutParameters? = nil) {
    ChatNavigationHooks.shared.showGalleryMedia(context, medias, parent, firstIndex, firstStableId, delegate, contentInteractions)
}

func chatDateSelector(context: any AccountContextProtocol, defaultDate: Date? = nil, repeatPeriod: Int32? = nil, mode: ChatDateSelectorMode, selectedAt: @escaping (Date, Int32?) -> Void, infoText: TextViewLayout? = nil) -> ModalViewController {
    let selectorMode: ChatDateSelectorMode
    if case let .dateAction(title, done, action) = mode {
        selectorMode = .dateAction(title: title, done: done, action: .init(string: action.string, callback: {
            action.callback()
        }))
    } else {
        selectorMode = mode
    }
    let controller = ChatNavigationHooks.shared.makeDateSelector(context, defaultDate, repeatPeriod, selectorMode, { date, repeatPeriod in
        selectedAt(date, repeatPeriod)
    }, infoText)
    return controller
}

func generateChatThemeThumb(palette: ColorPalette, bubbled: Bool, backgroundMode: TableBackgroundMode) -> Signal<CGImage, NoError> {
    return ChatNavigationHooks.shared.generateChatThemeThumb(palette, bubbled, backgroundMode)
}
