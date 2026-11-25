import Foundation
import ObjectiveC
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct MessageId: Equatable, ExpressibleByIntegerLiteral {
    let peerId: PeerId
    let id: Int64
    init(peerId: PeerId, id: Int64) { self.peerId = peerId; self.id = id }
    init(integerLiteral value: Int64) { self.init(peerId: 3, id: value) }
}
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
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(excluded: true) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext?) -> AnalyticsContext {
        let inherited = inherited ?? AnalyticsContext(engine.owner)
        return AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: engine.owner == inherited.owner ? inherited.scope : nil)
    }
}
protocol AccountContextProtocol: AnyObject { var engine: Engine { get }; var window: Window { get }; var peerId: PeerId { get }; var account: Account { get } }
final class Context: AccountContextProtocol {
    let engine: Engine
    let window = Window()
    let peerId: PeerId = 1
    let account = Account()
    init(_ owner: Int = 1) { engine = Engine(owner) }
}
final class Window {}
enum ItemMode { case destruct }
final class ContextMenuItem {
    let title: String
    let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void, itemMode: ItemMode? = nil, itemImage: Int = 0) { self.title = title; self.handler = handler }
}
enum MenuAnimation { case menu_message, menu_delete, menu_unmuted, menu_mute, menu_unarchive, menu_archive, menu_leave; var value: Int { 0 } }
final class ContextMenu {
    var items: [ContextMenuItem] = []
    init(betterInside: Bool = false) { UI.onNewsMenuInit?() }
    func addItem(_ item: ContextMenuItem) { items.append(item) }
    weak var delegate: ContextMenu?
    var onShow: (ContextMenu) -> Void = { _ in }
    var onClose: () -> Void = {}
}
func makeAttachmentMenu(_ analyticsContext: AnalyticsContext) -> ContextMenu {
    let menu = ContextMenu()
__MENU_PRESENTATION__
    return menu
}
struct BotFlags: OptionSet { let rawValue: Int; static let canBeAddedToAttachMenu = Self(rawValue: 1) }
struct BotInfo { var flags: BotFlags = [] }
class Peer {
    let id: PeerId
    var addressName: String? = "synthetic"
    var isVerified = false
    var botInfo: BotInfo? = BotInfo()
    var displayTitle: String { "synthetic" }
    init(_ id: PeerId) { self.id = id }
}
struct EnginePeer {
    let peer: Peer
    var id: PeerId { peer.id }
    init(_ peer: Peer) { self.peer = peer }
    var addressName: String? { peer.addressName }
    func _asPeer() -> Peer { peer }
}
struct AttachFlags: OptionSet {
    let rawValue: Int
    static let showInSettingsDisclaimer = Self(rawValue: 1), notActivated = Self(rawValue: 2), showInAttachMenu = Self(rawValue: 4)
}
struct AttachMenuBot {
    let peer: EnginePeer
    var flags: AttachFlags = []
    var shortName = "synthetic"
}
enum BackendError: Error { case generic }
final class Engine {
    let owner: Int
    let messages = Messages()
    let data = DataEngine()
    let peers = PeersEngine()
    init(_ owner: Int) { self.owner = owner }
}
enum InactiveSource { case join }
func showInactiveChannels(context: any AccountContextProtocol, source: InactiveSource) { UI.inactiveOrigins.append(nil); UI.onInactiveChannels?() }
func showInactiveChannels(context: any AccountContextProtocol, source: InactiveSource, analyticsContext: AnalyticsContext?) { UI.inactiveOrigins.append(analyticsContext); UI.onInactiveChannels?() }
enum JoinChannelError: Error { case generic, tooMuchJoined, tooMuchUsers, inviteRequestSent }
struct JoinView { let botPeer: EnginePeer; let url: String?; let queryId: Int64 }
enum ChatListGroupId { case root, archive }
enum ChannelJoinOutcome { case joined, webView(JoinView) }
final class PeersEngine {
    var signal: Signal<ChannelJoinOutcome, JoinChannelError> = .complete()
    var requested: [PeerId] = []
    var forNews: [Bool] = []
    var effects: [String] = []
    var effectIds: [PeerId] = []
    var effect: Signal<Void, NoError> = .complete()
    func joinChannel(peerId: PeerId, hash: String?, forNews: Bool = false) -> Signal<ChannelJoinOutcome, JoinChannelError> {
        requested.append(peerId); self.forNews.append(forNews); UI.onChannelRequest?(); return signal
    }
    func removePeerChat(peerId: PeerId, reportChatSpam: Bool) -> Signal<Void, NoError> { record("remove", peerId); return effect }
    func updatePeerMuteSetting(peerId: PeerId, threadId: Int64?, muteInterval: Int32) -> Signal<Void, NoError> { record("mute", peerId); return effect }
    func togglePeerMuted(peerId: PeerId, threadId: Int64?) -> Signal<Void, NoError> { record("toggle", peerId); return effect }
    func updatePeersGroupIdInteractively(peerIds: [PeerId], groupId: ChatListGroupId) -> Signal<Void, NoError> { record(groupId == .archive ? "archive" : "unarchive", peerIds[0]); return effect }
    func record(_ name: String, _ id: PeerId) { effects.append(name); effectIds.append(id); UI.onNewsEffect?() }
}
final class Messages {
    var joinResult: Signal<RequestWebViewResult, BackendError> = .single(RequestWebViewResult(flags: [1], queryId: nil, url: "resolved", keepAliveSignal: nil))
    var joinQueries: [Int64] = []
    func requestChatJoinWebView(queryId: Int64, themeParams: [String: Any]?) -> Signal<RequestWebViewResult, BackendError> { joinQueries.append(queryId); UI.onJoinRequest?(); return joinResult }
    var installed: Signal<[AttachMenuBot], NoError> = .single([])
    var metadata: Signal<AttachMenuBot, BackendError> = .complete()
    var add: Signal<Bool, BackendError> = .complete()
    var accept: Signal<Never, NoError> = .complete()
    var metadataIds: [PeerId] = []
    var addIds: [PeerId] = []
    var accepted: [PeerId] = []
    func attachMenuBots() -> Signal<[AttachMenuBot], NoError> { installed }
    func getAttachMenuBot(botId: PeerId, cached: Bool) -> Signal<AttachMenuBot, BackendError> { XCTAssertTrue(cached); metadataIds.append(botId); UI.onMetadata?(); return metadata }
    func addBotToAttachMenu(botId: PeerId, allowWrite: Bool) -> Signal<Bool, BackendError> { XCTAssertTrue(allowWrite); addIds.append(botId); UI.onInstall?(); return add }
    func acceptAttachMenuBotDisclaimer(botId: PeerId) -> Signal<Never, NoError> { accepted.append(botId); UI.onAccept?(); return accept }
}
enum ChatBrowserTab {
    case webapp(bot: EnginePeer, peerId: PeerId, buttonText: String, url: String?, payload: String?, threadId: Int64?, replyTo: MessageId?, fromMenu: Bool)
    case straight(bot: EnginePeer, peerId: PeerId, title: String, result: RequestWebViewResult)
}
struct BotApp { let title: String }
struct RequestWebViewResult {
    var flags: [Int] = []
    var queryId: Int64?
    var url: String = ""
    var keepAliveSignal: Signal<Never, NoError>?
    init() {}
    init(flags: [Int], queryId: Int64?, url: String, keepAliveSignal: Signal<Never, NoError>?) { self.flags = flags; self.queryId = queryId; self.url = url; self.keepAliveSignal = keepAliveSignal }
}
struct DraftPresentation {
    struct Reply { let messageId: MessageId }
    struct InterfaceState { var replyMessageId: Reply? = Reply(messageId: 10) }
    struct Location: Equatable { var threadId: Int64? = 9 }
    var interfaceState = InterfaceState()
    var chatLocation = Location()
    func withoutInitialAction() -> DraftPresentation { self }
}
final class IncomingAction {
    var context: Context
    var peerId: PeerId = 3
    var origin: AnalyticsContext
    var presentation = DraftPresentation()
    var onUpdate: (() -> Void)?
    init(_ context: Context, _ origin: AnalyticsContext) { self.context = context; self.origin = origin }
    var chatLocation: DraftPresentation.Location { presentation.chatLocation }
    func captureAnalyticsContext(sourcePeerId: PeerId? = nil) -> AnalyticsContext { sourcePeerId.map { origin.restricting(peerId: $0) } ?? origin }
    func attachmentHandler(_ bot: AttachMenuBot) -> () -> Void {
        let chatInteraction = self
        let context = self.context
        let peerId = self.peerId
        let threadId = presentation.chatLocation.threadId
        let replyTo = presentation.interfaceState.replyMessageId?.messageId
__MENU_CAPTURE__
        return {
__MENU_ACTION__
        }
    }
    func update(animated: Bool = false, _ f: (DraftPresentation) -> DraftPresentation) { presentation = f(presentation); onUpdate?() }
    func attach(botname: String, payload: String?) {
__ATTACH_INGRESS__
    }
    func webview(botPeer: EnginePeer, botApp: BotApp, result: RequestWebViewResult, animated: Bool = false) {
__WEB_INGRESS__
    }
}
typealias ChatInteraction = IncomingAction
enum ChatState {
    struct NewsChannelData {
        let peerId: PeerId
        var title = "synthetic"
        var isMember = false
        var isMuted = false
        var isInNews = false
    }
}
final class NewsView {
__NEWS_MODE__
    var data: ChatState.NewsChannelData?
    weak var chatInteraction: ChatInteraction?
    var isAddingToNews = false
    var isArchived = false
    var observedPeerId: PeerId?
    var newsActionGeneration: UInt64 = 0
    let newsDisposable = MetaDisposable()
    let groupDisposable = MetaDisposable()
    let actionDisposable = MetaDisposable()
    let menuActionDisposable = MetaDisposable()
    var window: Window? { chatInteraction?.context.window }
    func applyUpdate(animated: Bool) { UI.onNewsUpdate?() }
__NEWS_DEINIT__
__NEWS_MODE_VALUE__
__NEWS_CAPTURE__
__NEWS_ACTIONS__
}
struct ChatNavigationHooks {
    static var shared = ChatNavigationHooks()
__HOOKS__
__INACTIVE_HOOK__
}
struct FeatureNavigationHooks {
    static var shared = FeatureNavigationHooks()
__FEATURE_JOIN__
}
func installFeatureJoinHooks() {
    var hooks = FeatureNavigationHooks()
__FEATURE_JOIN_INSTALL__
    FeatureNavigationHooks.shared = hooks
}
__CHANNEL_JOIN__
final class ChannelController {
    let context: Context
    let peerId: PeerId
    let chatInteraction: IncomingAction
    init(_ context: Context, _ origin: AnalyticsContext, peerId: PeerId = 3) {
        self.context = context; self.peerId = peerId; self.chatInteraction = IncomingAction(context, origin)
    }
    func handler() -> () -> Void {
        let context = self.context
        let peerId = self.peerId
__CHANNEL_INGRESS__
    }
}
struct ChatInterfaceHooks {
    static var shared = ChatInterfaceHooks()
    var resolveUsername: (String, any AccountContextProtocol) -> Signal<Peer?, NoError> = { name, _ in UI.names.append(name); return UI.resolution }
}
func installHooks() {
    var hooks = ChatNavigationHooks()
__INSTALL__
__INACTIVE_INSTALL__
    hooks.openBrowserTab = { _, tab in UI.onBrowser?(); UI.tabs.append(tab) }
    ChatNavigationHooks.shared = hooks
}
class ViewController: NSObject { var analyticsContext: AnalyticsContext? }
struct BrowserTabData {
    enum Unique: Hashable { case webapp(Int64) }
    enum Source { case settings }
    enum Data {
        case mainapp(bot: EnginePeer, source: Source)
        case webapp(bot: EnginePeer, peerId: PeerId, buttonText: String, url: String?, payload: String?, threadId: Int64?, replyTo: MessageId?, fromMenu: Bool)
        case simple(bot: EnginePeer, url: String?, buttonText: String, source: Source)
        case straight(bot: EnginePeer, peerId: PeerId, title: String, result: RequestWebViewResult)
        case game(url: String, peerId: PeerId, messageId: MessageId)
        case tonsite(url: String)
        case instantView(url: String, webPage: Int, anchor: String?)
        var peer: EnginePeer? {
            switch self { case let .mainapp(bot, _), let .webapp(bot, _, _, _, _, _, _, _), let .simple(bot, _, _, _), let .straight(bot, _, _, _): return bot; default: return nil }
        }
    }
}
enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct Peer { let id: PeerId } } } } }
final class DataEngine {
    var signal: Signal<EnginePeer?, NoError> = .single(nil)
    var ids: [PeerId] = []
    func get(_ item: TelegramEngine.EngineData.Item.Peer.Peer) -> Signal<EnginePeer?, NoError> { ids.append(item.id); UI.onJoinLookup?(); return signal }
}
enum JoinChatWebViewResult { case approved, declined, queued, webView(String) }
struct JoinChatWebViewDecision { let peerId: PeerId; let queryId: Int64; let result: JoinChatWebViewResult }
final class StateManager {
    let decisions = ValuePipe<[JoinChatWebViewDecision]>()
    var joinChatWebViewDecisions: Signal<[JoinChatWebViewDecision], NoError> { decisions.signal() }
}
final class Account { let stateManager = StateManager() }
struct Theme { struct Icons { let successModalProgress = 0 }; let icons = Icons() }
let theme = Theme()
func generateWebAppThemeParams(_ theme: Theme) -> [String: Any]? { nil }
func showModalSuccess(for window: Window, icon: Int, delay: Double) -> Signal<Void, NoError> {
    UI.joinSuccess += 1; UI.onJoinFeedback?(); UI.joinOrder.append("feedback"); return .single(())
}
final class BrowserStateContext {
    let context: any AccountContextProtocol
    var joinChatOperations: [BrowserTabData.Unique: JoinChatWebViewOperation] = [:]
    init(_ context: any AccountContextProtocol) { self.context = context }
    static func get(_ context: any AccountContextProtocol) -> BrowserStateContext {
        let key = ObjectIdentifier(context)
        if let state = UI.joinStates[key] { return state }
        let state = BrowserStateContext(context); UI.joinStates[key] = state; return state
    }
__JOIN_OWNER__
    func closeAccountForTest() { cancelJoinChatOperations() }
    func openCancellable(tab: BrowserTabData.Data, uniqueId: BrowserTabData.Unique?, analyticsContext: AnalyticsContext?, completion: ((Bool) -> Void)? = nil) -> Disposable {
        UI.joinTabs.append(tab); UI.joinIds.append(uniqueId); UI.joinOrigins.append(analyticsContext); UI.onJoinOpen?()
        var completed = false
        let complete: (Bool) -> Void = { opened in guard !completed else { return }; completed = true; completion?(opened) }
        if UI.deferJoinOpen { UI.joinOpenCallbacks.append(complete) } else { complete(true) }
        return ActionDisposable { UI.joinCancelled += 1; UI.joinOrder.append("cancel"); complete(false) }
    }
    func closeJoinChatTab(uniqueId: BrowserTabData.Unique) { UI.joinClosed.append(uniqueId); UI.joinOrder.append("close") }
    func open(tab: BrowserTabData.Data, analyticsContext: AnalyticsContext?) {
        UI.settingsTabs.append(tab); UI.settingsOrigins.append(analyticsContext); UI.onSettingsBrowser?()
    }
}
__JOIN_OPERATION__
__BROWSER_ORIGIN__
__SETTINGS_BOT__
__JOIN_BACKEND__
struct SettingsNavigationHooks {
    static var shared = SettingsNavigationHooks()
__SETTINGS_HOOKS__
}
func installSettingsHooks() {
    var hooks = SettingsNavigationHooks()
__SETTINGS_INSTALL__
    SettingsNavigationHooks.shared = hooks
}
final class SettingsController {
    let context: Context
    var analyticsContext: AnalyticsContext?
    init(_ context: Context, _ origin: AnalyticsContext?) { self.context = context; analyticsContext = origin }
    func handler() -> (AttachMenuBot) -> Void {
        let context = self.context
        return { [weak self] bot in
__SETTINGS_INGRESS__
        }
    }
}
__BACKEND__
struct ModalAlertData {
    struct Option { let string: String; let isSelected: Bool; let mandatory: Bool }
    struct Description { let string: String; let onlyWhenEnabled: Bool }
    let title: String
    let info: String
    let description: Description?
    let ok: String
    let options: [Option]
}
func showModalAlert(for window: Window, data: ModalAlertData, completion: @escaping (Bool) -> Void, cancel: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    UI.onConfirmation?(); UI.data = data; UI.confirmed = completion; UI.cancelled = cancel; UI.dismissed = onDeinit
}
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> { UI.onProgress?(); return signal }
func showModalText(for window: Window, text: String, title: String? = nil) { UI.onFeedback?(); UI.feedback += 1 }
func alert(for window: Window, info: String) { UI.onFeedback?(); UI.missing += 1 }
struct Strings {
    let chatContextUnarchive = "unarchive", chatContextArchive = "archive"
    let groupUsersTooMuchError = "too many users"
    let unknownError = "unknown", chatSendJoinRequestInfo = "queued", chatSendJoinRequestTitle = "join"
    let webBotAccountDisclaimerThird = "option", webBotAccountDisclaimerTitle = "title", webBotAccountDisclaimerText = "text", webBotAccountDisclaimerOK = "ok"
    func webBotAccountDesclaimerDesc(_ name: String) -> String { "description" }
    func webAppAttachSuccess(_ name: String) -> String { "success" }
    func webAppAttachDoenstExist(_ name: String) -> String { "missing" }
}
func strings() -> Strings { Strings() }
__ACTION__
enum UI {
    static var newsInteractions: [IncomingAction] = []
    static var onNewsMenuInit: (() -> Void)?
    static var onNewsEffect: (() -> Void)?
    static var onNewsUpdate: (() -> Void)?
    static var onChannelRequest: (() -> Void)?
    static var inactiveOrigins: [AnalyticsContext?] = []
    static var onInactiveChannels: (() -> Void)?
    static var joinStates: [ObjectIdentifier: BrowserStateContext] = [:]
    static var deferJoinOpen = false
    static var joinOpenCallbacks: [(Bool) -> Void] = []
    static var onJoinRequest: (() -> Void)?
    static var joinTabs: [BrowserTabData.Data] = []
    static var joinIds: [BrowserTabData.Unique?] = []
    static var joinOrigins: [AnalyticsContext?] = []
    static var joinClosed: [BrowserTabData.Unique] = []
    static var joinCancelled = 0
    static var joinSuccess = 0
    static var joinOrder: [String] = []
    static var onJoinLookup: (() -> Void)?
    static var onJoinOpen: (() -> Void)?
    static var onJoinFeedback: (() -> Void)?
    static var settingsTabs: [BrowserTabData.Data] = []
    static var settingsOrigins: [AnalyticsContext?] = []
    static var onSettingsBrowser: (() -> Void)?
    static var exclusions = 0
    static var resolution: Signal<Peer?, NoError> = .single(nil)
    static var names: [String] = []
    static var tabs: [ChatBrowserTab] = []
    static var data: ModalAlertData?
    static var confirmed: ((Bool) -> Void)?
    static var cancelled: (() -> Void)?
    static var dismissed: (() -> Void)?
    static var onMetadata: (() -> Void)?
    static var onInstall: (() -> Void)?
    static var onAccept: (() -> Void)?
    static var onBrowser: (() -> Void)?
    static var onConfirmation: (() -> Void)?
    static var onProgress: (() -> Void)?
    static var onFeedback: (() -> Void)?
    static var feedback = 0
    static var missing = 0
    static func reset() {
        newsInteractions = []; onNewsMenuInit = nil; onNewsEffect = nil; onNewsUpdate = nil
        inactiveOrigins = []; onChannelRequest = nil; onInactiveChannels = nil; installFeatureJoinHooks()
        joinStates = [:]; deferJoinOpen = false; joinOpenCallbacks = []; onJoinRequest = nil
        joinTabs = []; joinIds = []; joinOrigins = []; joinClosed = []; joinCancelled = 0; joinSuccess = 0; joinOrder = []
        onJoinLookup = nil; onJoinOpen = nil; onJoinFeedback = nil
        settingsTabs = []; settingsOrigins = []; onSettingsBrowser = nil; installSettingsHooks()
        resolution = .single(nil); names = []; tabs = []; data = nil; confirmed = nil; cancelled = nil; dismissed = nil
        onMetadata = nil; onInstall = nil; onAccept = nil; onBrowser = nil; onConfirmation = nil; onProgress = nil; onFeedback = nil
        feedback = 0; missing = 0; installHooks()
    }
}
final class BotTests: XCTestCase {
    override func setUp() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    override func tearDown() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    func setupBot(_ context: Context, disclaimer: Bool = false, install: Bool = false) -> Peer {
        let bot = Peer(2)
        if install { bot.botInfo?.flags.insert(.canBeAddedToAttachMenu) }
        let menu = AttachMenuBot(peer: EnginePeer(bot), flags: disclaimer ? [.notActivated] : [])
        context.engine.messages.installed = .single([menu]); context.engine.messages.metadata = .single(menu)
        return bot
    }
    func start(_ context: Context, origin: AnalyticsContext = AnalyticsContext(excluded: true), peerId: PeerId = 3) {
        chatOpenAttachBot(context: context, peerId: peerId, threadId: 9, replyId: 10, botname: "SYNTHETIC", payload: "synthetic", analyticsContext: origin)
    }
    func testInstalledBotKeepsCapturedTargetAndOpensOnceUnderOrigin() {
        let context = Context(); _ = setupBot(context)
        UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
        start(context)
        XCTAssertTrue(UI.names.isEmpty); XCTAssertEqual(UI.tabs.count, 1)
        if case let .webapp(bot, peer, _, _, payload, thread, reply, fromMenu) = UI.tabs[0] {
            XCTAssertEqual(bot.peer.id, 2); XCTAssertEqual(peer, 3); XCTAssertEqual(thread, 9); XCTAssertEqual(reply, 10); XCTAssertEqual(payload, "synthetic"); XCTAssertFalse(fromMenu)
        }
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testDelayedResolveAndMetadataRetainOriginAfterParentEnds() {
        let context = Context(); let bot = Peer(2)
        var resolved: Subscriber<Peer?, NoError>?
        var metadata: Subscriber<AttachMenuBot, BackendError>?
        UI.resolution = Signal { resolved = $0; return EmptyDisposable }
        context.engine.messages.metadata = Signal { metadata = $0; return EmptyDisposable }
        UI.onMetadata = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
        start(context); XCTAssertGreaterThan(UI.exclusions, 0)
        resolved?.putNext(bot); resolved?.putNext(Peer(4)); resolved = nil
        XCTAssertEqual(context.engine.messages.metadataIds, [2]); XCTAssertGreaterThan(UI.exclusions, 0)
        metadata?.putNext(AttachMenuBot(peer: EnginePeer(bot))); metadata?.putNext(AttachMenuBot(peer: EnginePeer(bot))); metadata = nil
        XCTAssertEqual(UI.tabs.count, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testDisclaimerCloseBeforeConfirmationInstallsAndOpensOnceAfterDelayedResult() {
        let context = Context(); _ = setupBot(context, disclaimer: true)
        var installed: Subscriber<Bool, BackendError>?
        context.engine.messages.add = Signal { installed = $0; return EmptyDisposable }
        UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onAccept = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onInstall = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
        start(context); XCTAssertEqual(UI.data?.options.first?.mandatory, true); XCTAssertGreaterThan(UI.exclusions, 0)
        UI.dismissed?(); UI.confirmed?(true); UI.confirmed?(true); drainMain()
        XCTAssertEqual(context.engine.messages.accepted, [2]); XCTAssertEqual(context.engine.messages.addIds, [2]); XCTAssertTrue(UI.tabs.isEmpty)
        XCTAssertGreaterThan(UI.exclusions, 0)
        installed?.putNext(true); installed?.putNext(true); installed = nil
        XCTAssertEqual(UI.tabs.count, 1); XCTAssertEqual(UI.feedback, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testCancelAndUnknownDisclaimerCloseDoNotWriteOrOpen() {
        for cancel in [true, false] {
            let context = Context(); _ = setupBot(context, disclaimer: true)
            start(context)
            if cancel { UI.cancelled?() }
            UI.dismissed?(); drainMain(); UI.confirmed?(true)
            XCTAssertTrue(context.engine.messages.accepted.isEmpty); XCTAssertTrue(context.engine.messages.addIds.isEmpty); XCTAssertTrue(UI.tabs.isEmpty)
            XCTAssertEqual(UI.exclusions, 0); UI.reset()
        }
    }
    func testInstallFalseErrorAndEmptyResultsDoNotOpenOrInventSuccess() {
        let signals: [Signal<Bool, BackendError>] = [.single(false), .fail(.generic), .complete()]
        for signal in signals {
            let context = Context(); _ = setupBot(context, install: true); context.engine.messages.add = signal
            start(context)
            XCTAssertEqual(context.engine.messages.addIds, [2]); XCTAssertTrue(UI.tabs.isEmpty); XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testMetadataErrorPreservesExistingOpenFallbackButInvalidBotDoesNotOpen() {
        let context = Context(); let bot = setupBot(context); context.engine.messages.metadata = .fail(.generic)
        UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
        start(context); XCTAssertEqual(UI.tabs.count, 1)
        UI.reset(); bot.botInfo = nil; start(context)
        XCTAssertTrue(UI.tabs.isEmpty); XCTAssertEqual(context.engine.messages.metadataIds, [2]); XCTAssertEqual(UI.exclusions, 0)
    }
    func testMissingUsernameAndEmptyInstalledSignalStayDistinct() {
        let context = Context()
        UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
        start(context); XCTAssertEqual(UI.missing, 1); XCTAssertTrue(UI.tabs.isEmpty)
        UI.reset(); context.engine.messages.installed = .complete(); start(context)
        XCTAssertTrue(UI.names.isEmpty); XCTAssertEqual(UI.missing, 0); XCTAssertEqual(UI.exclusions, 0)
    }
    func testForeignAccountSecretTargetAndRevocationDenyLateOpen() {
        for (account, peer): (Int, PeerId) in [(2, 3), (1, -3), (1, 3)] {
            let context = Context(account); let bot = setupBot(context); let origin = AnalyticsContext()
            var metadata: Subscriber<AttachMenuBot, BackendError>?
            context.engine.messages.metadata = Signal { metadata = $0; return EmptyDisposable }
            start(context, origin: origin, peerId: peer)
            origin.scope?.valid = false
            UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
            metadata?.putNext(AttachMenuBot(peer: EnginePeer(bot))); metadata = nil
            XCTAssertEqual(UI.tabs.count, 1); UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testInstallBackendKeepsLegacyTrueOnlyResultAndConsumesOnce() {
        let context = Context(); let peer = Peer(2)
        var result: Subscriber<Bool, BackendError>?
        context.engine.messages.add = Signal { result = $0; return EmptyDisposable }
        var values: [Bool] = []
        installAttachMenuBot(context: context, peer: peer) { values.append($0) }
        result?.putNext(true); result?.putNext(true); result = nil
        XCTAssertEqual(values, [true]); XCTAssertEqual(UI.exclusions, 0)
    }
    func testObservedLegacyInstallationCallbackIsConsumedBeforeReentrantDelivery() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        var callback: ((Bool) -> Void)?
        var hooks = ChatNavigationHooks()
        hooks.installAttachMenuBot = { _, _, completed in callback = completed }
        var values: [Bool] = []
        hooks.installAttachMenuBotObserved(context, Peer(2), analyticsContext: origin, completion: { value in
            XCTAssertGreaterThan(UI.exclusions, 0); values.append(value); callback?(true)
        })
        XCTAssertEqual(UI.exclusions, 0)
        callback?(true); callback?(true); callback = nil
        XCTAssertEqual(values, [true]); XCTAssertEqual(UI.exclusions, 0)
    }
    func testBrowserCompanionReceivesImmutableOriginInsteadOfLegacyFallback() {
        let context = Context(); _ = setupBot(context); let origin = AnalyticsContext()
        var calls = 0
        ChatNavigationHooks.shared.openBrowserTabWithContext = { _, _, captured in calls += 1; XCTAssertTrue(captured.scope === origin.scope) }
        start(context, origin: origin)
        XCTAssertEqual(calls, 1); XCTAssertTrue(UI.tabs.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testAttachIngressCapturesTargetAndOriginBeforeReentrantStateUpdate() {
        let context = Context(); _ = setupBot(context)
        let action = IncomingAction(context, AnalyticsContext(excluded: true))
        action.onUpdate = { [weak action] in
            XCTAssertGreaterThan(UI.exclusions, 0)
            action?.context = Context(2); action?.peerId = 8; action?.origin = AnalyticsContext(2)
            action?.presentation.chatLocation.threadId = 20; action?.presentation.interfaceState.replyMessageId = nil
        }
        action.attach(botname: "synthetic", payload: nil)
        XCTAssertEqual(context.engine.messages.metadataIds, [2]); XCTAssertEqual(UI.tabs.count, 1)
        if case let .webapp(_, peer, _, _, _, thread, reply, _) = UI.tabs[0] { XCTAssertEqual(peer, 3); XCTAssertEqual(thread, 9); XCTAssertEqual(reply, 10) } else { XCTFail() }
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testWebviewIngressCapturesAccountPeerAndOriginBeforeUpdate() {
        let context = Context(); let action = IncomingAction(context, AnalyticsContext(excluded: true))
        action.onUpdate = { [weak action] in
            XCTAssertGreaterThan(UI.exclusions, 0)
            action?.context = Context(2); action?.peerId = 8; action?.origin = AnalyticsContext(2)
        }
        var calls = 0
        ChatNavigationHooks.shared.openBrowserTabWithContext = { account, tab, origin in
            calls += 1; XCTAssertTrue(account as AnyObject === context); XCTAssertTrue(origin.isExcluded)
            if case let .straight(_, peer, _, _) = tab { XCTAssertEqual(peer, 3) } else { XCTFail() }
        }
        action.webview(botPeer: EnginePeer(Peer(2)), botApp: BotApp(title: "synthetic"), result: RequestWebViewResult())
        XCTAssertEqual(calls, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    private func drainMain() {
        let done = expectation(description: "main delivery")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}
extension BotTests {
    func testMenuHandlerCapturesAccountDestinationAndOriginBeforeLaterMutation() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        let action = IncomingAction(context, origin)
        let handler = action.attachmentHandler(AttachMenuBot(peer: EnginePeer(Peer(2))))
        action.context = Context(2); action.peerId = 8; action.origin = AnalyticsContext(2)
        action.presentation.chatLocation.threadId = 100
        action.presentation.interfaceState.replyMessageId = nil
        ChatNavigationHooks.shared.openBrowserTabWithContext = { account, tab, received in
            XCTAssertTrue(account as AnyObject === context); XCTAssertTrue(received.isExcluded)
            XCTAssertGreaterThan(UI.exclusions, 0); UI.tabs.append(tab)
        }
        handler()
        XCTAssertEqual(UI.tabs.count, 1)
        guard case let .webapp(bot, peerId, _, _, payload, threadId, reply, fromMenu) = UI.tabs[0] else { return XCTFail() }
        XCTAssertEqual(bot.id, 2); XCTAssertEqual(peerId, 3); XCTAssertEqual(threadId, 9); XCTAssertEqual(reply, 10)
        XCTAssertNil(payload); XCTAssertFalse(fromMenu)
        XCTAssertTrue(context.engine.messages.metadataIds.isEmpty); XCTAssertTrue(context.engine.messages.addIds.isEmpty)
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testMenuDisclaimerKeepsSecretOriginUntilDelayedInstallationAndOpensOnce() {
        let context = Context(); let bot = AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated])
        var installed: Subscriber<Bool, BackendError>?
        context.engine.messages.add = Signal { installed = $0; return EmptyDisposable }
        UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onAccept = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onInstall = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
        chatOpenAttachMenuBot(bot, context: context, peerId: -3, threadId: 9, replyId: nil, analyticsContext: AnalyticsContext())
        XCTAssertEqual(UI.data?.options.first?.mandatory, true)
        UI.dismissed?(); UI.confirmed?(true); UI.confirmed?(true); drainMenuMain()
        XCTAssertEqual(context.engine.messages.accepted, [2]); XCTAssertEqual(context.engine.messages.addIds, [2])
        XCTAssertTrue(UI.tabs.isEmpty); XCTAssertGreaterThan(UI.exclusions, 0)
        installed?.putNext(true); installed?.putNext(true); installed = nil
        XCTAssertEqual(UI.tabs.count, 1); XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
    }
    func testMenuCancelAndUnknownClosureDoNotAcknowledgeInstallOrOpen() {
        for cancel in [false, true] {
            let context = Context(); let bot = AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated])
            chatOpenAttachMenuBot(bot, context: context, peerId: 3, threadId: nil, replyId: nil, analyticsContext: AnalyticsContext(excluded: true))
            if cancel { UI.cancelled?() }
            UI.dismissed?(); drainMenuMain(); UI.confirmed?(true)
            XCTAssertTrue(context.engine.messages.accepted.isEmpty); XCTAssertTrue(context.engine.messages.addIds.isEmpty)
            XCTAssertTrue(UI.tabs.isEmpty); XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testMenuFalseErrorAndEmptyInstallationDoNotInventBrowserOrFeedback() {
        let signals: [Signal<Bool, BackendError>] = [.single(false), .fail(.generic), .complete()]
        for signal in signals {
            let context = Context(); context.engine.messages.add = signal
            let bot = AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated])
            chatOpenAttachMenuBot(bot, context: context, peerId: 3, threadId: nil, replyId: nil, analyticsContext: AnalyticsContext(excluded: true))
            UI.confirmed?(true)
            XCTAssertTrue(UI.tabs.isEmpty); XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testMenuFeedbackKeepsExistingEligibilityAndIsScoped() {
        for alreadyVisible in [false, true] {
            let context = Context(); let peer = Peer(2); peer.botInfo?.flags.insert(.canBeAddedToAttachMenu)
            let bot = AttachMenuBot(peer: EnginePeer(peer), flags: alreadyVisible ? [.showInSettingsDisclaimer, .showInAttachMenu] : [.showInSettingsDisclaimer])
            context.engine.messages.add = .single(true)
            UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
            chatOpenAttachMenuBot(bot, context: context, peerId: 3, threadId: nil, replyId: nil, analyticsContext: AnalyticsContext(excluded: true))
            UI.confirmed?(true); UI.confirmed?(true)
            XCTAssertEqual(UI.tabs.count, 1); XCTAssertEqual(UI.feedback, alreadyVisible ? 0 : 1)
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testMenuOrdinaryAndForeignContextDoNotAcquireNewGrants() {
        let original = AnalyticsContext()
        for owner in [1, 2] {
            let context = Context(owner); let bot = AttachMenuBot(peer: EnginePeer(Peer(2)))
            ChatNavigationHooks.shared.openBrowserTabWithContext = { _, _, received in
                if owner == 1 {
                    XCTAssertTrue(received.scope === original.scope); XCTAssertEqual(UI.exclusions, 0)
                } else {
                    XCTAssertNil(received.scope); XCTAssertGreaterThan(UI.exclusions, 0)
                }
            }
            chatOpenAttachMenuBot(bot, context: context, peerId: 3, threadId: nil, replyId: nil, analyticsContext: original)
            XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testMenuRevocationDuringInstallationIsNotRefreshedAtBrowserDelivery() {
        let context = Context(); let original = AnalyticsContext()
        var installed: Subscriber<Bool, BackendError>?
        context.engine.messages.add = Signal { installed = $0; return EmptyDisposable }
        let bot = AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated])
        ChatNavigationHooks.shared.openBrowserTabWithContext = { _, _, received in
            XCTAssertTrue(received.scope === original.scope); XCTAssertGreaterThan(UI.exclusions, 0)
        }
        chatOpenAttachMenuBot(bot, context: context, peerId: 3, threadId: nil, replyId: nil, analyticsContext: original)
        UI.confirmed?(true); original.scope?.valid = false
        installed?.putNext(true); installed = nil
        UI.reset(); XCTAssertEqual(UI.exclusions, 0)
    }
    func testSecretReplyRestrictsBothBotEntryPointsBeforeRequestsAndBrowserDelivery() {
        let context = Context(); _ = setupBot(context)
        let reply = MessageId(peerId: -3, id: 10)
        UI.onMetadata = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
        chatOpenAttachBot(context: context, peerId: 3, threadId: nil, replyId: reply, botname: "synthetic", payload: nil, analyticsContext: AnalyticsContext())
        chatOpenAttachMenuBot(AttachMenuBot(peer: EnginePeer(Peer(2))), context: context, peerId: 3, threadId: nil, replyId: reply, analyticsContext: AnalyticsContext())
        XCTAssertEqual(UI.tabs.count, 2); XCTAssertEqual(UI.exclusions, 0)
    }
    func testMenuRejectsFalseAndDuplicateLegacyInstallationCallbacks() {
        let context = Context(); let bot = AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated])
        var completion: ((Bool) -> Void)?
        ChatNavigationHooks.shared.installAttachMenuBotWithContext = nil
        ChatNavigationHooks.shared.installAttachMenuBot = { _, _, done in completion = done }
        chatOpenAttachMenuBot(bot, context: context, peerId: 3, threadId: nil, replyId: nil, analyticsContext: AnalyticsContext(excluded: true))
        UI.confirmed?(true)
        completion?(false); completion?(true); completion = nil
        XCTAssertTrue(UI.tabs.isEmpty); XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
    }
    private func drainMenuMain() {
        let done = expectation(description: "menu decision delivery")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}

extension BotTests {
    func testAttachmentMenuRetainsExclusionFromConstructionUntilCloseAndRechecksOnReopen() {
        let origin = AnalyticsContext(excluded: true)
        let menu = makeAttachmentMenu(origin)
        XCTAssertTrue(menu.delegate === menu)
        XCTAssertEqual(UI.exclusions, 1)
        menu.onShow(menu); XCTAssertEqual(UI.exclusions, 1)
        menu.onShow(menu); XCTAssertEqual(UI.exclusions, 1)
        menu.onClose(); menu.onClose(); XCTAssertEqual(UI.exclusions, 0)
        menu.onShow(menu); XCTAssertEqual(UI.exclusions, 1)
        menu.onClose(); XCTAssertEqual(UI.exclusions, 0)
    }
    func testAttachmentMenuDestructionReleasesUnknownCloseAndRevokedShowIsDenied() {
        let origin = AnalyticsContext()
        var menu: ContextMenu? = makeAttachmentMenu(origin)
        menu!.onShow(menu!); XCTAssertEqual(UI.exclusions, 0)
        menu!.onClose(); origin.scope?.valid = false
        menu!.onShow(menu!); XCTAssertEqual(UI.exclusions, 1)
        menu = nil; XCTAssertEqual(UI.exclusions, 0)
    }
    func testAttachmentMenuCloseBeforeBotActionStillProtectsDelivery() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        let action = IncomingAction(context, origin)
        let handler = action.attachmentHandler(AttachMenuBot(peer: EnginePeer(Peer(2))))
        let menu = makeAttachmentMenu(origin)
        menu.onShow(menu); menu.onClose(); XCTAssertEqual(UI.exclusions, 0)
        UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
        handler(); XCTAssertEqual(UI.tabs.count, 1); XCTAssertEqual(UI.exclusions, 0)
    }
}
extension BotTests {
    func testSettingsLegacyOpenIsUnresolvedBeforeConsentAndBrowserDelivery() {
        for disclaimer in [false, true] {
            let context = Context(); let bot = AttachMenuBot(peer: EnginePeer(Peer(2)), flags: disclaimer ? [.notActivated] : [])
            context.engine.messages.add = .single(true)
            UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onInstall = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onSettingsBrowser = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.settingsOrigins.last??.isExcluded == true) }
            openWebBot(bot, context: context)
            if disclaimer { UI.confirmed?(true) }
            XCTAssertEqual(UI.settingsTabs.count, 1); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testSettingsIngressAndInstalledCompanionPreserveScreenGrant() {
        let context = Context(); let original = AnalyticsContext()
        let controller = SettingsController(context, original)
        UI.onSettingsBrowser = { XCTAssertEqual(UI.exclusions, 0) }
        controller.handler()(AttachMenuBot(peer: EnginePeer(Peer(2))))
        XCTAssertEqual(UI.settingsTabs.count, 1)
        XCTAssertTrue(UI.settingsOrigins.last??.scope === original.scope)
        guard case let .simple(bot, url, text, .settings) = UI.settingsTabs[0] else { return XCTFail() }
        XCTAssertEqual(bot.id, 2); XCTAssertNil(url); XCTAssertEqual(text, "")
    }
    func testSettingsHandlerDoesNotLaunchAfterScreenOwnerIsReleased() {
        var controller: SettingsController? = SettingsController(Context(), AnalyticsContext(excluded: true))
        let handler = controller!.handler()
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        handler(AttachMenuBot(peer: EnginePeer(Peer(2))))
        XCTAssertTrue(UI.settingsTabs.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testSettingsDisclaimerInstallsOnceAndRetainsPrivateContextAfterScreenRelease() {
        let context = Context()
        var installed: Subscriber<Bool, BackendError>?
        context.engine.messages.add = Signal { installed = $0; return EmptyDisposable }
        var controller: SettingsController? = SettingsController(context, AnalyticsContext(excluded: true))
        UI.onConfirmation = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onInstall = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onSettingsBrowser = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.settingsOrigins.last??.isExcluded == true) }
        controller!.handler()(AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated]))
        controller = nil
        UI.dismissed?(); UI.confirmed?(true); UI.confirmed?(true); drainSettingsMain()
        XCTAssertEqual(context.engine.messages.accepted, [2]); XCTAssertEqual(context.engine.messages.addIds, [2])
        XCTAssertTrue(UI.settingsTabs.isEmpty); XCTAssertGreaterThan(UI.exclusions, 0)
        installed?.putNext(true); installed?.putNext(true); installed = nil
        XCTAssertEqual(UI.settingsTabs.count, 1); XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
    }
    func testSettingsCancelAndUnknownDisclaimerCloseCannotLaterInstall() {
        for cancel in [false, true] {
            let context = Context()
            openWebBot(AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated]), context: context, analyticsContext: AnalyticsContext(excluded: true))
            if cancel { UI.cancelled?() }
            UI.dismissed?(); drainSettingsMain(); UI.confirmed?(true)
            XCTAssertTrue(context.engine.messages.accepted.isEmpty); XCTAssertTrue(context.engine.messages.addIds.isEmpty)
            XCTAssertTrue(UI.settingsTabs.isEmpty); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testSettingsFalseErrorAndEmptyInstallationDoNotOpenOrShowSuccess() {
        for signal: Signal<Bool, BackendError> in [.single(false), .fail(.generic), .complete()] {
            let context = Context(); context.engine.messages.add = signal
            openWebBot(AttachMenuBot(peer: EnginePeer(Peer(2)), flags: [.notActivated]), context: context, analyticsContext: AnalyticsContext(excluded: true))
            UI.confirmed?(true)
            XCTAssertTrue(UI.settingsTabs.isEmpty); XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testSettingsForeignSecretAndRevokedContextsAreDeniedWithoutFreshGrant() {
        for mode in 0..<3 {
            let context = Context(mode == 0 ? 2 : 1); let original = AnalyticsContext()
            let bot = AttachMenuBot(peer: EnginePeer(Peer(mode == 1 ? -2 : 2)), flags: [.notActivated])
            var installed: Subscriber<Bool, BackendError>?
            context.engine.messages.add = Signal { installed = $0; return EmptyDisposable }
            openWebBot(bot, context: context, analyticsContext: original)
            UI.confirmed?(true)
            if mode == 2 { original.scope?.valid = false }
            UI.onSettingsBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
            installed?.putNext(true); installed = nil
            XCTAssertEqual(UI.settingsTabs.count, 1)
            if mode == 2 { XCTAssertTrue(UI.settingsOrigins.last??.scope === original.scope) }
            else { XCTAssertNil(UI.settingsOrigins.last??.scope) }
            UI.reset(); XCTAssertEqual(UI.exclusions, 0)
        }
    }
    func testSettingsFeedbackEligibilityAndLegacyHookFallbackRemainScoped() {
        let context = Context(); let peer = Peer(2); peer.botInfo?.flags.insert(.canBeAddedToAttachMenu)
        context.engine.messages.add = .single(true)
        UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
        openWebBot(AttachMenuBot(peer: EnginePeer(peer), flags: [.showInSettingsDisclaimer]), context: context, analyticsContext: AnalyticsContext(excluded: true))
        UI.confirmed?(true); UI.confirmed?(true)
        XCTAssertEqual(UI.feedback, 1); XCTAssertEqual(UI.settingsTabs.count, 1)
        var fallback = 0
        SettingsNavigationHooks.shared.openWebBotWithContext = nil
        SettingsNavigationHooks.shared.openWebBot = { _, _ in fallback += 1; XCTAssertGreaterThan(UI.exclusions, 0) }
        SettingsNavigationHooks.shared.openWebBotObserved(context, AttachMenuBot(peer: EnginePeer(peer)), analyticsContext: AnalyticsContext(excluded: true))
        XCTAssertEqual(fallback, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    private func drainSettingsMain() {
        let done = expectation(description: "settings decision delivery")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}
extension BotTests {
    func joinContext() -> Context {
        let context = Context()
        context.engine.data.signal = .single(EnginePeer(Peer(2)))
        return context
    }
    func testJoinLegacyLookupAndOpenAreDeniedAndTerminalCancelsBeforeCloseAndFeedback() {
        let context = joinContext()
        UI.onJoinLookup = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onJoinOpen = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.joinOrigins.last??.isExcluded == true) }
        UI.onJoinFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
        openJoinChatBotWebView(context: context, botId: 2, url: "synthetic", queryId: 901, joinedPeerId: 3)
        XCTAssertEqual(UI.joinIds, [.webapp(901)])
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
        XCTAssertEqual(UI.joinCancelled, 1); XCTAssertEqual(UI.joinClosed, [.webapp(901)]); XCTAssertEqual(UI.joinSuccess, 1)
        XCTAssertEqual(UI.joinOrder, ["cancel", "close", "feedback"]); XCTAssertEqual(UI.exclusions, 0)
    }
    func testJoinIgnoresUnrelatedQueryAndWrongKnownDestination() {
        let context = joinContext()
        openJoinChatBotWebView(context: context, botId: 2, url: "synthetic", queryId: 901, joinedPeerId: 3, analyticsContext: AnalyticsContext(excluded: true))
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 902, result: .approved), .init(peerId: 4, queryId: 901, result: .approved)])
        XCTAssertEqual(UI.joinCancelled, 0); XCTAssertTrue(UI.joinClosed.isEmpty); XCTAssertEqual(UI.joinSuccess, 0)
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .queued)])
        XCTAssertEqual(UI.joinCancelled, 1); XCTAssertEqual(UI.joinClosed, [.webapp(901)]); XCTAssertEqual(UI.feedback, 1)
    }
    func testDeferredJoinUrlTightensDestinationAndCarriesOriginalScopeIntoNextStage() {
        let context = joinContext(); let origin = AnalyticsContext()
        var response: Subscriber<RequestWebViewResult, BackendError>?
        context.engine.messages.joinResult = Signal { response = $0; return EmptyDisposable }
        openJoinChatBotWebView(context: context, botId: 2, url: nil, queryId: 901, joinedPeerId: nil, analyticsContext: origin)
        XCTAssertEqual(context.engine.messages.joinQueries, [901])
        XCTAssertTrue(UI.joinTabs.isEmpty)
        UI.onJoinLookup = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onJoinOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
        context.account.stateManager.decisions.putNext([.init(peerId: -3, queryId: 901, result: .webView("synthetic-next"))])
        XCTAssertTrue(UI.joinTabs.isEmpty)
        response?.putNext(RequestWebViewResult(flags: [1, 2], queryId: 901, url: "initial", keepAliveSignal: .never()))
        response = nil
        XCTAssertEqual(context.engine.data.ids, [2]); XCTAssertEqual(UI.joinTabs.count, 1)
        XCTAssertTrue(UI.joinOrigins.last??.isExcluded == true)
        guard case let .straight(_, peerId, _, result) = UI.joinTabs[0] else { return XCTFail() }
        XCTAssertEqual(peerId, -3); XCTAssertEqual(result.url, "synthetic-next")
        XCTAssertEqual(result.flags, [1, 2]); XCTAssertEqual(result.queryId, 901); XCTAssertNotNil(result.keepAliveSignal)
        UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
        context.account.stateManager.decisions.putNext([.init(peerId: -3, queryId: 901, result: .declined)])
        XCTAssertEqual(UI.joinCancelled, 1); XCTAssertEqual(UI.missing, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testJoinUrlTransitionCancelsOldPendingOpenAndReusesQueryIdentity() {
        let context = joinContext(); let origin = AnalyticsContext()
        openJoinChatBotWebView(context: context, botId: 2, url: "first", queryId: 901, joinedPeerId: 3, analyticsContext: origin)
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .webView("second"))])
        XCTAssertEqual(UI.joinCancelled, 1); XCTAssertEqual(UI.joinIds, [.webapp(901), .webapp(901)])
        XCTAssertTrue(UI.joinOrigins.allSatisfy { $0?.scope === origin.scope })
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
        XCTAssertEqual(UI.joinCancelled, 2); XCTAssertEqual(UI.joinClosed, [.webapp(901), .webapp(901)])
    }
    func testJoinMissingMismatchedAndEmptyBotLookupDoNotCreatePendingOpen() {
        let peers: [Signal<EnginePeer?, NoError>] = [.single(nil), .single(EnginePeer(Peer(9))), .complete()]
        for (index, signal) in peers.enumerated() {
            let context = Context(); context.engine.data.signal = signal
            UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            openJoinChatBotWebView(context: context, botId: 2, url: "synthetic", queryId: 901, joinedPeerId: 3, analyticsContext: AnalyticsContext(excluded: true))
            XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.missing, index < 2 ? 1 : 0)
            XCTAssertEqual(UI.joinCancelled, 0); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testJoinRevokedOriginIsRecheckedForTerminalFeedbackWithoutNewGrant() {
        let context = joinContext(); let origin = AnalyticsContext()
        openJoinChatBotWebView(context: context, botId: 2, url: "synthetic", queryId: 901, joinedPeerId: 3, analyticsContext: origin)
        XCTAssertTrue(UI.joinOrigins.last??.scope === origin.scope)
        origin.scope?.valid = false
        UI.onJoinFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
        XCTAssertEqual(UI.joinSuccess, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testJoinLookupTakesOnlyFirstPeerAndAccountMismatchStaysDenied() {
        let context = Context(2); let origin = AnalyticsContext()
        var peers: Subscriber<EnginePeer?, NoError>?
        context.engine.data.signal = Signal { peers = $0; return EmptyDisposable }
        UI.onJoinOpen = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertNil(UI.joinOrigins.last??.scope) }
        openJoinChatBotWebView(context: context, botId: 2, url: "synthetic", queryId: 901, joinedPeerId: 3, analyticsContext: origin)
        peers?.putNext(EnginePeer(Peer(2))); peers?.putNext(EnginePeer(Peer(2))); peers = nil
        XCTAssertEqual(UI.joinTabs.count, 1)
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .queued)])
        XCTAssertEqual(UI.feedback, 1); XCTAssertEqual(UI.joinCancelled, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testJoinTerminalDuringLookupDisposesPendingWorkAndRejectsLatePeer() {
        let context = joinContext(); let state = BrowserStateContext.get(context)
        var peer: Subscriber<EnginePeer?, NoError>?
        var url: Subscriber<RequestWebViewResult, BackendError>?
        var disposed = 0
        context.engine.data.signal = Signal { peer = $0; return ActionDisposable { disposed += 1 } }
        context.engine.messages.joinResult = Signal { url = $0; return ActionDisposable { disposed += 1 } }
        openJoinChatBotWebView(context: context, botId: 2, url: nil, queryId: 901, joinedPeerId: 3, analyticsContext: AnalyticsContext())
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
        XCTAssertEqual(disposed, 2); XCTAssertTrue(state.joinChatOperations.isEmpty)
        peer?.putNext(EnginePeer(Peer(2)))
        url?.putNext(RequestWebViewResult())
        XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.joinSuccess, 1)
    }
    func testJoinSubscribesBeforeBotLookupStarts() {
        let context = joinContext()
        UI.onJoinLookup = {
            context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .queued)])
        }
        openJoinChatBotWebView(context: context, botId: 2, url: nil, queryId: 901, joinedPeerId: 3, analyticsContext: AnalyticsContext())
        XCTAssertEqual(UI.feedback, 1); XCTAssertTrue(UI.joinTabs.isEmpty)
        XCTAssertTrue(context.engine.messages.joinQueries.isEmpty)
        XCTAssertTrue(BrowserStateContext.get(context).joinChatOperations.isEmpty)
    }
    func testJoinPendingConsentCoalescesUrlsAndPreservesOriginalGrant() {
        let context = joinContext(); let origin = AnalyticsContext()
        UI.deferJoinOpen = true
        openJoinChatBotWebView(context: context, botId: 2, url: "initial", queryId: 901, joinedPeerId: 3, analyticsContext: origin)
        context.account.stateManager.decisions.putNext([
            .init(peerId: 3, queryId: 901, result: .webView("middle")),
            .init(peerId: 3, queryId: 901, result: .webView("latest"))
        ])
        XCTAssertEqual(UI.joinTabs.count, 1); XCTAssertEqual(UI.joinOpenCallbacks.count, 1)
        UI.joinOpenCallbacks[0](true)
        XCTAssertEqual(UI.joinTabs.count, 2); XCTAssertEqual(UI.joinCancelled, 1)
        guard case let .straight(_, _, _, result) = UI.joinTabs[1] else { return XCTFail() }
        XCTAssertEqual(result.url, "latest"); XCTAssertEqual(result.queryId, 901)
        XCTAssertTrue(UI.joinOrigins.allSatisfy { $0?.scope === origin.scope })
        UI.joinOpenCallbacks[1](true)
        XCTAssertEqual(UI.joinTabs.count, 2)
    }
    func testJoinTerminalBatchWinsOverUrlAndPendingConsent() {
        let context = joinContext(); UI.deferJoinOpen = true
        openJoinChatBotWebView(context: context, botId: 2, url: "initial", queryId: 901, joinedPeerId: 3, analyticsContext: AnalyticsContext(excluded: true))
        context.account.stateManager.decisions.putNext([
            .init(peerId: 3, queryId: 901, result: .webView("late")),
            .init(peerId: 3, queryId: 901, result: .approved),
            .init(peerId: 3, queryId: 901, result: .declined)
        ])
        UI.joinOpenCallbacks[0](true)
        XCTAssertEqual(UI.joinTabs.count, 1); XCTAssertEqual(UI.joinSuccess, 1); XCTAssertEqual(UI.missing, 0)
        XCTAssertEqual(UI.joinCancelled, 1); XCTAssertTrue(BrowserStateContext.get(context).joinChatOperations.isEmpty)
    }
    func testJoinConsentFailureRemovesOperationAndIgnoresLateDecisions() {
        let context = joinContext(); UI.deferJoinOpen = true
        openJoinChatBotWebView(context: context, botId: 2, url: "initial", queryId: 901, joinedPeerId: 3)
        UI.joinOpenCallbacks[0](false)
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
        XCTAssertTrue(BrowserStateContext.get(context).joinChatOperations.isEmpty)
        XCTAssertEqual(UI.joinSuccess, 0); XCTAssertEqual(UI.joinCancelled, 1)
    }
    func testJoinUserCloseAndAccountCleanupStopPendingRequests() {
        for accountClose in [false, true] {
            let context = joinContext(); let state = BrowserStateContext.get(context)
            var response: Subscriber<RequestWebViewResult, BackendError>?
            var disposed = 0
            context.engine.messages.joinResult = Signal { response = $0; return ActionDisposable { disposed += 1 } }
            openJoinChatBotWebView(context: context, botId: 2, url: nil, queryId: 901, joinedPeerId: 3)
            if accountClose { state.closeAccountForTest() } else { state.cancelJoinChatOperation(uniqueId: .webapp(901)) }
            response?.putNext(RequestWebViewResult())
            context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
            XCTAssertEqual(disposed, 1); XCTAssertTrue(state.joinChatOperations.isEmpty)
            XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.joinSuccess, 0); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testJoinReplacementCancelsOnlySameQueryAndTerminalLeavesOtherQueryActive() {
        let context = joinContext(); let state = BrowserStateContext.get(context)
        UI.deferJoinOpen = true
        for query: Int64 in [901, 902, 901] {
            openJoinChatBotWebView(context: context, botId: 2, url: "initial", queryId: query, joinedPeerId: 3)
        }
        XCTAssertEqual(state.joinChatOperations.count, 2); XCTAssertEqual(UI.joinCancelled, 1)
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .queued)])
        XCTAssertEqual(state.joinChatOperations.count, 1); XCTAssertNotNil(state.joinChatOperations[.webapp(902)])
        UI.joinOpenCallbacks[0](true); UI.joinOpenCallbacks[2](true)
        XCTAssertEqual(UI.joinTabs.count, 3); XCTAssertEqual(UI.feedback, 1)
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 902, result: .approved)])
        XCTAssertTrue(state.joinChatOperations.isEmpty); XCTAssertEqual(UI.joinSuccess, 1)
    }
    func testJoinEmptyAndFailedUrlRequestReleaseOperationWithoutOpening() {
        let signals: [Signal<RequestWebViewResult, BackendError>] = [.complete(), .fail(.generic)]
        for (index, signal) in signals.enumerated() {
            let context = joinContext(); context.engine.messages.joinResult = signal
            openJoinChatBotWebView(context: context, botId: 2, url: nil, queryId: 901, joinedPeerId: 3)
            XCTAssertTrue(BrowserStateContext.get(context).joinChatOperations.isEmpty)
            XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.joinSuccess, 0)
            XCTAssertEqual(UI.missing, index); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }

    func testJoinUnknownDestinationIsDeniedBeforeLookupAndInitialUrlDelivery() {
        let context = joinContext(); let origin = AnalyticsContext()
        UI.onJoinLookup = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onJoinRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onJoinOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
        openJoinChatBotWebView(context: context, botId: 2, url: nil, queryId: 901, joinedPeerId: nil, analyticsContext: origin)
        XCTAssertTrue(UI.joinOrigins.last??.isExcluded == true)
        XCTAssertNil(UI.joinOrigins.last??.scope)
        context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .webView("next"))])
        XCTAssertTrue(UI.joinOrigins.last??.isExcluded == true)
        XCTAssertNil(UI.joinOrigins.last??.scope)
    }
    func testJoinDecisionDuringUrlRequestStartsNoBrowserAndCompletesOnce() {
        let context = joinContext()
        UI.onJoinRequest = {
            context.account.stateManager.decisions.putNext([.init(peerId: 3, queryId: 901, result: .approved)])
        }
        openJoinChatBotWebView(context: context, botId: 2, url: nil, queryId: 901, joinedPeerId: 3, analyticsContext: AnalyticsContext())
        XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.joinSuccess, 1)
        XCTAssertTrue(BrowserStateContext.get(context).joinChatOperations.isEmpty)
    }

    func testBothInstalledJoinHooksPreserveOrdinaryGrantAndDestination() {
        for feature in [false, true] {
            let context = joinContext(); let origin = AnalyticsContext()
            if feature {
                FeatureNavigationHooks.shared.openJoinChatBotWebViewObserved(context, 2, "initial", 901, 3, analyticsContext: origin)
            } else {
                ChatNavigationHooks.shared.openJoinChatBotWebViewObserved(context, 2, "initial", 901, 3, analyticsContext: origin)
            }
            XCTAssertEqual(UI.joinIds, [.webapp(901)]); XCTAssertTrue(UI.joinOrigins.last??.scope === origin.scope)
            guard case let .straight(_, peerId, _, _) = UI.joinTabs[0] else { return XCTFail() }
            XCTAssertEqual(peerId, 3)
            UI.reset()
        }
    }
    func testBothJoinHooksDenySecretUnknownForeignAndRevokedOriginsBeforeLegacyFallback() {
        for feature in [false, true] {
            let revoked = AnalyticsContext(); revoked.scope?.valid = false
            let cases: [(Context, PeerId, PeerId?, AnalyticsContext)] = [
                (Context(), 2, -3, AnalyticsContext()),
                (Context(), -2, 3, AnalyticsContext()),
                (Context(), 2, nil, AnalyticsContext()),
                (Context(2), 2, 3, AnalyticsContext()),
                (Context(), 2, 3, revoked),
                (Context(), 2, 3, AnalyticsContext(excluded: true))
            ]
            var calls = 0
            let fallback: (any AccountContextProtocol, PeerId, String?, Int64, PeerId?) -> Void = { _, _, _, _, _ in
                calls += 1; XCTAssertGreaterThan(UI.exclusions, 0)
            }
            if feature {
                FeatureNavigationHooks.shared.openJoinChatBotWebViewWithContext = nil
                FeatureNavigationHooks.shared.openJoinChatBotWebView = fallback
            } else {
                ChatNavigationHooks.shared.openJoinChatBotWebViewWithContext = nil
                ChatNavigationHooks.shared.openJoinChatBotWebView = fallback
            }
            for (context, botId, peerId, origin) in cases {
                if feature {
                    FeatureNavigationHooks.shared.openJoinChatBotWebViewObserved(context, botId, nil, 901, peerId, analyticsContext: origin)
                } else {
                    ChatNavigationHooks.shared.openJoinChatBotWebViewObserved(context, botId, nil, 901, peerId, analyticsContext: origin)
                }
            }
            XCTAssertEqual(calls, cases.count); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testChatJoinCapturesBeforeRequestAndKeepsOriginalGrantAfterDelayedResult() {
        let context = joinContext(); let origin = AnalyticsContext()
        let controller = ChannelController(context, origin)
        var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
        var disposed = 0
        context.engine.peers.signal = Signal { response = $0; return ActionDisposable { disposed += 1 } }
        controller.handler()()
        controller.chatInteraction.origin = AnalyticsContext(excluded: true)
        response?.putNext(.webView(JoinView(botPeer: EnginePeer(Peer(2)), url: "initial", queryId: 901)))
        response?.putNext(.joined)
        XCTAssertEqual(context.engine.peers.requested, [3]); XCTAssertEqual(disposed, 1)
        XCTAssertTrue(UI.joinOrigins.last??.scope === origin.scope)
        XCTAssertEqual(UI.joinTabs.count, 1); XCTAssertEqual(UI.joinSuccess, 0)
    }
    func testChatJoinSecretOriginCoversRequestProgressDelayedWebviewAndDisposal() {
        let context = joinContext(); let origin = AnalyticsContext(excluded: true)
        let controller = ChannelController(context, origin)
        var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
        UI.onChannelRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onProgress = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onJoinLookup = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onJoinOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
        context.engine.peers.signal = Signal { response = $0; return ActionDisposable { XCTAssertGreaterThan(UI.exclusions, 0) } }
        controller.handler()()
        XCTAssertGreaterThan(UI.exclusions, 0)
        controller.chatInteraction.origin = AnalyticsContext()
        response?.putNext(.webView(JoinView(botPeer: EnginePeer(Peer(2)), url: "initial", queryId: 901)))
        XCTAssertTrue(UI.joinOrigins.last??.isExcluded == true)
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testChatJoinRevocationAndAccountMismatchCannotAcquireFreshGrant() {
        for foreign in [false, true] {
            let context = Context(foreign ? 2 : 1); context.engine.data.signal = .single(EnginePeer(Peer(2)))
            let origin = AnalyticsContext()
            var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
            context.engine.peers.signal = Signal { response = $0; return EmptyDisposable }
            joinChannel(context: context, peerId: 3, analyticsContext: origin)
            origin.scope?.valid = false
            UI.onJoinOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
            response?.putNext(.webView(JoinView(botPeer: EnginePeer(Peer(2)), url: "initial", queryId: 901)))
            XCTAssertEqual(UI.joinTabs.count, 1)
            if foreign { XCTAssertNil(UI.joinOrigins.last??.scope) }
            else { XCTAssertTrue(UI.joinOrigins.last??.scope === origin.scope) }
            UI.reset()
        }
    }
    func testLegacyChannelJoinAndErrorFeedbackRemainDeniedWithoutInventedSuccess() {
        let errors: [JoinChannelError] = [.generic, .tooMuchJoined, .tooMuchUsers, .inviteRequestSent]
        for error in errors {
            let context = Context(); context.engine.peers.signal = .fail(error)
            var inactive = 0
            UI.onInactiveChannels = { inactive += 1; XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onChannelRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            joinChannel(context: context, peerId: 3)
            XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.joinSuccess, 0)
            XCTAssertEqual(UI.missing + UI.feedback + inactive, 1); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testChatJoinDoesNotStartAfterOwnerReleaseAndEmptyResultCreatesNoOutcome() {
        let context = Context()
        var controller: ChannelController? = ChannelController(context, AnalyticsContext())
        let handler = controller!.handler()
        controller = nil; handler()
        XCTAssertTrue(context.engine.peers.requested.isEmpty)
        joinChannel(context: context, peerId: 3)
        XCTAssertEqual(context.engine.peers.requested, [3])
        XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.joinSuccess + UI.feedback + UI.missing, 0)
        XCTAssertEqual(UI.exclusions, 0)
    }

    func testChannelJoinDelayedSuccessAndFailureFeedbackKeepPrivateOrigin() {
        for succeeds in [true, false] {
            let context = Context()
            var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
            context.engine.peers.signal = Signal { response = $0; return EmptyDisposable }
            UI.onJoinFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            joinChannel(context: context, peerId: 3, analyticsContext: AnalyticsContext(excluded: true))
            XCTAssertGreaterThan(UI.exclusions, 0)
            if succeeds { response?.putNext(.joined); response?.putNext(.joined) }
            else { response?.putError(.generic) }
            XCTAssertEqual(UI.joinSuccess, succeeds ? 1 : 0); XCTAssertEqual(UI.missing, succeeds ? 0 : 1)
            XCTAssertTrue(UI.joinTabs.isEmpty); XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }

    func testTooManyChatsPassesOriginalOriginThroughInstalledRecoveryHookAfterRequest() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
        context.engine.peers.signal = Signal { response = $0; return EmptyDisposable }
        UI.onInactiveChannels = { XCTAssertGreaterThan(UI.exclusions, 0) }
        joinChannel(context: context, peerId: 3, analyticsContext: origin)
        response?.putError(.tooMuchJoined)
        XCTAssertEqual(UI.inactiveOrigins.count, 1); XCTAssertTrue(UI.inactiveOrigins[0]?.isExcluded == true)
        XCTAssertEqual(UI.exclusions, 0)
    }

    func newsView(_ context: Context, origin: AnalyticsContext = AnalyticsContext(), member: Bool = false, inNews: Bool = true, peerId: PeerId = 3) -> NewsView {
        let interaction = IncomingAction(context, origin); UI.newsInteractions.append(interaction)
        let view = NewsView()
        view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: peerId, isMember: member, isInNews: inNews), chatInteraction: interaction)
        return view
    }
    func drainNewsMenu() {
        let ready = expectation(description: "news menu delayed action")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ready.fulfill() }
        wait(for: [ready], timeout: 2)
    }
    func testNewsMenuOwnsPrivateExclusionUntilCloseAndThroughDelayedJoin() {
        let context = joinContext(); let view = newsView(context, origin: AnalyticsContext(excluded: true))
        UI.onNewsMenuInit = { XCTAssertGreaterThan(UI.exclusions, 0) }
        let menu = view.makeMenu()!
        XCTAssertTrue(menu.delegate === menu); XCTAssertGreaterThan(UI.exclusions, 0)
        menu.onShow(menu)
        UI.onChannelRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onProgress = { XCTAssertGreaterThan(UI.exclusions, 0) }
        context.engine.peers.signal = .single(.webView(JoinView(botPeer: EnginePeer(Peer(2)), url: "initial", queryId: 901)))
        menu.items[0].handler(); menu.onClose()
        XCTAssertGreaterThan(UI.exclusions, 0)
        drainNewsMenu()
        XCTAssertEqual(context.engine.peers.requested, [3]); XCTAssertTrue(UI.joinOrigins.last??.isExcluded == true)
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testNewsMenuCapturesOriginalGrantAndConsumesDuplicateOrDifferentItemsOnce() {
        let context = joinContext(); let origin = AnalyticsContext(); let view = newsView(context, origin: origin)
        context.engine.peers.signal = .single(.webView(JoinView(botPeer: EnginePeer(Peer(2)), url: "initial", queryId: 901)))
        let menu = view.makeMenu()!
        view.chatInteraction?.origin = AnalyticsContext(excluded: true)
        menu.items[0].handler(); menu.items[0].handler(); menu.items[1].handler(); menu.onClose()
        drainNewsMenu()
        XCTAssertEqual(context.engine.peers.requested, [3]); XCTAssertTrue(context.engine.peers.effects.isEmpty)
        XCTAssertTrue(UI.joinOrigins.last??.scope === origin.scope)
    }
    func testNewsRebindingBeforeOrAfterMenuSelectionRejectsOldTargetEvenIfReturned() {
        for selectedFirst in [false, true] {
            let context = Context(); let view = newsView(context, origin: AnalyticsContext(excluded: true))
            let original = view.chatInteraction!
            let menu = view.makeMenu()!
            if selectedFirst { menu.items[0].handler() }
            view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: 4, isInNews: true), chatInteraction: original)
            view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: 3, isInNews: true), chatInteraction: original)
            if !selectedFirst { menu.items[0].handler() }
            menu.onClose(); drainNewsMenu()
            XCTAssertTrue(context.engine.peers.requested.isEmpty); XCTAssertTrue(context.engine.peers.effects.isEmpty)
            XCTAssertEqual(UI.exclusions, 0); UI.reset()
        }
    }
    func testNewsMenuRejectsChangedModeArchiveAndThreadWhileWaiting() {
        for change in 0..<3 {
            let context = Context(); let view = newsView(context)
            let menu = view.makeMenu()!
            menu.items[0].handler()
            switch change {
            case 0: view.data?.isMember = true
            case 1: view.isArchived = true
            default: view.chatInteraction?.presentation.chatLocation.threadId = 99
            }
            menu.onClose(); drainNewsMenu()
            XCTAssertTrue(context.engine.peers.requested.isEmpty); UI.reset()
        }
    }
    func testNewsAccountReplacementCancelsPendingJoinAndIgnoresLateFeedback() {
        let context = Context(); let view = newsView(context, origin: AnalyticsContext(excluded: true), inNews: false)
        var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
        var disposed = 0
        context.engine.peers.signal = Signal { response = $0; return ActionDisposable { disposed += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        view.addToNews()
        XCTAssertTrue(view.isAddingToNews)
        let replacement = IncomingAction(Context(2), AnalyticsContext(2)); UI.newsInteractions.append(replacement)
        view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: 3), chatInteraction: replacement)
        response?.putNext(.joined); response?.putError(.tooMuchJoined)
        XCTAssertEqual(disposed, 1); XCTAssertFalse(view.isAddingToNews); XCTAssertNil(view.observedPeerId)
        XCTAssertEqual(UI.feedback, 0); XCTAssertTrue(UI.inactiveOrigins.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testDirectNewsJoinTakesOneOutcomeAndPrivateErrorUsesRecoveryCompanion() {
        let context = Context(); let view = newsView(context, origin: AnalyticsContext(excluded: true), inNews: false)
        var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
        context.engine.peers.signal = Signal { response = $0; return EmptyDisposable }
        UI.onChannelRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onInactiveChannels = { XCTAssertGreaterThan(UI.exclusions, 0) }
        view.addToNews(); view.addToNews()
        XCTAssertEqual(context.engine.peers.requested, [3]); XCTAssertEqual(context.engine.peers.forNews, [true])
        response?.putError(.tooMuchJoined)
        XCTAssertFalse(view.isAddingToNews); XCTAssertTrue(UI.inactiveOrigins.last??.isExcluded == true)
        context.engine.peers.signal = Signal { subscriber in subscriber.putNext(.joined); subscriber.putNext(.joined); return EmptyDisposable }
        view.addToNews()
        XCTAssertEqual(UI.feedback, 1)
    }
    func testEmptyNewsJoinClearsPendingStateWithoutSuccessAndCanRetry() {
        let context = Context(); let view = newsView(context, inNews: false)
        view.addToNews(); XCTAssertFalse(view.isAddingToNews)
        view.addToNews(); XCTAssertFalse(view.isAddingToNews)
        XCTAssertEqual(context.engine.peers.requested, [3, 3]); XCTAssertEqual(UI.feedback, 0)
    }
    func testNewsAddToChatsMutesCapturedPeerOnceAfterJoinAndRejectsStaleResult() {
        let context = Context(); let view = newsView(context)
        var response: Subscriber<ChannelJoinOutcome, JoinChannelError>?
        context.engine.peers.signal = Signal { response = $0; return EmptyDisposable }
        let menu = view.makeMenu()!; menu.items[0].handler(); menu.onClose(); drainNewsMenu()
        response?.putNext(.joined); response?.putNext(.joined)
        XCTAssertEqual(context.engine.peers.effects, ["mute"]); XCTAssertEqual(context.engine.peers.effectIds, [3]); XCTAssertEqual(UI.feedback, 1)
        let next = view.makeMenu()!; next.items[0].handler(); next.onClose(); drainNewsMenu()
        view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: 4), chatInteraction: view.chatInteraction!)
        response?.putNext(.joined)
        XCTAssertEqual(context.engine.peers.effects, ["mute"]); XCTAssertEqual(UI.feedback, 1)
    }
    func testNewsMenuMuteArchiveAndRemovalRetainPrivateOriginAcrossDelay() {
        for item in 0..<3 {
            let context = Context(); let view = newsView(context, origin: AnalyticsContext(excluded: true), member: true)
            let menu = view.makeMenu()!
            UI.onNewsEffect = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            menu.items[item].handler(); menu.onClose(); drainNewsMenu()
            XCTAssertEqual(context.engine.peers.effects, [["toggle"], ["archive"], ["remove"]][item])
            XCTAssertEqual(context.engine.peers.effectIds, [3]); XCTAssertEqual(UI.feedback, item == 2 ? 1 : 0)
            UI.reset()
        }
    }
    func testNewsRemovalCompletionAfterRebindingDoesNotPresentOldFeedback() {
        let context = Context(); let view = newsView(context, origin: AnalyticsContext(excluded: true), member: true)
        var result: Subscriber<Void, NoError>?
        context.engine.peers.effect = Signal { result = $0; return EmptyDisposable }
        let menu = view.makeMenu()!; menu.items[2].handler(); menu.onClose(); drainNewsMenu()
        view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: 4), chatInteraction: view.chatInteraction!)
        result?.putCompletion()
        XCTAssertEqual(UI.feedback, 0); XCTAssertEqual(UI.exclusions, 0)
    }
    func testNewsMenuOwnerReleaseRejectsRetainedHandlersAndPendingAction() {
        let context = Context(); var view: NewsView? = newsView(context, origin: AnalyticsContext(excluded: true))
        let menu = view!.makeMenu()!; menu.items[0].handler()
        view = nil; menu.items[0].handler(); menu.onClose(); drainNewsMenu()
        XCTAssertTrue(context.engine.peers.requested.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testNewsProgressRebindingPreventsSubscriptionToOldJoin() {
        let context = Context(); let view = newsView(context)
        var subscribed = 0
        context.engine.peers.signal = Signal { _ in subscribed += 1; return EmptyDisposable }
        UI.onProgress = { view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: 4), chatInteraction: view.chatInteraction!) }
        let menu = view.makeMenu()!; menu.items[0].handler(); menu.onClose(); drainNewsMenu()
        XCTAssertEqual(subscribed, 0)
        UI.onProgress = nil
    }

    func testNewsRemovalAndUnarchiveUseCapturedTargetUnderPrivateContext() {
        for member in [false, true] {
            let context = Context(); let view = newsView(context, origin: AnalyticsContext(excluded: true), member: member)
            view.isArchived = true
            UI.onNewsEffect = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            let menu = view.makeMenu()!; menu.items[1].handler(); menu.onClose(); drainNewsMenu()
            XCTAssertEqual(context.engine.peers.effects, [member ? "unarchive" : "remove"])
            XCTAssertEqual(context.engine.peers.effectIds, [3]); XCTAssertEqual(UI.feedback, member ? 0 : 1)
            UI.reset()
        }
    }
    func testNewsJoinRevalidatesTargetAfterOptimisticUpdateBeforeSubscribing() {
        let context = Context(); let view = newsView(context, inNews: false)
        UI.onNewsUpdate = { view.bindNewsTarget(data: ChatState.NewsChannelData(peerId: 4), chatInteraction: view.chatInteraction!) }
        view.addToNews()
        XCTAssertTrue(context.engine.peers.requested.isEmpty); XCTAssertFalse(view.isAddingToNews)
        UI.onNewsUpdate = nil
    }
    func testNewsMenuRevocationBeforeDelayedRequestCannotRefreshItsGrant() {
        let context = joinContext(); let origin = AnalyticsContext(); let view = newsView(context, origin: origin)
        context.engine.peers.signal = .single(.webView(JoinView(botPeer: EnginePeer(Peer(2)), url: "initial", queryId: 901)))
        let menu = view.makeMenu()!; menu.items[0].handler(); menu.onClose()
        origin.scope?.valid = false
        UI.onChannelRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onJoinOpen = { XCTAssertGreaterThan(UI.exclusions, 0) }
        drainNewsMenu()
        XCTAssertEqual(UI.joinTabs.count, 1); XCTAssertTrue(UI.joinOrigins.last??.scope === origin.scope)
    }

}
