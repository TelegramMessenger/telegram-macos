import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct MessageId: Equatable, ExpressibleByIntegerLiteral {
    let peerId: PeerId
    let id: Int32
    init(peerId: PeerId, namespace: Int32, id: Int32) { self.peerId = peerId; self.id = id }
    init(integerLiteral value: Int32) { self.init(peerId: 0, namespace: 0, id: value) }
}
enum Namespaces { enum Message { static let Cloud: Int32 = 0 } }
final class Scope { var valid = true }
final class AnalyticsContext {
    let isExcluded: Bool
    let owner: Int
    let scope: Scope?
    init(_ owner: Int = 1, excluded: Bool = false, scope: Scope? = Scope()) { self.owner = owner; isExcluded = excluded; self.scope = excluded ? nil : scope }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(self) }
    func restricting(peerId: PeerId) -> AnalyticsContext { AnalyticsContext(owner, excluded: isExcluded || peerId < 0, scope: scope) }
__SIGNAL__
}
final class AnalyticsPresentation {
    let excluded: Bool
    var active = true
    init(_ context: AnalyticsContext) { excluded = context.isExcluded || context.scope?.valid != true; if excluded { UI.exclusions += 1 } }
    func end() { guard active else { return }; active = false; if excluded { UI.exclusions -= 1 } }
    deinit { end() }
}
final class Analytics {
    static let shared = Analytics()
    func send(_ event: Int, scope: Scope? = nil) {
        guard UI.exclusions == 0, scope?.valid == true else { return }
        InviteUI.linkEvents += 1
        InviteUI.linkScopes.append(scope!)
    }
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(excluded: true) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext) -> AnalyticsContext {
        AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: engine.owner == inherited.owner ? inherited.scope : nil)
    }
}
protocol AccountContextProtocol: AnyObject { var engine: Engine { get }; var peerId: PeerId { get }; var window: Window { get } }
final class AccountContext: AccountContextProtocol { let peerId: PeerId = 1; let window = Window(); let engine: Engine; let bindings = Bindings(); let account = Account(); init(_ owner: Int = 1) { engine = Engine(owner) } }
final class Account { let postbox = Postbox() }
final class Postbox {
    var loaded: Signal<Peer, NoError> = .complete()
    var requested: [PeerId] = []
    func loadedPeerWithId(_ id: PeerId) -> Signal<Peer, NoError> { requested.append(id); UI.onPeerLoad?(); return loaded }
}
final class Bindings { let navigation = Navigation(); func rootNavigation() -> Navigation { navigation } }
final class Navigation {
    var controllers: [ChatController] = []
    var controller: ChatController? { controllers.last }
    func first(_ predicate: (ChatController) -> Bool) -> ChatController? { controllers.first(where: predicate) }
    func push(_ controller: ChatController) { UI.onPush?(controller); controllers.append(controller) }
}
struct ThreadMessage: Equatable { let peerId: PeerId; let threadId: Int64 }
struct ThreadInfo { let message: ThreadMessage; var contextHolder: Int? = nil }
enum ChatLocation: Equatable {
    case thread(ThreadMessage)
    var peerId: PeerId { switch self { case let .thread(message): return message.peerId } }
    var threadId: Int64? { switch self { case let .thread(message): return message.threadId } }
}
enum ReplyThreadMode { case comments(origin: MessageId), topic(origin: MessageId), replies(origin: MessageId) }
enum ChatMode { case thread(mode: ReplyThreadMode) }
struct FocusTarget { let messageId: MessageId?; var string: String? = nil }
enum Alignment { case CenterEmpty }
final class Interaction {
    var focused: [MessageId?] = []
    var actions: [ChatInitialAction] = []
    func invokeInitialAction(action: ChatInitialAction) { UI.onInitialAction?(); actions.append(action) }
    func focusMessageId(_ from: MessageId?, _ target: FocusTarget, _ alignment: Alignment) { UI.onFocus?(); focused.append(target.messageId) }
}
class ChatController {
    var chatLocation: ChatLocation
    let chatInteraction = Interaction()
    var analyticsContext: AnalyticsContext?
    var presentation: AnalyticsPresentation?
    init(_ location: ChatLocation) { chatLocation = location }
    func inheritAnalyticsContext(_ incoming: AnalyticsContext) {
        let context: AnalyticsContext
        if let current = analyticsContext, current.isExcluded || !incoming.isExcluded { context = current } else { context = incoming }
        let presentation = context.beginPresentation()
        analyticsContext = context
        self.presentation = presentation
    }
}
final class ChatAdditionController: ChatController {
    let mode: ChatMode
    let focusTarget: FocusTarget
    init(context: AccountContext, chatLocation: ChatLocation, mode: ChatMode, focusTarget: FocusTarget, initialAction: ChatInitialAction?, chatLocationContextHolder: Int?) {
        self.mode = mode; self.focusTarget = focusTarget; super.init(chatLocation); UI.onChatConstruction?()
    }
}
final class Engine { let payments = InvoicePayments(); let owner: Int; let messages = Messages(); let peers = Peers(); init(_ owner: Int) { self.owner = owner } }
struct EnginePeer { var id: PeerId { peer.id }; let peer: Peer; init(_ peer: Peer) { self.peer = peer }; init(peer: Peer) { self.peer = peer }; func _asPeer() -> Peer { peer } }
enum ResolvedPeer: Equatable {
    case progress, resolved(EnginePeer?)
    var result: EnginePeer? { if case let .resolved(value) = self { return value }; return nil }
    static func ==(lhs: ResolvedPeer, rhs: ResolvedPeer) -> Bool { if case .progress = lhs, case .progress = rhs { return true }; return false }
}
final class Peers {
    var inviteInfo: Signal<ExternalJoiningChatState, JoinLinkInfoError> = .complete()
    var inviteJoin: Signal<JoinLinkResult, JoinLinkError> = .complete()
    var infoHashes: [String] = []
    var joinHashes: [String] = []
    func joinLinkInformation(_ hash: String) -> Signal<ExternalJoiningChatState, JoinLinkInfoError> {
        infoHashes.append(hash); InviteUI.onInfo?(); return inviteInfo
    }
    func joinChatInteractively(with hash: String) -> Signal<JoinLinkResult, JoinLinkError> {
        joinHashes.append(hash); InviteUI.onJoin?(); return inviteJoin
    }

    var result: Signal<ResolvedPeer, NoError> = .complete()
    var names: [String] = []
    func resolvePeerByName(name: String, referrer: String?) -> Signal<ResolvedPeer, NoError> { names.append(name); return result }
}
final class Messages {
    var botApp: Signal<BotApp, MenuError> = .complete()
    var webView: Signal<RequestWebViewResult, RequestWebViewError> = .complete()
    var botAppRequests: [PeerId] = []
    var webRequests: [(PeerId, Bool, String?)] = []
    func getBotApp(botId: PeerId, shortName: String) -> Signal<BotApp, MenuError> { botAppRequests.append(botId); UI.onBotApp?(); return botApp }
    func requestAppWebView(peerId: PeerId, appReference: BotAppReference, payload: String?, themeParams: [String: Any]?, compact: Bool, fullscreen: Bool, allowWrite: Bool) -> Signal<RequestWebViewResult, RequestWebViewError> {
        webRequests.append((peerId, allowWrite, payload)); UI.onWebRequest?(); return webView
    }

    var result: Signal<LoadResult, LoadError> = .complete()
    var requested: [[MessageId]] = []
    var menu: Signal<Bool, MenuError> = .complete()
    var menuBotIds: [PeerId] = []
    func getAttachMenuBot(botId: PeerId) -> Signal<Bool, MenuError> { menuBotIds.append(botId); UI.onMenuLookup?(); return menu }
    func getMessagesLoadIfNecessary(_ ids: [MessageId]) -> Signal<LoadResult, LoadError> { requested.append(ids); UI.onLoad?(); return result }
}
enum LoadResult { case progress, result([Message]) }
enum LoadError: Error { case missing }
enum MenuError: Error { case generic }
struct Message { let threadId: Int64? }
class Peer {
    let id: PeerId
    var isForum = false
    var isChannel = false
    var isSupergroup = false
    var isBot = false
    var displayTitle: String { "synthetic" }
    var username: String?
    init(_ id: PeerId, forum: Bool = false) { self.id = id; isForum = forum }
}
final class TelegramChannel: Peer { var linkedMonoforumId: PeerId? }
enum ChatInitialAction { case closeAfter(Int32); case inputText, direct, start, attachBot, makeWebview; case openWebview(botPeer: EnginePeer, botApp: BotApp, result: RequestWebViewResult) }
final class Window {}
enum ConfirmResult { case basic }
struct Strings {
    let paymentsInvoiceAlreadyActive = "active", paymentsInvoiceNotExists = "missing", giftSendDisallowError = "disallowed", giftOptionsGiftBuyLimitReached = "limit"
    let requestJoinSent = "requested", groupUsersTooMuchError = "full", joinLinkFloodError = "flood", unknownError = "unknown", linkExpired = "expired"

    let botInfoLaunchInfoPrivacyUrl = "policy", botLaunchApp = "open", modalCancel = "cancel", botMoreAbout = "about"
    func botAllowSendMessages(_ title: String) -> String { "write" }
    func webAppFirstOpenTerms(_ url: String) -> String { "terms" }

    let inAppLinksConfirmOpenExternalHeader = "header"
    let inAppLinksConfirmOpenExternalOK = "open"
    let selectPeersTitleSelectChat = "select"
}
struct SelectPeerSettings: OptionSet {
    let rawValue: Int
    init(rawValue: Int = 0) { self.rawValue = rawValue }
    static let contacts = Self(rawValue: 1), remote = Self(rawValue: 2), bots = Self(rawValue: 4), groups = Self(rawValue: 8), channels = Self(rawValue: 16)
}
struct SelectChatsBehavior {
    let settings: SelectPeerSettings
    init(settings: SelectPeerSettings, excludePeerIds: [PeerId], limit: Int) { self.settings = settings }
}
func selectModalPeers(window: Window, context: AccountContext, title: String, limit: Int, behavior: SelectChatsBehavior) -> Signal<[PeerId], NoError> {
    UI.onPicker?(); UI.settings = behavior.settings; return UI.selection
}
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> { UI.onProgress?(); return signal }
func strings() -> Strings { Strings() }
func verifyAlert_button(for window: Window, header: String, information: String?, ok: String, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.onConfirmation?()
    UI.confirmed = successHandler; UI.cancelled = cancelHandler; UI.dismissed = onDeinit
}
extension String { var nsstring: NSString { self as NSString } }
final class NSWorkspace {
    static let shared = NSWorkspace()
    func open(_ url: URL) { UI.onSystemOpen?(); UI.openedURLs.append(url) }
}
func closeAllModals(window: Window) { UI.closes += 1; UI.onClose?() }
enum ForumUI {
    static func openTopic(_ threadId: Int64, peerId: PeerId, context: AccountContext, messageId: MessageId?, animated: Bool, addition: Bool, analyticsContext: AnalyticsContext?) -> Signal<Bool, NoError> {
        UI.topics.append(threadId); UI.topicMessages.append(messageId); UI.contexts.append(analyticsContext); UI.onTopic?()
        return UI.readiness
    }
    static func open(_ peerId: PeerId, addition: Bool, context: AccountContext, analyticsContext: AnalyticsContext?) {
        UI.forums.append(peerId); UI.contexts.append(analyticsContext); UI.child = analyticsContext?.beginPresentation(); UI.onForum?()
    }
}
struct BotApp {
    struct Flags: OptionSet {
        let rawValue: Int
        static let notActivated = Self(rawValue: 1), requiresWriteAccess = Self(rawValue: 2)
    }
    var flags: Flags = []
    let id: Int64 = 1
    let accessHash: Int64 = 2
    let title = "app"
}
enum BotAppReference { case id(id: Int64, accessHash: Int64) }
struct RequestWebViewResult { let serial: Int }
enum RequestWebViewError: Error { case generic }
let theme = 0
func generateWebAppThemeParams(_ theme: Int) -> [String: Any]? { nil }
struct BrowserTabData {
    enum Source { case inline(startParam: String) }
    enum Data { case mainapp(bot: EnginePeer, source: Source); case straight(bot: EnginePeer, peerId: PeerId, title: String, result: RequestWebViewResult) }
}
struct BrowserStateContext {
    static func get(_ context: AccountContext) -> BrowserStateContext { BrowserStateContext() }
    func open(tab: BrowserTabData.Data, analyticsContext: AnalyticsContext?) {
        UI.browserTabs.append(tab); UI.browserContexts.append(analyticsContext); UI.onBrowserOpen?()
    }
}
enum FastSettings {
    static func markWebAppAsConfirmed(_ id: PeerId) { UI.confirmedBots.append(id); UI.onConfirmedBot?() }
}
struct ModalAlertData {
    struct Option { let string: String; let isSelected: Bool; let mandatory: Bool }
    struct Header { let id: String; let value: (Int, Int, Int) -> AlertHeaderItem }
    enum Mode { case confirm(text: String, isThird: Bool) }
    let title: String?
    let info: String
    let description: String?
    let ok: String
    let options: [Option]
    let mode: Mode
    let header: Header
}
struct AlertHeaderItem {
    let callback: (Int) -> Void
    init(_ size: Int, stableId: Int, presentation: Int, context: AccountContext, peer: EnginePeer, info: String, callback: @escaping (Int) -> Void) { self.callback = callback }
}
struct ModalAlertResult { var selected: [Int: Bool] = [:] }
func showModalAlert(for window: Window, data: ModalAlertData, completion: @escaping (ModalAlertResult) -> Void, cancel: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.webAlerts += 1; UI.webOptions = data.options; UI.onConfirmation?()
    UI.webAccept = completion; UI.webCancel = cancel; UI.webDismiss = onDeinit; UI.webHeader = data.header.value(0, 0, 0)
}

enum ExternalJoiningChatState {
    struct Invite {
        struct Flags { var canRefulfillSubscription = false; var requestNeeded = false }
        var flags = Flags()
        var subscriptionPricing: Int?
    }
    case alreadyJoined(EnginePeer), invite(Invite), peek(EnginePeer, Int32), invalidHash
}
enum JoinLinkInfoError: Error { case generic, flood }
enum JoinLinkError: Error, CaseIterable { case tooMuchJoined, requestSent, tooMuchUsers, flood, generic }
struct JoinWebView { let botPeer: EnginePeer; let url: String?; let queryId: Int64; let peerId: PeerId? }
enum JoinLinkResult { case joined(EnginePeer?), webView(JoinWebView) }
final class InviteModal {
    var onDeinit: (() -> Void)?
    deinit { onDeinit?() }
    final class Content { var analyticsContext: AnalyticsContext? }
    let current = Content()
    var analyticsContext: AnalyticsContext?
}
enum PurchaseSource { case slug(String); case starsChatSubscription(hash: String) }
enum PurchaseType { case bot, botSubscription(TelegramMediaInvoice); case subscription(ExternalJoiningChatState.Invite) }
enum PurchaseStatus { var rawValue: String { switch self { case .paid: return "paid"; case .cancelled: return "cancelled"; case .failed: return "failed" } }; case paid(messageId: MessageId?, peerId: PeerId?), cancelled, failed }
func Star_PurschaseInApp(context: any AccountContextProtocol, invoice: TelegramMediaInvoice?, source: PurchaseSource, type: PurchaseType, analyticsContext: AnalyticsContext?, completion: @escaping (PurchaseStatus) -> Void = { _ in }) -> InviteModal {
    InvoiceUI.purchaseTypes.append(type); InviteUI.purchaseContext = analyticsContext; InviteUI.onPurchase?(); InviteUI.purchase = completion; return InviteModal()
}
func RequestJoinChatModalController(context: AccountContext, joinhash: String, invite: ExternalJoiningChatState, analyticsContext: AnalyticsContext?, interaction: @escaping (Peer) -> Void) -> InviteModal {
    InviteUI.routes.append("request"); InviteUI.dialogContext = analyticsContext; InviteUI.selected = interaction; InviteUI.onDialog?(); return InviteModal()
}
func JoinLinkPreviewModalController(_ context: AccountContext, hash: String, join: ExternalJoiningChatState, analyticsContext: AnalyticsContext?, interaction: @escaping (Peer) -> Void) -> InviteModal {
    InviteUI.routes.append("preview"); InviteUI.dialogContext = analyticsContext; InviteUI.selected = interaction; InviteUI.onDialog?(); return InviteModal()
}
func showModal(with controller: InviteModal, for window: Window) { InviteUI.modal = controller; InviteUI.onModal?() }
func showModalText(for window: Window, text: String) { InviteUI.texts.append(text); InviteUI.onText?() }
func delay(_ seconds: Double, closure: @escaping () -> Void) { InviteUI.delayed.append(closure) }
func openJoinChatBotWebView(context: AccountContext, botId: PeerId, url: String?, queryId: Int64, joinedPeerId: PeerId?, analyticsContext: AnalyticsContext?) {
    InviteUI.webDestinations.append(joinedPeerId); InviteUI.webContexts.append(analyticsContext); InviteUI.onWeb?()
}
enum Recovery { case join }
struct FeatureNavigationHooks {
    static let shared = FeatureNavigationHooks()
    func showInactiveChannelsObserved(_ context: AccountContext, _ source: Recovery, analyticsContext: AnalyticsContext) {
        InviteUI.recoveries.append(analyticsContext); InviteUI.onRecovery?()
    }
}
enum InviteUI {
    static var onInfo: (() -> Void)?, onJoin: (() -> Void)?, onDialog: (() -> Void)?, onPurchase: (() -> Void)?, onModal: (() -> Void)?, onText: (() -> Void)?, onWeb: (() -> Void)?, onRecovery: (() -> Void)?
    static var selected: ((Peer) -> Void)?
    static var purchase: ((PurchaseStatus) -> Void)?
    static var purchaseContext: AnalyticsContext?
    static var dialogContext: AnalyticsContext?
    static var modal: InviteModal?
    static var delayed: [() -> Void] = []
    static var routes: [String] = [], texts: [String] = []
    static var webDestinations: [PeerId?] = []
    static var webContexts: [AnalyticsContext?] = [], recoveries: [AnalyticsContext] = []
    static var linkEvents = 0
    static var linkScopes: [Scope] = []
    static func reset() {
        onInfo = nil; onJoin = nil; onDialog = nil; onPurchase = nil; onModal = nil; onText = nil; onWeb = nil; onRecovery = nil
        selected = nil; purchase = nil; purchaseContext = nil; dialogContext = nil; modal = nil; delayed = []; routes = []; texts = []
        webDestinations = []; webContexts = []; recoveries = []; linkEvents = 0; linkScopes = []
    }
}
struct StickerPackPreviewSource {}
struct ProxyServerSettings {}
struct inAppSecureIdRequest {}
struct WallpaperPreview {}
struct ParsedWalletUrl {}
struct ParsedSendGramsLink {}
struct TelegramMediaWebpage {}
struct InAppSettingsSection {}
enum CachedChannelData { struct ActiveCall {} }
__LINK_ENUM__
extension inAppLink {
    static var join: inAppLink { .joinchat(link: "synthetic", "synthetic", context: AccountContext(), callback: { _, _, _, _ in }) }
}
__LINK_KIND__
enum AnalyticsEvents {
    enum LinkOpenLinkKind { case miniApp, message, peer, invite, stickers, theme, proxy, external, other }
    static func linkOpen(linkKind: LinkOpenLinkKind) -> Int { 1 }
}
func executeAdmission(inapp: inAppLink, window: Window? = nil, analyticsContext: AnalyticsContext?, action: (AnalyticsContext?) -> Void) {
__ADMISSION__
    action(analyticsContext)
}

__LINK__
func externalSuccess(url: URL, analyticsContext: AnalyticsContext?, afterComplete: @escaping (Bool) -> Void) -> () -> Void {
__EXTERNAL_SUCCESS__
    return success
}
enum UI {
    static var browserTabs: [BrowserTabData.Data] = []
    static var browserContexts: [AnalyticsContext?] = []
    static var confirmedBots: [PeerId] = []
    static var webAlerts = 0
    static var webOptions: [ModalAlertData.Option] = []
    static var webAccept: ((ModalAlertResult) -> Void)?
    static var webCancel: (() -> Void)?
    static var webDismiss: (() -> Void)?
    static var webHeader: AlertHeaderItem?
    static var onBotApp: (() -> Void)?
    static var onWebRequest: (() -> Void)?
    static var onBrowserOpen: (() -> Void)?
    static var onConfirmedBot: (() -> Void)?
    static var exclusions = 0
    static var closes = 0
    static var topics: [Int64] = []
    static var topicMessages: [MessageId?] = []
    static var forums: [PeerId] = []
    static var contexts: [AnalyticsContext?] = []
    static var child: AnalyticsPresentation?
    static var readiness: Signal<Bool, NoError> = .single(true)
    static var onClose: (() -> Void)?
    static var onLoad: (() -> Void)?
    static var onTopic: (() -> Void)?
    static var onForum: (() -> Void)?
    static var onPush: ((ChatController) -> Void)?
    static var onFocus: (() -> Void)?
    static var onChatConstruction: (() -> Void)?
    static var onConfirmation: (() -> Void)?
    static var onSystemOpen: (() -> Void)?
    static var confirmed: ((ConfirmResult) -> Void)?
    static var cancelled: (() -> Void)?
    static var dismissed: (() -> Void)?
    static var openedURLs: [URL] = []
    static var selection: Signal<[PeerId], NoError> = .complete()
    static var settings: SelectPeerSettings = []
    static var onPicker: (() -> Void)?
    static var onPeerLoad: (() -> Void)?
    static var onMenuLookup: (() -> Void)?
    static var onProgress: (() -> Void)?
    static var onInitialAction: (() -> Void)?
    static func reset() {
        InvoiceUI.reset()
        InviteUI.reset()
        browserTabs = []; browserContexts = []; confirmedBots = []; webAlerts = 0; webOptions = []
        webAccept = nil; webCancel = nil; webDismiss = nil; webHeader = nil
        onBotApp = nil; onWebRequest = nil; onBrowserOpen = nil; onConfirmedBot = nil
        child = nil; contexts = []; topics = []; topicMessages = []; forums = []; closes = 0
        readiness = .single(true); onClose = nil; onLoad = nil; onTopic = nil; onForum = nil
        onPush = nil; onFocus = nil; onChatConstruction = nil; onConfirmation = nil; onSystemOpen = nil
        confirmed = nil; cancelled = nil; dismissed = nil; openedURLs = []
        selection = .complete(); settings = []; onPicker = nil; onPeerLoad = nil; onMenuLookup = nil; onProgress = nil; onInitialAction = nil
    }
}
final class LinkTests: XCTestCase {
    override func setUp() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    override func tearDown() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    func testDirectForumKeepsOriginThroughParentCloseAndChildLifetime() {
        var origin: InAppLinkOrigin? = InAppLinkOrigin(AnalyticsContext(excluded: true))
        UI.onClose = { origin = nil; XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onForum = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.contexts.last??.isExcluded == true) }
        openResolvedLinkPeer(Peer(2, forum: true), messageId: nil, action: nil, forceProfile: false, context: AccountContext(), window: Window(), origin: origin!) { _, _, _, _ in XCTFail("Forum bypasses chat callback") }
        XCTAssertEqual(UI.forums, [2]); XCTAssertEqual(UI.closes, 1); XCTAssertGreaterThan(UI.exclusions, 0)
        UI.reset(); XCTAssertEqual(UI.exclusions, 0)
    }
    func testDelayedMessageAndTopicFallbackKeepOriginAfterParentReleaseAndConsumeOnce() {
        let context = AccountContext()
        var messages: Subscriber<LoadResult, LoadError>?
        var ready: Subscriber<Bool, NoError>?
        context.engine.messages.result = Signal { messages = $0; return EmptyDisposable }
        UI.readiness = Signal { ready = $0; return EmptyDisposable }
        var origin: InAppLinkOrigin? = InAppLinkOrigin(AnalyticsContext(excluded: true))
        UI.onLoad = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onTopic = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.contexts.last??.isExcluded == true) }
        UI.onForum = { XCTAssertGreaterThan(UI.exclusions, 0) }
        openResolvedLinkPeer(Peer(2, forum: true), messageId: 5, action: nil, forceProfile: false, context: context, window: Window(), origin: origin!) { _, _, _, _ in XCTFail() }
        origin = nil
        XCTAssertGreaterThan(UI.exclusions, 0)
        messages?.putNext(.progress); XCTAssertTrue(UI.topics.isEmpty)
        messages?.putNext(.result([Message(threadId: 9)]))
        messages?.putNext(.result([Message(threadId: 10)]))
        XCTAssertEqual(UI.topics, [9]); XCTAssertTrue(UI.forums.isEmpty)
        ready?.putNext(false); ready?.putNext(false)
        XCTAssertEqual(UI.forums, [2]); XCTAssertEqual(context.engine.messages.requested, [[5]])
        messages = nil; ready = nil; UI.reset(); XCTAssertEqual(UI.exclusions, 0)
    }
    func testSuccessfulTopicDoesNotOpenForumFallback() {
        let context = AccountContext(); context.engine.messages.result = .single(.result([Message(threadId: 9)]))
        openResolvedLinkPeer(Peer(2, forum: true), messageId: 5, action: nil, forceProfile: false, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext())) { _, _, _, _ in XCTFail() }
        XCTAssertEqual(UI.topics, [9]); XCTAssertTrue(UI.forums.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testEmptyMissingThreadErrorAndEmptyCompletionDoNotInventNavigation() {
        let results: [Signal<LoadResult, LoadError>] = [.single(.result([])), .single(.result([Message(threadId: nil)])), .fail(.missing), .complete()]
        for result in results {
            let context = AccountContext(); context.engine.messages.result = result
            openResolvedLinkPeer(Peer(2, forum: true), messageId: 5, action: nil, forceProfile: false, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _, _ in XCTFail() }
            XCTAssertTrue(UI.topics.isEmpty); XCTAssertTrue(UI.forums.isEmpty); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testOrdinaryScopeIdentitySurvivesForumFallback() {
        let context = AccountContext(); let analytics = AnalyticsContext()
        context.engine.messages.result = .single(.result([Message(threadId: 9)])); UI.readiness = .single(false)
        openResolvedLinkPeer(Peer(2, forum: true), messageId: 5, action: nil, forceProfile: false, context: context, window: Window(), origin: InAppLinkOrigin(analytics)) { _, _, _, _ in XCTFail() }
        XCTAssertEqual(UI.contexts.count, 2)
        for origin in UI.contexts { XCTAssertTrue(origin?.scope === analytics.scope) }
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testForeignAccountAndSecretDestinationAreDenied() {
        for (owner, peer): (Int, PeerId) in [(2, 2), (1, -2)] {
            UI.onForum = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertNil(UI.contexts.last??.scope) }
            openResolvedLinkPeer(Peer(peer, forum: true), messageId: nil, action: nil, forceProfile: false, context: AccountContext(owner), window: Window(), origin: InAppLinkOrigin(AnalyticsContext())) { _, _, _, _ in XCTFail() }
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testRevocationBeforeMessageDeliveryKeepsLateTopicDenied() {
        let context = AccountContext(); let analytics = AnalyticsContext()
        var messages: Subscriber<LoadResult, LoadError>?
        context.engine.messages.result = Signal { messages = $0; return EmptyDisposable }
        openResolvedLinkPeer(Peer(2, forum: true), messageId: 5, action: nil, forceProfile: false, context: context, window: Window(), origin: InAppLinkOrigin(analytics)) { _, _, _, _ in XCTFail() }
        analytics.scope?.valid = false
        UI.onTopic = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertFalse(UI.contexts.last??.scope?.valid ?? true) }
        messages?.putNext(.result([Message(threadId: 9)])); messages = nil
        XCTAssertEqual(UI.topics, [9]); XCTAssertEqual(UI.exclusions, 0)
    }
    func testLinkedMonoforumDestinationRestrictsCallback() {
        let peer = TelegramChannel(2); peer.isChannel = true; peer.linkedMonoforumId = -3
        var called = false
        openResolvedLinkPeer(peer, messageId: 5, action: .direct, forceProfile: false, context: AccountContext(), window: Window(), origin: InAppLinkOrigin(AnalyticsContext())) { id, openChat, message, action in
            called = true; XCTAssertEqual(id, -3); XCTAssertTrue(openChat); XCTAssertEqual(message, 5); XCTAssertGreaterThan(UI.exclusions, 0)
            if case .direct = action {} else { XCTFail() }
        }
        XCTAssertTrue(called); XCTAssertEqual(UI.exclusions, 0)
    }
    func testProfileAndInputTextRoutingKeepExistingCallbackSemantics() {
        for force in [false, true] {
            var called = false
            openResolvedLinkPeer(Peer(2), messageId: 5, action: .inputText, forceProfile: force, context: AccountContext(), window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { id, chat, message, action in
                called = true; XCTAssertEqual(id, 2); XCTAssertEqual(chat, !force); XCTAssertEqual(message, 5); XCTAssertGreaterThan(UI.exclusions, 0)
                if force { XCTAssertNil(action) } else if case .inputText = action {} else { XCTFail() }
            }
            XCTAssertTrue(called); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testLegacyNilOriginDoesNotCreateNewGrantOrExclusion() {
        openResolvedLinkPeer(Peer(2, forum: true), messageId: nil, action: nil, forceProfile: false, context: AccountContext(), window: Window(), origin: InAppLinkOrigin(nil)) { _, _, _, _ in XCTFail() }
        XCTAssertEqual(UI.contexts.count, 1); XCTAssertNil(UI.contexts[0]); XCTAssertEqual(UI.exclusions, 0)
    }
}

extension LinkTests {
    func testCommentReuseBindsBeforeFocusAndRetainsOriginalExclusion() {
        let context = AccountContext()
        let thread = ThreadMessage(peerId: 3, threadId: 9)
        let chat = ChatController(.thread(thread)); context.bindings.navigation.controllers = [chat]
        UI.onFocus = { XCTAssertTrue(chat.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(UI.exclusions, 0) }
        openResolvedCommentLink(ThreadInfo(message: thread), peer: Peer(2), threadId: 7, commentId: 11, context: context, origin: InAppLinkOrigin(AnalyticsContext(excluded: true)))
        XCTAssertEqual(context.bindings.navigation.controllers.count, 1)
        XCTAssertEqual(chat.chatInteraction.focused, [MessageId(peerId: 3, namespace: 0, id: 11)])
        openResolvedCommentLink(ThreadInfo(message: thread), peer: Peer(2), threadId: 7, commentId: nil, context: context, origin: InAppLinkOrigin(AnalyticsContext()))
        XCTAssertTrue(chat.analyticsContext?.isExcluded == true)
    }
    func testSameThreadIdInAnotherPeerCreatesCorrectChatInsteadOfReusing() {
        let context = AccountContext()
        let previous = ChatController(.thread(ThreadMessage(peerId: 4, threadId: 9)))
        context.bindings.navigation.controllers = [previous]
        UI.onChatConstruction = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onPush = { XCTAssertTrue($0.analyticsContext?.isExcluded == true); XCTAssertEqual($0.chatLocation.peerId, 3) }
        openResolvedCommentLink(ThreadInfo(message: ThreadMessage(peerId: 3, threadId: 9)), peer: Peer(2), threadId: 7, commentId: 11, context: context, origin: InAppLinkOrigin(AnalyticsContext(excluded: true)))
        XCTAssertEqual(context.bindings.navigation.controllers.count, 2)
        XCTAssertTrue(previous.chatInteraction.focused.isEmpty)
        XCTAssertEqual((context.bindings.navigation.controller as? ChatAdditionController)?.focusTarget.messageId, MessageId(peerId: 3, namespace: 0, id: 11))
    }
    func testCommentModeAndActualDestinationRestrictionArePreserved() {
        for kind in 0..<3 {
            let context = AccountContext(); let peer = Peer(2); peer.isChannel = kind == 0; peer.isForum = kind == 1
            openResolvedCommentLink(ThreadInfo(message: ThreadMessage(peerId: -3, threadId: 9)), peer: peer, threadId: 7, commentId: nil, context: context, origin: InAppLinkOrigin(AnalyticsContext()))
            let chat = context.bindings.navigation.controller as! ChatAdditionController
            XCTAssertTrue(chat.analyticsContext?.isExcluded == true)
            switch chat.mode {
            case let .thread(mode):
                switch mode {
                case .comments: XCTAssertEqual(kind, 0)
                case .topic: XCTAssertEqual(kind, 1)
                case .replies: XCTAssertEqual(kind, 2)
                }
            }
            context.bindings.navigation.controllers.removeAll()
        }
    }
    func testDirectTopicCarriesCommentTargetAndOriginUntilReadinessResolves() {
        let context = AccountContext()
        var ready: Subscriber<Bool, NoError>?
        UI.readiness = Signal { ready = $0; return EmptyDisposable }
        UI.onTopic = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.contexts.last??.isExcluded == true) }
        openResolvedTopicLink(Peer(2), threadId: 7, commentId: 11, context: context, origin: InAppLinkOrigin(AnalyticsContext(excluded: true)))
        XCTAssertEqual(UI.topics, [7]); XCTAssertEqual(UI.topicMessages, [MessageId(peerId: 2, namespace: 0, id: 11)])
        XCTAssertGreaterThan(UI.exclusions, 0)
        ready?.putNext(true); ready?.putNext(false); ready = nil
        XCTAssertTrue(UI.forums.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testExternalConfirmationAllowsCloseBeforeCallbackAndConsumesReentrancy() {
        let analytics = AnalyticsContext(excluded: true)
        let url = URL(string: "https://example.invalid/path")!
        var results: [Bool] = []
        let success = externalSuccess(url: url, analyticsContext: analytics, afterComplete: { value in
            XCTAssertGreaterThan(UI.exclusions, 0)
            results.append(value)
            UI.cancelled?()
        })
        UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onSystemOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
        confirmExternalLink(window: Window(), information: "synthetic", origin: InAppLinkOrigin(analytics), success: success, cancel: { results.append(false) })
        XCTAssertGreaterThan(UI.exclusions, 0)
        UI.dismissed?(); UI.confirmed?(.basic); UI.confirmed?(.basic)
        drainMain()
        XCTAssertEqual(results, [true]); XCTAssertEqual(UI.openedURLs, [url]); XCTAssertEqual(UI.exclusions, 0)
    }
    func testExternalCancelAndUnknownCloseNeverOpenOrInventSuccess() {
        for cancel in [true, false] {
            let analytics = AnalyticsContext(excluded: true)
            var results: [Bool] = []
            let success = externalSuccess(url: URL(string: "https://example.invalid/path")!, analyticsContext: analytics, afterComplete: { results.append($0) })
            confirmExternalLink(window: Window(), information: "synthetic", origin: InAppLinkOrigin(analytics), success: success, cancel: { XCTAssertGreaterThan(UI.exclusions, 0); results.append(false) })
            if cancel { UI.cancelled?() }
            UI.dismissed?(); drainMain(); UI.confirmed?(.basic); UI.cancelled?()
            XCTAssertTrue(UI.openedURLs.isEmpty); XCTAssertEqual(results, cancel ? [false] : [])
            XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testExternalConfirmationRechecksRevokedGrantOnLateDelivery() {
        let analytics = AnalyticsContext()
        let success = externalSuccess(url: URL(string: "https://example.invalid/path")!, analyticsContext: analytics, afterComplete: { _ in XCTAssertGreaterThan(UI.exclusions, 0) })
        confirmExternalLink(window: Window(), information: "synthetic", origin: InAppLinkOrigin(analytics), success: success, cancel: {})
        XCTAssertEqual(UI.exclusions, 0)
        analytics.scope?.valid = false
        UI.onSystemOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.confirmed?(.basic)
        XCTAssertEqual(UI.openedURLs.count, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testExternalStoreSchemeRewriteStillUsesOneProtectedHandoff() {
        let analytics = AnalyticsContext(excluded: true)
        var results: [Bool] = []
        UI.onSystemOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
        externalSuccess(url: URL(string: "https://itunes.apple.com/path")!, analyticsContext: analytics, afterComplete: { results.append($0); XCTAssertGreaterThan(UI.exclusions, 0) })()
        XCTAssertEqual(UI.openedURLs.map(\.absoluteString), ["itms://itunes.apple.com/path"])
        XCTAssertEqual(results, [true]); XCTAssertEqual(UI.exclusions, 0)
    }
    private func drainMain() {
        let done = expectation(description: "main delivery")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}

extension LinkTests {
    func testAttachNamedTargetForcesChatAndKeepsOriginThroughDelayedResolution() {
        let context = AccountContext()
        var result: Subscriber<ResolvedPeer, NoError>?
        context.engine.peers.result = Signal { result = $0; return EmptyDisposable }
        var targets: [PeerId] = []
        executeAttachBotLink(Peer(2), botname: "synthetic", choose: ["target"], action: .attachBot, messageId: MessageId(peerId: 2, namespace: 0, id: 5), context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { peer, chat, message, _ in
            targets.append(peer); XCTAssertTrue(chat); XCTAssertNil(message); XCTAssertGreaterThan(UI.exclusions, 0)
        }
        XCTAssertGreaterThan(UI.exclusions, 0)
        result?.putNext(.progress); XCTAssertTrue(targets.isEmpty)
        result?.putNext(.resolved(EnginePeer(peer: Peer(3))))
        result?.putNext(.resolved(EnginePeer(peer: Peer(4))))
        XCTAssertEqual(targets, [3]); XCTAssertEqual(context.engine.peers.names, ["target"])
        XCTAssertTrue(context.engine.messages.menuBotIds.isEmpty)
        result = nil; XCTAssertEqual(UI.exclusions, 0)
    }
    func testAttachPickerUsesSelectedPeerAndDoesNotQueryItAsBot() {
        let context = AccountContext()
        var selected: Subscriber<[PeerId], NoError>?
        var loaded: Subscriber<Peer, NoError>?
        UI.selection = Signal { selected = $0; return EmptyDisposable }
        context.account.postbox.loaded = Signal { loaded = $0; return EmptyDisposable }
        UI.onPicker = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onPeerLoad = { XCTAssertGreaterThan(UI.exclusions, 0) }
        var targets: [PeerId] = []
        executeAttachBotLink(Peer(2), botname: "synthetic", choose: ["users", "bots", "groups", "channels"], action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { peer, chat, _, _ in
            targets.append(peer); XCTAssertTrue(chat); XCTAssertGreaterThan(UI.exclusions, 0)
        }
        XCTAssertEqual(UI.settings, [.contacts, .remote, .bots, .groups, .channels])
        selected?.putNext([3]); selected?.putNext([4]); selected = nil
        XCTAssertGreaterThan(UI.exclusions, 0)
        loaded?.putNext(Peer(3)); loaded?.putNext(Peer(4)); loaded = nil
        XCTAssertEqual(targets, [3]); XCTAssertEqual(context.account.postbox.requested, [3]); XCTAssertTrue(context.engine.messages.menuBotIds.isEmpty)
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testAttachSecretSelectionRestrictsBeforePeerLoadAndMismatchedResultCannotOpen() {
        let context = AccountContext()
        for returned: PeerId in [-3, 4] {
            UI.selection = .single([-3]); context.account.postbox.loaded = .single(Peer(returned))
            UI.onPeerLoad = { XCTAssertGreaterThan(UI.exclusions, 0) }
            var targets: [PeerId] = []
            executeAttachBotLink(Peer(2), botname: "synthetic", choose: ["users"], action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext())) { peer, _, _, _ in
                targets.append(peer); XCTAssertGreaterThan(UI.exclusions, 0)
            }
            XCTAssertEqual(targets, returned == -3 ? [-3] : []); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testAttachPickerCancelAndMissingNamedPeerDoNotInventAction() {
        let context = AccountContext()
        for selection: Signal<[PeerId], NoError> in [.single([]), .complete()] {
            UI.selection = selection
            executeAttachBotLink(Peer(2), botname: "synthetic", choose: ["users"], action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _, _ in XCTFail() }
            XCTAssertEqual(UI.exclusions, 0)
        }
        context.engine.peers.result = .single(.resolved(nil))
        executeAttachBotLink(Peer(2), botname: "synthetic", choose: ["target"], action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _, _ in XCTFail() }
        XCTAssertTrue(context.engine.messages.menuBotIds.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testAttachCurrentChatBindsBeforeActionAndConsumesMenuResultOnce() {
        let context = AccountContext(); let bot = Peer(2); bot.username = "synthetic"
        let chat = ChatController(.thread(ThreadMessage(peerId: 3, threadId: 9))); context.bindings.navigation.controllers = [chat]
        var menu: Subscriber<Bool, MenuError>?
        context.engine.messages.menu = Signal { menu = $0; return EmptyDisposable }
        UI.onInitialAction = { XCTAssertTrue(chat.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(UI.exclusions, 0) }
        executeAttachBotLink(bot, botname: "synthetic", choose: nil, action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _, _ in XCTFail() }
        menu?.putNext(true); menu?.putNext(true); menu?.putError(.generic)
        XCTAssertEqual(chat.chatInteraction.actions.count, 1); XCTAssertEqual(context.engine.messages.menuBotIds, [2])
        menu = nil
    }
    func testAttachMenuResultCannotUseDifferentChatOrChangedThread() {
        for changedThread in [false, true] {
            let context = AccountContext(); let chat = ChatController(.thread(ThreadMessage(peerId: 3, threadId: 9))); context.bindings.navigation.controllers = [chat]
            var menu: Subscriber<Bool, MenuError>?
            context.engine.messages.menu = Signal { menu = $0; return EmptyDisposable }
            executeAttachBotLink(Peer(2), botname: "synthetic", choose: nil, action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _, _ in XCTFail() }
            if changedThread { chat.chatLocation = .thread(ThreadMessage(peerId: 3, threadId: 10)) }
            else { context.bindings.navigation.controllers = [ChatController(.thread(ThreadMessage(peerId: 4, threadId: 9)))] }
            menu?.putNext(true); menu = nil
            XCTAssertTrue(chat.chatInteraction.actions.isEmpty); XCTAssertTrue(context.bindings.navigation.controller!.chatInteraction.actions.isEmpty)
            XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testAttachNoChatFallsBackToBotButDoesNotHijackNewChatDuringLookup() {
        for added in [false, true] {
            let context = AccountContext(); let bot = Peer(2); bot.username = "synthetic"
            var menu: Subscriber<Bool, MenuError>?
            context.engine.messages.menu = Signal { menu = $0; return EmptyDisposable }
            var targets: [PeerId] = []
            executeAttachBotLink(bot, botname: "synthetic", choose: nil, action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { peer, chat, _, _ in
                targets.append(peer); XCTAssertTrue(chat); XCTAssertGreaterThan(UI.exclusions, 0)
            }
            if added { context.bindings.navigation.controllers = [ChatController(.thread(ThreadMessage(peerId: 4, threadId: 9)))] }
            menu?.putNext(true); menu = nil
            XCTAssertEqual(targets, added ? [] : [2]); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testAttachMenuErrorRetainsExistingFallbackBehaviorUnderOrigin() {
        for matching in [false, true] {
            let context = AccountContext(); let bot = Peer(2); bot.username = matching ? "synthetic" : "different"
            let chat = ChatController(.thread(ThreadMessage(peerId: 3, threadId: 9))); context.bindings.navigation.controllers = [chat]
            context.engine.messages.menu = .fail(.generic)
            var targets: [PeerId] = []
            executeAttachBotLink(bot, botname: "synthetic", choose: nil, action: .attachBot, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { peer, _, _, _ in
                targets.append(peer); XCTAssertGreaterThan(UI.exclusions, 0)
            }
            XCTAssertEqual(targets, matching ? [] : [2]); XCTAssertEqual(chat.chatInteraction.actions.count, matching ? 1 : 0)
        }
    }
}
extension LinkTests {
    func testMainWebAppCarriesOriginalContextWithoutNamedAppLookup() {
        for owner in [1, 2] {
            let context = AccountContext(owner)
            UI.onBrowserOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
            executeWebAppLink(Peer(2), appname: "", command: "synthetic", messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
            XCTAssertTrue(context.engine.messages.botAppRequests.isEmpty)
            XCTAssertTrue(UI.browserContexts.last??.isExcluded == true)
            guard case let .mainapp(bot, .inline(parameter)) = UI.browserTabs.last else { return XCTFail() }
            XCTAssertEqual(bot.peer.id, 2); XCTAssertEqual(parameter, "synthetic")
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testNamedWebAppDelayedStagesCarryOriginAndDeliverOnce() {
        let context = AccountContext()
        var metadata: Subscriber<BotApp, MenuError>?
        var result: Subscriber<RequestWebViewResult, RequestWebViewError>?
        context.engine.messages.botApp = Signal { metadata = $0; return EmptyDisposable }
        context.engine.messages.webView = Signal { result = $0; return EmptyDisposable }
        UI.onBotApp = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onWebRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onBrowserOpen = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.browserContexts.last??.isExcluded == true) }
        var origin: InAppLinkOrigin? = InAppLinkOrigin(AnalyticsContext(excluded: true))
        executeWebAppLink(Peer(2), appname: "app", command: "synthetic", messageId: nil, context: context, window: Window(), origin: origin!) { _, _, _ in XCTFail() }
        origin = nil; XCTAssertGreaterThan(UI.exclusions, 0)
        metadata?.putNext(BotApp()); metadata?.putNext(BotApp()); metadata = nil
        XCTAssertEqual(context.engine.messages.webRequests.count, 1); XCTAssertEqual(UI.webAlerts, 0)
        result?.putNext(RequestWebViewResult(serial: 1)); result?.putNext(RequestWebViewResult(serial: 2)); result = nil
        XCTAssertEqual(UI.browserTabs.count, 1)
        guard case let .straight(_, peerId, _, value) = UI.browserTabs[0] else { return XCTFail() }
        XCTAssertEqual(peerId, 2); XCTAssertEqual(value.serial, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testNamedWebAppRestrictsSecretDestinationBeforeLookupAndBindsBeforeAction() {
        let context = AccountContext(); let chat = ChatController(.thread(ThreadMessage(peerId: -3, threadId: 4)))
        context.bindings.navigation.controllers = [chat]
        context.engine.messages.botApp = .single(BotApp())
        context.engine.messages.webView = .single(RequestWebViewResult(serial: 1))
        UI.onBotApp = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onWebRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onInitialAction = { XCTAssertTrue(chat.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(UI.exclusions, 0) }
        executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext())) { _, _, _ in XCTFail() }
        XCTAssertEqual(context.engine.messages.webRequests.first?.0, -3)
        XCTAssertEqual(chat.chatInteraction.actions.count, 1); XCTAssertTrue(UI.browserTabs.isEmpty)
    }
    func testNamedWebAppConsentCloseBeforeAcceptConsumesOnceAndPreservesWriteChoice() {
        for allowWrite in [false, true] {
            let context = AccountContext()
            context.engine.messages.botApp = .single(BotApp(flags: [.notActivated, .requiresWriteAccess]))
            context.engine.messages.webView = .single(RequestWebViewResult(serial: 1))
            UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onConfirmedBot = { XCTAssertGreaterThan(UI.exclusions, 0) }
            executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
            XCTAssertEqual(UI.webAlerts, 1); XCTAssertEqual(UI.webOptions.count, 1); XCTAssertTrue(UI.webOptions[0].mandatory)
            UI.webDismiss?(); UI.webAccept?(ModalAlertResult(selected: [0: allowWrite])); UI.webAccept?(ModalAlertResult(selected: [0: allowWrite]))
            drainWebMain()
            XCTAssertEqual(UI.confirmedBots, [2]); XCTAssertEqual(context.engine.messages.webRequests.count, 1)
            XCTAssertEqual(context.engine.messages.webRequests.first?.1, allowWrite); XCTAssertEqual(UI.browserTabs.count, 1)
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testNamedWebAppCancelAndUnknownClosureDoNotSendRequestOrMarkConsent() {
        for cancel in [false, true] {
            let context = AccountContext(); context.engine.messages.botApp = .single(BotApp(flags: [.notActivated]))
            executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
            if cancel { UI.webCancel?() }
            UI.webDismiss?(); drainWebMain(); UI.webAccept?(ModalAlertResult())
            XCTAssertTrue(context.engine.messages.webRequests.isEmpty); XCTAssertTrue(UI.confirmedBots.isEmpty); XCTAssertTrue(UI.browserTabs.isEmpty)
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testNamedWebAppMoreAboutConsumesDecisionWithoutStartingWebRequest() {
        let context = AccountContext(); context.engine.messages.botApp = .single(BotApp(flags: [.notActivated]))
        var targets: [PeerId] = []
        executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: 9, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { peer, messageId, action in
            XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertNil(messageId); XCTAssertNil(action); targets.append(peer.id)
        }
        UI.webHeader?.callback(0); UI.webHeader?.callback(0); UI.webAccept?(ModalAlertResult())
        XCTAssertEqual(targets, [2]); XCTAssertEqual(UI.closes, 1)
        XCTAssertTrue(context.engine.messages.webRequests.isEmpty); XCTAssertTrue(UI.confirmedBots.isEmpty)
    }
    func testNamedWebAppDoesNotDeliverToReplacementOrChangedThread() {
        for changedThread in [false, true] {
            let context = AccountContext(); let chat = ChatController(.thread(ThreadMessage(peerId: 3, threadId: 4)))
            context.bindings.navigation.controllers = [chat]
            context.engine.messages.botApp = .single(BotApp())
            var result: Subscriber<RequestWebViewResult, RequestWebViewError>?
            context.engine.messages.webView = Signal { result = $0; return EmptyDisposable }
            executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
            if changedThread { chat.chatLocation = .thread(ThreadMessage(peerId: 3, threadId: 5)) }
            else { context.bindings.navigation.controllers = [ChatController(.thread(ThreadMessage(peerId: 9, threadId: 4)))] }
            result?.putNext(RequestWebViewResult(serial: 1)); result = nil
            XCTAssertTrue(chat.chatInteraction.actions.isEmpty); XCTAssertTrue(context.bindings.navigation.controller!.chatInteraction.actions.isEmpty)
            XCTAssertTrue(UI.browserTabs.isEmpty); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testNamedWebAppDoesNotRequestAfterNewChatAppearsDuringLookupOrConsent() {
        for duringConsent in [false, true] {
            let context = AccountContext(); var metadata: Subscriber<BotApp, MenuError>?
            context.engine.messages.botApp = Signal { metadata = $0; return EmptyDisposable }
            executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
            if duringConsent { metadata?.putNext(BotApp(flags: [.notActivated])) }
            context.bindings.navigation.controllers = [ChatController(.thread(ThreadMessage(peerId: 9, threadId: 4)))]
            if duringConsent { UI.webAccept?(ModalAlertResult()) }
            else { metadata?.putNext(BotApp()) }
            metadata = nil
            XCTAssertTrue(context.engine.messages.webRequests.isEmpty); XCTAssertTrue(UI.confirmedBots.isEmpty); XCTAssertTrue(UI.browserTabs.isEmpty)
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testNamedWebAppLookupAndRequestErrorsFallbackOnceUnderOrigin() {
        for metadataError in [false, true] {
            let context = AccountContext()
            context.engine.messages.botApp = metadataError ? .fail(.generic) : .single(BotApp())
            context.engine.messages.webView = .fail(.generic)
            var targets: [PeerId] = []
            executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: 9, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { peer, messageId, _ in
                XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertEqual(messageId, 9); targets.append(peer.id)
            }
            XCTAssertEqual(targets, [2]); XCTAssertTrue(UI.browserTabs.isEmpty); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testNamedWebAppEmptyStagesDoNotInventFailureOrSuccess() {
        for emptyMetadata in [false, true] {
            let context = AccountContext()
            context.engine.messages.botApp = emptyMetadata ? .complete() : .single(BotApp())
            context.engine.messages.webView = .complete()
            executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
            XCTAssertTrue(UI.browserTabs.isEmpty); XCTAssertEqual(UI.webAlerts, 0); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testNamedWebAppRevokedAndForeignOriginsCannotBeReplacedWithFreshGrant() {
        for owner in [1, 2] {
            let context = AccountContext(owner); let original = AnalyticsContext()
            context.engine.messages.botApp = .single(BotApp())
            var result: Subscriber<RequestWebViewResult, RequestWebViewError>?
            context.engine.messages.webView = Signal { result = $0; return EmptyDisposable }
            executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(original)) { _, _, _ in XCTFail() }
            original.scope?.valid = false
            UI.onBrowserOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
            result?.putNext(RequestWebViewResult(serial: 1)); result = nil
            if owner == 1 { XCTAssertTrue(UI.browserContexts.last??.scope === original.scope) }
            else { XCTAssertNil(UI.browserContexts.last??.scope) }
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testLegacyWebAppOriginIsDeniedBeforeLookupConsentAndBrowserOpen() {
        for appname in ["", "app"] {
            let context = AccountContext()
            context.engine.messages.botApp = .single(BotApp(flags: [.notActivated]))
            context.engine.messages.webView = .single(RequestWebViewResult(serial: 1))
            UI.onBotApp = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onWebRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onBrowserOpen = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.browserContexts.last??.isExcluded == true) }
            executeWebAppLink(Peer(2), appname: appname, command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(nil)) { _, _, _ in XCTFail() }
            if !appname.isEmpty { UI.webAccept?(ModalAlertResult()) }
            XCTAssertEqual(UI.browserTabs.count, 1)
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testStaleWebAppHeaderCannotCloseModalsOrNavigateAfterChatReplacement() {
        let context = AccountContext()
        context.engine.messages.botApp = .single(BotApp(flags: [.notActivated]))
        executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
        context.bindings.navigation.controllers = [ChatController(.thread(ThreadMessage(peerId: 9, threadId: 4)))]
        UI.webHeader?.callback(0); UI.webAccept?(ModalAlertResult())
        XCTAssertEqual(UI.closes, 0); XCTAssertTrue(UI.confirmedBots.isEmpty); XCTAssertTrue(context.engine.messages.webRequests.isEmpty)
    }
    func testOrdinaryNamedWebAppPreservesOriginalGrantWithoutAddingExclusion() {
        let context = AccountContext(); let original = AnalyticsContext()
        context.engine.messages.botApp = .single(BotApp())
        context.engine.messages.webView = .single(RequestWebViewResult(serial: 1))
        UI.onBotApp = { XCTAssertEqual(UI.exclusions, 0) }
        UI.onWebRequest = { XCTAssertEqual(UI.exclusions, 0) }
        UI.onBrowserOpen = { XCTAssertEqual(UI.exclusions, 0) }
        executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(original)) { _, _, _ in XCTFail() }
        XCTAssertEqual(UI.browserTabs.count, 1)
        XCTAssertTrue(UI.browserContexts.last??.scope === original.scope)
        XCTAssertFalse(UI.browserContexts.last??.isExcluded ?? true)
        XCTAssertTrue(UI.browserContexts.last??.scope?.valid == true)
    }
    func testNamedWebAppRepeatedConsentCannotStartSecondPendingRequest() {
        let context = AccountContext()
        context.engine.messages.botApp = .single(BotApp(flags: [.notActivated]))
        var result: Subscriber<RequestWebViewResult, RequestWebViewError>?
        context.engine.messages.webView = Signal { result = $0; return EmptyDisposable }
        executeWebAppLink(Peer(2), appname: "app", command: nil, messageId: nil, context: context, window: Window(), origin: InAppLinkOrigin(AnalyticsContext(excluded: true))) { _, _, _ in XCTFail() }
        UI.webAccept?(ModalAlertResult()); UI.webAccept?(ModalAlertResult()); UI.webHeader?.callback(0)
        XCTAssertEqual(context.engine.messages.webRequests.count, 1); XCTAssertEqual(UI.confirmedBots, [2]); XCTAssertEqual(UI.closes, 0)
        XCTAssertGreaterThan(UI.exclusions, 0)
        result?.putNext(RequestWebViewResult(serial: 1)); result?.putNext(RequestWebViewResult(serial: 2)); result = nil
        XCTAssertEqual(UI.browserTabs.count, 1)
    }
    private func drainWebMain() {
        let done = expectation(description: "web decision delivery")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}

extension LinkTests {
    func testInviteAdmissionExcludesLegacySecretAndRevokedBeforeLinkEvent() {
        let revoked = AnalyticsContext(); revoked.scope?.valid = false
        for context in [nil, AnalyticsContext(excluded: true), revoked] as [AnalyticsContext?] {
            executeAdmission(inapp: .join, analyticsContext: context) { inherited in
                XCTAssertNotNil(inherited)
                XCTAssertGreaterThan(UI.exclusions, 0)
            }
        }
        XCTAssertEqual(InviteUI.linkEvents, 0)
        let ordinary = AnalyticsContext()
        executeAdmission(inapp: .join, analyticsContext: ordinary) { inherited in
            XCTAssertTrue(inherited?.scope === ordinary.scope); XCTAssertEqual(UI.exclusions, 0)
        }
        XCTAssertEqual(InviteUI.linkEvents, 1)
    }
    func testInviteMetadataPreservesPrivateContextThroughSubscriptionDeliveryAndDisposal() {
        let context = AccountContext()
        var metadata: Subscriber<ExternalJoiningChatState, JoinLinkInfoError>?
        var disposed = false
        context.engine.peers.inviteInfo = Signal { subscriber in
            XCTAssertGreaterThan(UI.exclusions, 0); metadata = subscriber
            return ActionDisposable { XCTAssertGreaterThan(UI.exclusions, 0); disposed = true }
        }
        InviteUI.onInfo = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onProgress = { XCTAssertGreaterThan(UI.exclusions, 0) }
        var destinations: [PeerId] = []
        executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(nil)) { id, _, _, _ in
            XCTAssertGreaterThan(UI.exclusions, 0); destinations.append(id)
        }
        XCTAssertEqual(context.engine.peers.infoHashes, ["synthetic"])
        XCTAssertGreaterThan(UI.exclusions, 0)
        metadata?.putNext(.alreadyJoined(EnginePeer(Peer(8))))
        metadata?.putNext(.alreadyJoined(EnginePeer(Peer(9))))
        metadata = nil
        XCTAssertEqual(destinations, [8]); XCTAssertTrue(disposed)
    }
    func testInviteDialogsRetainOriginalContextForLatePeerSelection() {
        for request in [false, true] {
            let context = AccountContext(); let origin = AnalyticsContext(excluded: true)
            context.engine.peers.inviteInfo = .single(.invite(.init(flags: .init(requestNeeded: request))))
            InviteUI.onDialog = { XCTAssertGreaterThan(UI.exclusions, 0) }
            var destinations: [PeerId] = []
            executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { id, _, _, _ in
                XCTAssertGreaterThan(UI.exclusions, 0); destinations.append(id)
            }
            XCTAssertEqual(InviteUI.routes.last, request ? "request" : "preview")
            XCTAssertTrue(InviteUI.dialogContext?.isExcluded == true)
            InviteUI.selected?(Peer(6))
            XCTAssertEqual(destinations, [6])
            InviteUI.reset()
        }
    }
    func testInviteDestinationsRestrictSecretForeignAndRevokedOrigins() {
        let revoked = AnalyticsContext(); revoked.scope?.valid = false
        for (origin, id) in [(AnalyticsContext(), PeerId(-5)), (AnalyticsContext(2), 5), (revoked, 5)] {
            let context = AccountContext()
            context.engine.peers.inviteInfo = .single(.alreadyJoined(EnginePeer(Peer(id))))
            var opened = false
            executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { _, _, _, _ in
                opened = true; XCTAssertGreaterThan(UI.exclusions, 0)
            }
            XCTAssertTrue(opened)
        }
    }
    func testInviteForumPreservesOrdinaryGrantAndPeekActionForDirectPeer() {
        let context = AccountContext(); let origin = AnalyticsContext()
        context.engine.peers.inviteInfo = .single(.alreadyJoined(EnginePeer(Peer(4, forum: true))))
        executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { _, _, _, _ in XCTFail() }
        XCTAssertEqual(UI.forums, [4]); XCTAssertTrue(UI.contexts.last??.scope === origin.scope)
        context.engine.peers.inviteInfo = .single(.peek(EnginePeer(Peer(5)), 42))
        var opened = false
        executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { id, _, _, action in
            XCTAssertEqual(id, 5); XCTAssertEqual(UI.exclusions, 0)
            guard case .closeAfter(42)? = action else { return XCTFail() }; opened = true
        }
        XCTAssertTrue(opened)
    }
    func testInviteMetadataEmptyInvalidAndErrorsNeverNavigate() {
        let context = AccountContext()
        InviteUI.onText = { XCTAssertGreaterThan(UI.exclusions, 0) }
        for signal: Signal<ExternalJoiningChatState, JoinLinkInfoError> in [.complete(), .single(.invalidHash), .fail(.generic), .fail(.flood)] {
            context.engine.peers.inviteInfo = signal
            executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(nil)) { _, _, _, _ in XCTFail() }
        }
        XCTAssertEqual(InviteUI.texts, ["expired", "unknown", "flood"])
        XCTAssertTrue(InviteUI.routes.isEmpty)
    }
    func testInviteRefillImportsHashAndNavigatesOnlyActualJoinedPeerOnce() {
        let context = AccountContext(); let origin = AnalyticsContext(excluded: true)
        context.engine.peers.inviteInfo = .single(.invite(.init(flags: .init(canRefulfillSubscription: true))))
        var join: Subscriber<JoinLinkResult, JoinLinkError>?
        var disposed = false
        context.engine.peers.inviteJoin = Signal { subscriber in
            XCTAssertGreaterThan(UI.exclusions, 0); join = subscriber
            return ActionDisposable { XCTAssertGreaterThan(UI.exclusions, 0); disposed = true }
        }
        InviteUI.onJoin = { XCTAssertGreaterThan(UI.exclusions, 0) }
        var destinations: [PeerId] = []
        executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { id, _, _, _ in
            XCTAssertGreaterThan(UI.exclusions, 0); destinations.append(id)
        }
        XCTAssertEqual(context.engine.peers.joinHashes, ["synthetic"])
        join?.putNext(.joined(EnginePeer(Peer(9)))); join?.putNext(.joined(EnginePeer(Peer(10)))); join = nil
        XCTAssertEqual(destinations, [9]); XCTAssertTrue(disposed)
        XCTAssertTrue(InviteUI.routes.isEmpty)
    }
    func testInviteRefillUnknownAndKnownWebDestinationsAreForwardedWithoutSelfSubstitution() {
        for destination in [nil, PeerId(7)] as [PeerId?] {
            let context = AccountContext(); let origin = AnalyticsContext()
            context.engine.peers.inviteInfo = .single(.invite(.init(flags: .init(canRefulfillSubscription: true))))
            context.engine.peers.inviteJoin = .single(.webView(.init(botPeer: EnginePeer(Peer(8)), url: nil, queryId: 12, peerId: destination)))
            executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { _, _, _, _ in XCTFail() }
            XCTAssertEqual(InviteUI.webDestinations.last!, destination)
            XCTAssertTrue(InviteUI.webContexts.last??.scope === origin.scope)
        }
    }
    func testInviteRefillErrorsUseScopedFeedbackAndObservedRecovery() {
        let context = AccountContext(); let origin = AnalyticsContext(excluded: true)
        context.engine.peers.inviteInfo = .single(.invite(.init(flags: .init(canRefulfillSubscription: true))))
        InviteUI.onText = { XCTAssertGreaterThan(UI.exclusions, 0) }
        InviteUI.onRecovery = { XCTAssertGreaterThan(UI.exclusions, 0) }
        for error in JoinLinkError.allCases {
            context.engine.peers.inviteJoin = .fail(error)
            executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { _, _, _, _ in XCTFail() }
        }
        XCTAssertEqual(InviteUI.recoveries.count, 1); XCTAssertTrue(InviteUI.recoveries[0].isExcluded)
        XCTAssertEqual(InviteUI.texts, ["requested", "full", "flood", "unknown"])
        XCTAssertTrue(InviteUI.webDestinations.isEmpty)
    }
    func testInviteRefillEmptyOrNilJoinedHasNoInventedDestination() {
        let context = AccountContext()
        context.engine.peers.inviteInfo = .single(.invite(.init(flags: .init(canRefulfillSubscription: true))))
        for signal: Signal<JoinLinkResult, JoinLinkError> in [.complete(), .single(.joined(nil))] {
            context.engine.peers.inviteJoin = signal
            executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(nil)) { _, _, _, _ in XCTFail() }
        }
        XCTAssertTrue(InviteUI.webDestinations.isEmpty); XCTAssertTrue(InviteUI.texts.isEmpty)
    }
    func testInvitePurchaseBindsControllersAndKeepsContextAfterModalCloses() {
        let context = AccountContext(); let origin = AnalyticsContext(excluded: true)
        context.engine.peers.inviteInfo = .single(.invite(.init(subscriptionPricing: 1)))
        InviteUI.onPurchase = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(InviteUI.purchaseContext?.isExcluded == true) }
        InviteUI.onModal = {
            XCTAssertTrue(InviteUI.modal?.analyticsContext?.isExcluded == true)
            XCTAssertTrue(InviteUI.modal?.current.analyticsContext === InviteUI.modal?.analyticsContext)
        }
        var destinations: [PeerId] = []
        executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { id, _, _, _ in
            XCTAssertGreaterThan(UI.exclusions, 0); destinations.append(id)
        }
        InviteUI.modal = nil
        InviteUI.purchase?(.failed); InviteUI.purchase?(.cancelled)
        XCTAssertTrue(InviteUI.delayed.isEmpty)
        InviteUI.purchase?(.paid(messageId: nil, peerId: 6)); InviteUI.purchase?(.paid(messageId: nil, peerId: 7))
        InviteUI.purchase = nil
        XCTAssertEqual(InviteUI.delayed.count, 1)
        let delayed = InviteUI.delayed; InviteUI.delayed = []
        delayed.forEach { $0() }
        XCTAssertEqual(destinations, [6])
    }
    func testInvitePurchaseNilPaidConsumesTerminalResultWithoutNavigation() {
        let context = AccountContext()
        context.engine.peers.inviteInfo = .single(.invite(.init(subscriptionPricing: 1)))
        executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(nil)) { _, _, _, _ in XCTFail() }
        InviteUI.purchase?(.paid(messageId: nil, peerId: nil)); InviteUI.purchase?(.paid(messageId: nil, peerId: 5))
        XCTAssertTrue(InviteUI.delayed.isEmpty)
    }
    func testInvitePurchaseRevocationAndSecretDestinationApplyToDelayedNavigation() {
        for secretDestination in [false, true] {
            let context = AccountContext(); let origin = AnalyticsContext()
            context.engine.peers.inviteInfo = .single(.invite(.init(subscriptionPricing: 1)))
            var opened = false
            executeInviteLink(hash: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin)) { _, _, _, _ in
                opened = true; XCTAssertGreaterThan(UI.exclusions, 0)
            }
            InviteUI.purchase?(.paid(messageId: nil, peerId: secretDestination ? -6 : 6))
            if !secretDestination { origin.scope?.valid = false }
            InviteUI.delayed.forEach { $0() }
            XCTAssertTrue(opened); InviteUI.reset()
        }
    }
}

let XTR = "XTR"
struct TelegramMediaInvoice { var currency = XTR; var subscriptionPeriod: Int? }
enum InvoiceError: Error, CaseIterable { case alreadyActive, generic, noPaymentNeeded, disallowedStarGift, starGiftResellTooEarly, starGiftUserLimit }
final class InvoicePayments {
    var invoices: Signal<TelegramMediaInvoice, InvoiceError> = .complete()
    var slugs: [String] = []
    func fetchBotPaymentInvoice(source: PurchaseSource) -> Signal<TelegramMediaInvoice, InvoiceError> {
        if case let .slug(slug) = source { slugs.append(slug) }; InvoiceUI.onFetch?(); return invoices
    }
}
typealias InputDataModalController = InviteModal
func PaymentsCheckoutController(context: any AccountContextProtocol, source: PurchaseSource, invoice: TelegramMediaInvoice, analyticsContext: AnalyticsContext, completion: @escaping (PurchaseStatus) -> Void = { _ in }) -> InviteModal {
    InvoiceUI.checkoutContexts.append(analyticsContext); InvoiceUI.cardCompletion = completion; InvoiceUI.onCheckout?(); return InviteModal()
}
struct BrowserHooks {
    static var shared = BrowserHooks(openInvoice: { _, _, _, _, _ in })
__INVOICE_HOOK__
}
func installInvoiceHooks() {
    var hooks = BrowserHooks(openInvoice: { context, invoice, slug, window, completion in
        presentBrowserInvoice(context: context, invoice: invoice, slug: slug, window: window, analyticsContext: Analytics.shared.unresolvedContext(), completion: completion)
    })
__INVOICE_INSTALL__
    BrowserHooks.shared = hooks
}
__INVOICE_BRIDGE__
__BROWSER_INVOICE__
struct JSON: ExpressibleByDictionaryLiteral {
    let string: String?
    init(dictionaryLiteral elements: (String, String)...) {
        string = String(data: try! JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: elements)), encoding: .utf8)
    }
}
final class WKWebView {}
final class WKNavigation {}
final class InvoicePage {
__INVOICE_NAVIGATION__
    let context: AccountContext
    var window: Window? = Window()
    let invoiceAction = BrowserInvoiceAction()
    let preparedShareAction = PreparedShareCancellation()
    var analyticsContext: AnalyticsContext?
    var events: [[String: String]] = []
    init(_ context: AccountContext, origin: AnalyticsContext?) { self.context = context; analyticsContext = origin }
    func receive(_ json: [String: Any]?) {
        guard let window else { return }
__INVOICE_INGRESS__
    }
    func sendEvent(name: String, data: String?) {
        XCTAssertEqual(name, "invoice_closed")
        if let data = data?.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] { events.append(value) }
    }
}
enum InvoiceUI {
    static var onFetch: (() -> Void)?, onCheckout: (() -> Void)?
    static var checkoutContexts: [AnalyticsContext] = [], purchaseTypes: [PurchaseType] = []
    static var cardCompletion: ((PurchaseStatus) -> Void)?
    static func reset() { onFetch = nil; onCheckout = nil; checkoutContexts = []; purchaseTypes = []; cardCompletion = nil; BrowserHooks.shared = BrowserHooks(openInvoice: { _, _, _, _, _ in }) }
}
extension LinkTests {
    func testInvoiceLinkCapturesContextBeforeFetchAndKeepsOriginalGrantAfterDelay() {
        let context = AccountContext(); let origin = AnalyticsContext()
        var invoice: Subscriber<TelegramMediaInvoice, InvoiceError>?
        context.engine.payments.invoices = Signal { invoice = $0; return EmptyDisposable }
        executeInvoiceLink(slug: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin))
        invoice?.putNext(.init(subscriptionPeriod: 30)); invoice?.putNext(.init()); invoice = nil
        XCTAssertTrue(InviteUI.purchaseContext?.scope === origin.scope); XCTAssertEqual(InvoiceUI.purchaseTypes.count, 1)
        guard case .botSubscription = InvoiceUI.purchaseTypes[0] else { return XCTFail() }
    }
    func testInvoiceLinkLegacySecretForeignAndRevokedOriginsRemainExcluded() {
        let revoked = AnalyticsContext(); revoked.scope?.valid = false
        for origin in [nil, AnalyticsContext(excluded: true), AnalyticsContext(2), revoked] as [AnalyticsContext?] {
            let context = AccountContext(); context.engine.payments.invoices = .single(.init(currency: "USD"))
            InvoiceUI.onFetch = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onProgress = InvoiceUI.onFetch; InvoiceUI.onCheckout = InvoiceUI.onFetch
            executeInvoiceLink(slug: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(origin))
            XCTAssertEqual(InvoiceUI.checkoutContexts.count, 1); UI.reset()
        }
    }
    func testInvoiceLinkErrorsAndEmptyCompletionDoNotCreateCheckout() {
        let context = AccountContext(); InviteUI.onText = { XCTAssertGreaterThan(UI.exclusions, 0) }
        for error in InvoiceError.allCases {
            context.engine.payments.invoices = .fail(error)
            executeInvoiceLink(slug: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(nil))
        }
        context.engine.payments.invoices = .complete()
        executeInvoiceLink(slug: "synthetic", context: context, window: Window(), origin: InAppLinkOrigin(nil))
        XCTAssertEqual(InviteUI.texts, ["active", "missing", "unknown", "disallowed", "unknown", "limit"])
        XCTAssertTrue(InvoiceUI.purchaseTypes.isEmpty); XCTAssertTrue(InvoiceUI.checkoutContexts.isEmpty)
    }
    func testBrowserInvoiceSendsOneFinalStatusAfterChildReleaseIncludingRetry() {
        installInvoiceHooks(); let context = AccountContext(); context.engine.payments.invoices = .single(.init())
        let page = InvoicePage(context, origin: AnalyticsContext(excluded: true))
        page.receive(["slug": "synthetic"]); page.receive(["slug": "another"])
        XCTAssertEqual(context.engine.payments.slugs, ["synthetic"])
        InviteUI.purchase?(.failed); XCTAssertTrue(page.events.isEmpty)
        InviteUI.purchase?(.paid(messageId: nil, peerId: nil)); InviteUI.purchase?(.cancelled)
        XCTAssertTrue(page.events.isEmpty)
        InviteUI.modal = nil
        XCTAssertEqual(page.events, [["slug": "synthetic", "status": "paid"]])
        InviteUI.purchase?(.failed); XCTAssertEqual(page.events.count, 1)
    }
    func testBrowserInvoiceDefaultDismissalAndFailureReportOnlyOnRelease() {
        for failed in [false, true] {
            installInvoiceHooks(); let context = AccountContext(); context.engine.payments.invoices = .single(.init(currency: "USD"))
            let page = InvoicePage(context, origin: nil)
            page.receive(["slug": "synthetic"])
            if failed { InvoiceUI.cardCompletion?(.failed) }
            XCTAssertTrue(page.events.isEmpty); InviteUI.modal = nil
            XCTAssertEqual(page.events.first?["status"], failed ? "failed" : "cancelled"); UI.reset()
        }
    }
    func testBrowserInvoiceResetCancelsMetadataAndAllowsNewDocumentWithoutOldResponse() {
        installInvoiceHooks(); let context = AccountContext(); let page = InvoicePage(context, origin: AnalyticsContext(excluded: true))
        var subscribers: [Subscriber<TelegramMediaInvoice, InvoiceError>] = []; var disposed = 0
        context.engine.payments.invoices = Signal { subscribers.append($0); return ActionDisposable { disposed += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        page.receive(["slug": "old"]); page.cancelPendingInvoices(); XCTAssertEqual(disposed, 1)
        page.receive(["slug": "new"]); subscribers[0].putNext(.init()); XCTAssertNil(InviteUI.modal)
        subscribers[1].putNext(.init()); subscribers = []; InviteUI.modal = nil
        XCTAssertEqual(page.events, [["slug": "new", "status": "cancelled"]])
    }
    func testBrowserInvoiceResetAfterPresentationPreventsReplyToReplacementDocument() {
        installInvoiceHooks(); let context = AccountContext(); context.engine.payments.invoices = .single(.init())
        let page = InvoicePage(context, origin: AnalyticsContext(excluded: true))
        page.receive(["slug": "old"]); page.webView(WKWebView(), didStartProvisionalNavigation: nil)
        InviteUI.purchase?(.paid(messageId: nil, peerId: nil)); InviteUI.modal = nil
        XCTAssertTrue(page.events.isEmpty)
        page.receive(["slug": "new"]); InviteUI.modal = nil
        XCTAssertEqual(page.events, [["slug": "new", "status": "cancelled"]])
    }
    func testBrowserInvoiceOwnerReleaseDisposesRequestAndChildOutlivesPagePrivately() {
        installInvoiceHooks(); let context = AccountContext(); var invoice: Subscriber<TelegramMediaInvoice, InvoiceError>?, disposed = false
        context.engine.payments.invoices = Signal { invoice = $0; return ActionDisposable { disposed = true } }
        var page: InvoicePage? = InvoicePage(context, origin: AnalyticsContext(excluded: true))
        page?.receive(["slug": "synthetic"]); page = nil; XCTAssertTrue(disposed)
        invoice?.putNext(.init()); invoice = nil; XCTAssertNil(InviteUI.modal)
        context.engine.payments.invoices = .single(.init())
        page = InvoicePage(context, origin: AnalyticsContext(excluded: true)); page?.receive(["slug": "synthetic"]); page = nil
        XCTAssertGreaterThan(UI.exclusions, 0); InviteUI.modal = nil
    }
    func testBrowserInvoiceErrorRepliesFailedOnceAndEmptyOrInvalidInputInventsNoStatus() {
        installInvoiceHooks(); let context = AccountContext(); let page = InvoicePage(context, origin: nil)
        InviteUI.onText = { XCTAssertGreaterThan(UI.exclusions, 0) }
        page.receive(nil); page.receive(["slug": 1]); page.receive(["slug": ""])
        XCTAssertTrue(context.engine.payments.slugs.isEmpty)
        context.engine.payments.invoices = .fail(.generic); page.receive(["slug": "failed"])
        context.engine.payments.invoices = .complete(); page.receive(["slug": "empty"])
        XCTAssertEqual(page.events, [["slug": "failed", "status": "failed"]]); XCTAssertNil(InviteUI.modal)
    }
    func testBrowserInvoiceLegacyFallbackRejectsInvalidAndDuplicateStatusesUnderOriginalContext() {
        var callback: ((String) -> Void)?
        BrowserHooks.shared = BrowserHooks(openInvoice: { _, _, _, _, completion in callback = completion; XCTAssertGreaterThan(UI.exclusions, 0) })
        let context = AccountContext(); context.engine.payments.invoices = .single(.init())
        let page = InvoicePage(context, origin: AnalyticsContext(excluded: true))
        page.receive(["slug": "synthetic"])
        callback?("unrecognized"); XCTAssertTrue(page.events.isEmpty)
        callback?("paid"); callback?("failed"); callback = nil
        XCTAssertEqual(page.events, [["slug": "synthetic", "status": "paid"]])
    }
    func testBrowserInvoiceOrdinaryGrantIsForwardedAndRevocationAppliesBeforeCheckout() {
        installInvoiceHooks(); let context = AccountContext(); let origin = AnalyticsContext()
        var invoice: Subscriber<TelegramMediaInvoice, InvoiceError>?
        context.engine.payments.invoices = Signal { invoice = $0; return EmptyDisposable }
        let page = InvoicePage(context, origin: origin); page.receive(["slug": "synthetic"])
        origin.scope?.valid = false; InviteUI.onPurchase = { XCTAssertGreaterThan(UI.exclusions, 0) }
        invoice?.putNext(.init()); invoice = nil
        XCTAssertTrue(InviteUI.purchaseContext?.scope === origin.scope); InviteUI.modal = nil
    }
    func testBrowserInvoiceResetDuringProgressSetupPreventsSubscription() {
        let context = AccountContext(); let page = InvoicePage(context, origin: nil); var subscribed = false
        context.engine.payments.invoices = Signal { _ in subscribed = true; return EmptyDisposable }
        UI.onProgress = { page.invoiceAction.reset() }
        page.receive(["slug": "synthetic"]); XCTAssertFalse(subscribed); XCTAssertTrue(page.events.isEmpty)
        UI.onProgress = nil
    }
}

extension LinkTests {
    func testBrowserInvoiceErrorAfterWindowChangeDoesNotShowFeedbackAndAllowsRetry() {
        for detach in [true, false] {
            installInvoiceHooks(); let context = AccountContext()
            let page = InvoicePage(context, origin: AnalyticsContext(excluded: true))
            let originalWindow = page.window
            var invoice: Subscriber<TelegramMediaInvoice, InvoiceError>?
            context.engine.payments.invoices = Signal { invoice = $0; return EmptyDisposable }
            page.receive(["slug": "old"])
            page.window = detach ? nil : Window()
            invoice?.putError(.generic); invoice = nil
            XCTAssertTrue(InviteUI.texts.isEmpty); XCTAssertTrue(page.events.isEmpty)
            page.window = originalWindow
            context.engine.payments.invoices = .single(.init())
            page.receive(["slug": "retry"]); InviteUI.modal = nil
            XCTAssertEqual(page.events, [["slug": "retry", "status": "cancelled"]])
            UI.reset()
        }
    }

    func testBrowserInvoiceOldCheckoutCannotConsumeNewDocumentAttempt() {
        installInvoiceHooks(); let context = AccountContext(); context.engine.payments.invoices = .single(.init())
        let page = InvoicePage(context, origin: AnalyticsContext(excluded: true))
        page.receive(["slug": "old"])
        var oldModal = InviteUI.modal; let oldCompletion = InviteUI.purchase
        page.webView(WKWebView(), didStartProvisionalNavigation: nil)
        page.receive(["slug": "new"])
        oldCompletion?(.paid(messageId: nil, peerId: nil)); XCTAssertNotNil(oldModal); oldModal = nil
        XCTAssertTrue(page.events.isEmpty)
        InviteUI.modal = nil
        XCTAssertEqual(page.events, [["slug": "new", "status": "cancelled"]])
    }
    func testBrowserInvoiceDoesNotPresentIntoDetachedOrReplacedWindow() {
        for detached in [false, true] {
            installInvoiceHooks(); let context = AccountContext()
            var invoice: Subscriber<TelegramMediaInvoice, InvoiceError>?
            context.engine.payments.invoices = Signal { invoice = $0; return EmptyDisposable }
            let page = InvoicePage(context, origin: AnalyticsContext(excluded: true)); page.receive(["slug": "synthetic"])
            page.window = detached ? nil : Window()
            invoice?.putNext(.init()); invoice = nil
            XCTAssertNil(InviteUI.modal); XCTAssertTrue(page.events.isEmpty)
            UI.reset()
        }
    }
}

extension LinkTests {
    private func accountRoutes(_ context: AccountContext) -> [inAppLink] {
        let callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void = { _, _, _, _ in }
        return [
            .tonsite(link: "synthetic", context: context),
            .followResolvedName(link: "synthetic", username: "synthetic", postId: nil, forceProfile: false, context: context, action: nil, callback: callback),
            .noPaidMessagesToken(link: "synthetic", username: "synthetic", token: "synthetic", context: context, callback: callback),
            .contactToken(link: "synthetic", token: "synthetic", freeToken: nil, context: context, callback: callback),
            .contactToken(link: "synthetic", token: "synthetic", freeToken: "synthetic", context: context, callback: callback),
            .comments(link: "synthetic", username: "synthetic", context: context, threadId: 1, commentId: nil),
            .topic(link: "synthetic", username: "synthetic", context: context, threadId: 1, commentId: nil),
            .inviteBotToGroup(link: "synthetic", username: "synthetic", context: context, action: nil, rights: nil, isChannel: false, callback: callback),
            .shareUrl(link: "synthetic", context, "synthetic", nil),
            .joinchat(link: "synthetic", "synthetic", context: context, callback: callback),
            .stickerPack(link: "synthetic", .init(), context: context, peerId: nil),
            .confirmPhone(link: "synthetic", context: context, phone: "synthetic", hash: "synthetic"),
            .socks(link: "synthetic", .init(), context: context, applyProxy: { _ in }),
            .requestSecureId(link: "synthetic", context: context, value: .init()),
            .unsupportedScheme(link: "synthetic", context: context, path: "synthetic"),
            .applyLocalization(link: "synthetic", context: context, value: "synthetic"),
            .wallpaper(link: "synthetic", context: context, preview: .init()),
            .theme(link: "synthetic", context: context, name: "synthetic"),
            .tonTransfer(link: "synthetic", context: context, data: .init()),
            .sendGrams(link: "synthetic", context: context, data: .init()),
            .settings(link: "synthetic", context: context, section: .init()),
            .joinGroupCall(link: "synthetic", context: context, peerId: 2, call: .init()),
            .invoice(link: "synthetic", context: context, slug: "synthetic"),
            .premiumOffer(link: "synthetic", ref: nil, context: context),
            .restorePurchase(link: "synthetic", context: context),
            .urlAuth(link: "synthetic", context: context),
            .folder(link: "synthetic", slug: "synthetic", context: context),
            .story(link: "synthetic", username: "synthetic", storyId: 1, messageId: nil, context: context),
            .boost(link: "synthetic", username: "synthetic", context: context),
            .gift(link: "synthetic", slug: "synthetic", context: context),
            .businessLink(link: "synthetic", slug: "synthetic", context: context),
            .starsTopup(link: "synthetic", amount: 1, purpose: "synthetic", context: context),
            .multigift(link: "synthetic", context: context),
            .nft(link: "synthetic", slug: "synthetic", context: context),
            .joinCall(link: "synthetic", slug: "synthetic", context: context),
            .starsInfo(link: "synthetic", context: context, isTon: false),
            .auction(link: "synthetic", slug: "synthetic", context: context),
            .oauth(link: "synthetic", token: "synthetic", context: context),
            .createBot(link: "synthetic", context: context, managerUsername: "synthetic", botUsername: "synthetic", title: nil),
            .addStyle(link: "synthetic", slug: "synthetic", context: context)
        ]
    }

    func testEveryAccountRouteValidatesOriginBeforeEventAndRouteAction() {
        let account = AccountContext(1)
        for route in accountRoutes(account) {
            let revoked = AnalyticsContext(); revoked.scope?.valid = false
            for source in [nil, AnalyticsContext(2), AnalyticsContext(excluded: true), revoked] as [AnalyticsContext?] {
                executeAdmission(inapp: route, analyticsContext: source) { inherited in
                    XCTAssertNotNil(inherited)
                    XCTAssertGreaterThan(UI.exclusions, 0)
                }
                XCTAssertEqual(InviteUI.linkEvents, 0)
            }
        }
    }

    func testEveryAccountRouteRetainsMatchingGrantWithoutChangingLinkClassification() {
        for route in accountRoutes(AccountContext(1)) {
            let source = AnalyticsContext(1)
            let before = InviteUI.linkEvents
            executeAdmission(inapp: route, analyticsContext: source) { inherited in
                XCTAssertTrue(inherited?.scope === source.scope)
                XCTAssertEqual(UI.exclusions, 0)
            }
            XCTAssertEqual(InviteUI.linkEvents - before, analyticsLinkKind(route) == nil ? 0 : 1)
            if analyticsLinkKind(route) != nil { XCTAssertTrue(InviteUI.linkScopes.last === source.scope) }
        }
    }

    func testKnownSecretDestinationOrSourceExcludesBeforeLinkEvent() {
        let context = AccountContext()
        let routes: [inAppLink] = [
            .peerInfo(link: "synthetic", peerId: -1, action: nil, openChat: true, postId: nil, callback: { _, _, _, _ in }),
            .stickerPack(link: "synthetic", .init(), context: context, peerId: -1),
            .joinGroupCall(link: "synthetic", context: context, peerId: -1, call: .init()),
            .story(link: "synthetic", username: "synthetic", storyId: 1, messageId: MessageId(peerId: -1, namespace: 0, id: 1), context: context)
        ]
        for route in routes {
            executeAdmission(inapp: route, analyticsContext: AnalyticsContext()) { inherited in
                XCTAssertTrue(inherited?.isExcluded == true)
                XCTAssertGreaterThan(UI.exclusions, 0)
            }
        }
        XCTAssertEqual(InviteUI.linkEvents, 0)
    }

    func testAccountlessRoutesKeepExplicitSourceAndCannotCreateMissingGrant() {
        let routes: [inAppLink] = [
            .external(link: "synthetic", false), .botCommand("synthetic", { _ in }),
            .callback("synthetic", { _ in }), .code("synthetic", { _ in }),
            .hashtag("synthetic", { _ in }), .logout({}), .nothing,
            .instantView(link: "synthetic", webpage: .init(), anchor: nil),
            .loginCode(link: "synthetic", code: "synthetic"),
            .peerInfo(link: "synthetic", peerId: 2, action: nil, openChat: false, postId: nil, callback: { _, _, _, _ in })
        ]
        for route in routes {
            let source = AnalyticsContext()
            executeAdmission(inapp: route, analyticsContext: source) { inherited in
                XCTAssertTrue(inherited?.scope === source.scope); XCTAssertEqual(UI.exclusions, 0)
            }
            let before = InviteUI.linkEvents
            for excluded in [nil, AnalyticsContext(excluded: true)] as [AnalyticsContext?] {
                executeAdmission(inapp: route, analyticsContext: excluded) { inherited in
                    XCTAssertTrue(inherited?.isExcluded == true); XCTAssertGreaterThan(UI.exclusions, 0)
                }
            }
            XCTAssertEqual(InviteUI.linkEvents, before)
        }
    }

    func testAccountValidationCannotRecoverAnAlreadyRejectedOrigin() {
        let origin = AnalyticsContext(1)
        let first = analyticsLinkContext(.invoice(link: "synthetic", context: AccountContext(2), slug: "synthetic"), inherited: origin)
        executeAdmission(inapp: .invoice(link: "synthetic", context: AccountContext(1), slug: "synthetic"), analyticsContext: first) { inherited in
            XCTAssertNil(inherited?.scope); XCTAssertGreaterThan(UI.exclusions, 0)
        }
        XCTAssertEqual(InviteUI.linkEvents, 0)
    }
}

final class PreparedShareCancellation { func reset() {} }
