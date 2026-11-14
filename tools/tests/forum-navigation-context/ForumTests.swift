import Foundation
import ObjectiveC
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
typealias MessageId = Int64
final class Scope { var valid = true }
final class AnalyticsContext {
    let isExcluded: Bool
    let owner: Int
    let scope: Scope?
    init(_ owner: Int = 1, excluded: Bool = false, scope: Scope? = Scope()) { self.owner = owner; isExcluded = excluded; self.scope = excluded ? nil : scope }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(self) }
__SIGNAL__
}
final class AnalyticsPresentation {
    let excluded: Bool
    var active = true
    init(_ context: AnalyticsContext) { excluded = context.isExcluded || context.scope?.valid != true; if excluded { State.exclusions += 1 } }
    func end() { guard active else { return }; active = false; if excluded { State.exclusions -= 1 } }
    deinit { end() }
}
final class Analytics {
    static let shared = Analytics()
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext) -> AnalyticsContext {
        AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: engine.owner == inherited.owner ? inherited.scope : nil)
    }
}
protocol AccountContextProtocol: AnyObject {
    var engine: Engine { get }
    var account: Account { get }
    var bindings: Bindings { get }
    var layout: Layout { get }
    var peerId: PeerId { get }
}
extension AccountContextProtocol { var concrete: Context { self as! Context } }
enum Layout { case single, dual, minimisize }
final class Context: AccountContextProtocol {
    let engine: Engine
    let account = Account()
    let bindings = Bindings()
    var layout = Layout.dual
    var peerId: PeerId = 1
    init(_ owner: Int = 1) { engine = Engine(owner) }
}
final class Account { let postbox = NSObject() }
final class Bindings {
    let root = NavigationViewController()
    func rootNavigation() -> NavigationViewController { root }
}
class ViewController: NSObject {
    var analyticsContext: AnalyticsContext?
    let ready = Promise<Bool>(true)
    let view = View()
    var scrolled = 0
    func isLoaded() -> Bool { true }
    func scrollup() { State.onAction?(); scrolled += 1 }
}
final class View { func shake(beep: Bool) { State.onAction?(); State.shakes += 1 } }
final class NavigationViewController {
    var controllers: [ViewController] = []
    var controller: ViewController? { controllers.last }
    var emptied = 0
    func push(_ controller: ViewController) { State.onPush?(controller); controllers.append(controller) }
    func gotoEmpty() { State.onAction?(); emptied += 1 }
}
protocol ChatListControllerKind: ViewController { var mode: PeerListMode { get } }
final class ListController: ViewController, ChatListControllerKind {
    let mode: PeerListMode
    init(_ mode: PeerListMode) { self.mode = mode; super.init() }
}
enum GroupId { case archive, root }
enum PeerListMode {
    case forum(PeerId, Bool, Bool), savedMessagesChats(peerId: PeerId), normal(GroupId)
    var isForumLike: Bool { switch self { case .forum, .savedMessagesChats: return true; default: return false } }
    var groupId: GroupId { if case let .normal(id) = self { return id }; return .root }
}
protocol ChatListChatController: ViewController {
    var chatLocation: ChatLocation { get }
    var chatInteraction: ChatInteraction { get }
    func inheritAnalyticsContext(_ context: AnalyticsContext)
}
final class ChatController: ViewController, ChatListChatController {
    let chatLocation: ChatLocation
    let chatInteraction = ChatInteraction()
    var presentation: AnalyticsPresentation?
    init(_ location: ChatLocation) { chatLocation = location; super.init() }
    func inheritAnalyticsContext(_ context: AnalyticsContext) {
        if let current = analyticsContext, current.isExcluded || !context.isExcluded { return }
        let presentation = context.beginPresentation()
        analyticsContext = context
        self.presentation = presentation
    }
}
final class ChatInteraction {
    var focuses = 0
    var actions = 0
    func focusMessageId(_ first: MessageId?, _ target: ChatFocusTarget, _ alignment: Alignment) { State.onAction?(); focuses += 1 }
    func invokeInitialAction(animated: Bool, action: ChatInitialAction) { State.onAction?(); actions += 1 }
}
enum Alignment { case CenterEmpty }
struct ChatInitialAction {}
struct ChatFocusTarget { var messageId: MessageId?; var string: String? = nil }
struct ChatLocationContextHolder {}
enum ViewControllerStyle { case push }
struct ThreadMessage { var peerId: PeerId; var threadId: Int64 }
enum ChatLocation {
    case peer(PeerId), thread(ThreadMessage), saved(PeerId, Int64)
    static func makeSaved(_ parent: PeerId, peerId: PeerId, isMonoforum: Bool) -> ChatLocation { .saved(parent, peerId) }
    var peerId: PeerId { switch self { case let .peer(id): return id; case let .thread(message): return message.peerId; case let .saved(id, _): return id } }
    var threadId: Int64? { switch self { case .peer: return nil; case let .thread(message): return message.threadId; case let .saved(_, thread): return thread } }
}
enum ThreadMode { case topic(origin: MessageId) }
enum ChatMode { case history, thread(mode: ThreadMode) }
struct ThreadInfo { let message: ThreadMessage; var contextHolder: Atomic<ChatLocationContextHolder?>? = nil }
enum FetchChannelReplyThreadMessageError: Error { case generic }
enum Subject { case groupMessage(MessageId) }
func makeThreadIdMessageId(peerId: PeerId, threadId: Int64) -> MessageId { threadId }
func fetchAndPreloadReplyThreadInfo(context: any AccountContextProtocol, subject: Subject, preload: Bool) -> Signal<ThreadInfo, FetchChannelReplyThreadMessageError> { State.fetches += 1; return State.thread }
final class CachedChannelData { let viewForumAsMessages: Known; init(_ value: Bool?) { viewForumAsMessages = Known(knownValue: value) } }
struct Known { let knownValue: Bool? }
struct Peer { var displayForumAsTabs: Bool? }
struct EnginePeer { let peer: Peer; func _asPeer() -> Peer { peer } }
func getCachedDataView(peerId: PeerId, postbox: NSObject) -> Signal<Any?, NoError> { State.cached }
enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct Peer { let id: PeerId } } } } }
final class Engine {
    let owner: Int
    let data = DataEngine()
    let peers = PeersEngine()
    init(_ owner: Int) { self.owner = owner }
}
final class DataEngine { func get(_ item: TelegramEngine.EngineData.Item.Peer.Peer) -> Signal<EnginePeer?, NoError> { State.peer } }
final class PeersEngine { func updateForumViewAsMessages(peerId: PeerId, value: Bool) -> Signal<Never, NoError> { State.updates += 1; return .complete() } }
final class ChatListUIHooks {
    static var shared = ChatListUIHooks()
    var navigateToChatWithCallback: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, ChatInitialAction?, Atomic<ChatLocationContextHolder?>?, Bool, ViewControllerStyle?, @escaping (ViewController) -> Void) -> Void = { navigation, _, location, _, _, _, _, _, _, callback in
        State.legacy += 1
        let controller = ChatController(location)
        navigation?.push(controller)
        callback(controller)
    }
__HOOK__
    func mainEffectiveNavigation(_ context: any AccountContextProtocol) -> NavigationViewController { State.listNavigation }
    func makeChatListController(_ context: any AccountContextProtocol, _ modal: Bool, _ mode: PeerListMode) -> ViewController { State.onConstruction?(); return ListController(mode) }
}
__ORIGIN__
struct ForumUI {
__FORUM__
}
func installContextHook(_ hooks: ChatListUIHooks) {
__INSTALL__
}
func navigateToChat(navigation: NavigationViewController?, context: Context, chatLocation: ChatLocation, mode: ChatMode, focusTarget: ChatFocusTarget?, initialAction: ChatInitialAction?, chatLocationContextHolder: Atomic<ChatLocationContextHolder?>?, additional: Bool, navigationStyle: ViewControllerStyle?, callback: @escaping (ViewController) -> Void, analyticsContext: AnalyticsContext) {
    State.navigations += 1
    State.onNavigation?(analyticsContext)
    let controller = ChatController(chatLocation)
    controller.inheritAnalyticsContext(analyticsContext)
    navigation?.push(controller)
    callback(controller)
}

enum State {
    static var exclusions = 0
    static var listNavigation = NavigationViewController()
    static var cached: Signal<Any?, NoError> = .single(CachedChannelData(false))
    static var peer: Signal<EnginePeer?, NoError> = .single(EnginePeer(peer: Peer(displayForumAsTabs: false)))
    static var thread: Signal<ThreadInfo, FetchChannelReplyThreadMessageError> = .complete()
    static var fetches = 0
    static var updates = 0
    static var legacy = 0
    static var shakes = 0
    static var navigations = 0
    static var onAction: (() -> Void)?
    static var onPush: ((ViewController) -> Void)?
    static var onConstruction: (() -> Void)?
    static var onNavigation: ((AnalyticsContext) -> Void)?
    static func reset() {
        listNavigation.controllers.removeAll()
        onAction = nil; onPush = nil; onConstruction = nil; onNavigation = nil
        cached = .single(CachedChannelData(false)); peer = .single(EnginePeer(peer: Peer(displayForumAsTabs: false))); thread = .complete()
        fetches = 0; updates = 0; legacy = 0; shakes = 0; navigations = 0
        ChatListUIHooks.shared = ChatListUIHooks()
        installContextHook(ChatListUIHooks.shared)
    }
}
final class ForumTests: XCTestCase {
    override func setUp() { State.reset(); XCTAssertEqual(State.exclusions, 0) }
    override func tearDown() { State.reset(); XCTAssertEqual(State.exclusions, 0) }
    func testDelayedListLookupProtectsConstructionPushAndIndependentChildLifetime() {
        let context = Context()
        let origin = AnalyticsContext(excluded: true)
        let pipe = ValuePipe<Any?>()
        State.cached = pipe.signal()
        State.onConstruction = { XCTAssertGreaterThan(State.exclusions, 0) }
        State.onPush = { XCTAssertTrue($0.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(State.exclusions, 0) }
        ForumUI.open(2, addition: true, context: context, analyticsContext: origin)
        XCTAssertGreaterThan(State.exclusions, 0)
        pipe.putNext(CachedChannelData(false))
        pipe.putNext(CachedChannelData(false))
        XCTAssertEqual(State.listNavigation.controllers.count, 1)
        XCTAssertGreaterThan(State.exclusions, 0)
        State.listNavigation.controllers.removeAll()
        XCTAssertEqual(State.exclusions, 0)
    }
    func testReusedListIsBoundBeforeActionAndCannotBeRelaxedByOrdinaryOrigin() {
        let context = Context()
        let list = ListController(.forum(2, false, false))
        State.listNavigation.controllers = [list]
        State.onAction = { XCTAssertTrue(list.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(State.exclusions, 0) }
        ForumUI.open(2, addition: false, context: context, analyticsContext: AnalyticsContext(excluded: true))
        ForumUI.open(2, addition: false, context: context, analyticsContext: AnalyticsContext())
        XCTAssertEqual(State.shakes, 2)
        XCTAssertEqual(State.listNavigation.controllers.count, 1)
    }
    func testReusedTopicBindsBeforeFocusAndInitialAction() {
        let context = Context()
        let chat = ChatController(.thread(ThreadMessage(peerId: 2, threadId: 7)))
        context.bindings.root.controllers = [chat]
        State.onAction = { XCTAssertTrue(chat.analyticsContext?.isExcluded == true); XCTAssertGreaterThan(State.exclusions, 0) }
        let result = ForumUI.openTopic(7, peerId: 2, context: context, messageId: 8, initialAction: ChatInitialAction(), analyticsContext: AnalyticsContext(excluded: true))
        var values: [Bool] = []
        let d = result.start(next: { values.append($0); XCTAssertGreaterThan(State.exclusions, 0) })
        XCTAssertEqual(values, [true]); XCTAssertEqual(chat.chatInteraction.focuses, 1); XCTAssertEqual(chat.chatInteraction.actions, 1)
        XCTAssertEqual(State.fetches, 0); XCTAssertEqual(State.updates, 0)
        d.dispose()
    }
    func testDelayedThreadResultKeepsOriginAndNavigatesOnce() {
        let context = Context()
        var receiver: Subscriber<ThreadInfo, FetchChannelReplyThreadMessageError>?
        State.thread = Signal { receiver = $0; return EmptyDisposable }
        State.onNavigation = { XCTAssertTrue($0.isExcluded); XCTAssertGreaterThan(State.exclusions, 0) }
        let result = ForumUI.openTopic(7, peerId: 2, context: context, analyticsContext: AnalyticsContext(excluded: true))
        var ready: [Bool] = []
        let d = result.start(next: { ready.append($0) })
        XCTAssertGreaterThan(State.exclusions, 0)
        receiver?.putNext(ThreadInfo(message: ThreadMessage(peerId: 2, threadId: 7)))
        receiver?.putNext(ThreadInfo(message: ThreadMessage(peerId: 2, threadId: 8)))
        XCTAssertEqual(State.navigations, 1); XCTAssertEqual(ready, [true]); XCTAssertEqual(context.bindings.root.controller.flatMap { ($0 as? ChatController)?.chatLocation.threadId }, 7)
        d.dispose(); context.bindings.root.controllers.removeAll(); receiver = nil
        XCTAssertEqual(State.exclusions, 0)
    }
    func testThreadFailureAndEmptyCompletionResolveWithoutNavigation() {
        for signal: Signal<ThreadInfo, FetchChannelReplyThreadMessageError> in [.fail(.generic), .complete()] {
            let context = Context(); State.thread = signal
            var values: [Bool] = []
            let d = ForumUI.openTopic(7, peerId: 2, context: context, analyticsContext: AnalyticsContext(excluded: true)).start(next: { values.append($0); XCTAssertGreaterThan(State.exclusions, 0) })
            XCTAssertEqual(values, [false]); XCTAssertEqual(State.navigations, 0)
            d.dispose(); XCTAssertEqual(State.exclusions, 0)
        }
    }
    func testMonoforumSkipsThreadFetchAndBindsBeforePush() {
        let context = Context()
        State.onPush = { XCTAssertTrue($0.analyticsContext?.isExcluded == true) }
        let d = ForumUI.openTopic(7, peerId: 2, context: context, isMonoforum: true, analyticsContext: AnalyticsContext(excluded: true)).start()
        XCTAssertEqual(State.fetches, 0); XCTAssertEqual(State.navigations, 1)
        XCTAssertEqual((context.bindings.root.controller as? ChatController)?.chatLocation.threadId, 7)
        d.dispose()
    }
    func testForeignAccountAndSecretDestinationNeverGetOrdinaryGrant() {
        for (account, peer): (Int, PeerId) in [(2, 2), (1, -2)] {
            let context = Context(account)
            State.onPush = { XCTAssertNil($0.analyticsContext?.scope); XCTAssertGreaterThan(State.exclusions, 0) }
            ForumUI.open(peer, addition: true, context: context, analyticsContext: AnalyticsContext())
            State.listNavigation.controllers.removeAll()
            XCTAssertEqual(State.exclusions, 0)
        }
    }
    func testOrdinaryListKeepsFirstGrantAcrossReuse() {
        let context = Context(); let first = AnalyticsContext(); let later = AnalyticsContext()
        ForumUI.open(2, addition: true, context: context, analyticsContext: first)
        ForumUI.open(2, addition: true, context: context, analyticsContext: later)
        XCTAssertTrue(State.listNavigation.controller?.analyticsContext?.scope === first.scope)
        XCTAssertEqual(State.exclusions, 0)
    }
    func testRevocationDuringLookupDeniesLateConstructionAndChild() {
        let context = Context(); let origin = AnalyticsContext(); let pipe = ValuePipe<Any?>(); State.cached = pipe.signal()
        ForumUI.open(2, addition: true, context: context, analyticsContext: origin)
        origin.scope?.valid = false
        State.onConstruction = { XCTAssertGreaterThan(State.exclusions, 0) }
        pipe.putNext(CachedChannelData(false))
        XCTAssertFalse(State.listNavigation.controller?.analyticsContext?.scope?.valid ?? true)
        XCTAssertGreaterThan(State.exclusions, 0)
    }
    func testReusedListRefreshesItsLeaseWhenOriginalGrantWasRevoked() {
        let context = Context(); let origin = AnalyticsContext()
        ForumUI.open(2, addition: true, context: context, analyticsContext: origin)
        XCTAssertEqual(State.exclusions, 0)
        origin.scope?.valid = false
        ForumUI.open(2, addition: true, context: context, analyticsContext: AnalyticsContext())
        XCTAssertTrue(State.listNavigation.controller?.analyticsContext?.scope === origin.scope)
        XCTAssertGreaterThan(State.exclusions, 0)
        State.listNavigation.controllers.removeAll()
        XCTAssertEqual(State.exclusions, 0)
    }
    func testMissingContextCompanionStillBindsBeforeReturningToCaller() {
        let context = Context()
        ChatListUIHooks.shared.navigateToChatWithContext = nil
        var called = false
        ChatListUIHooks.shared.navigateToChatObserved(context.bindings.root, context, .peer(2), .history, nil, nil, nil, false, nil, analyticsContext: AnalyticsContext(excluded: true), callback: { controller in
            called = true
            XCTAssertTrue(controller.analyticsContext?.isExcluded == true)
            XCTAssertGreaterThan(State.exclusions, 0)
        })
        XCTAssertTrue(called); XCTAssertEqual(State.legacy, 1)
    }
    func testTabsRouteUsesContextCompanionAndDoesNotPushForumList() {
        let context = Context()
        State.peer = .single(EnginePeer(peer: Peer(displayForumAsTabs: true)))
        State.onPush = { XCTAssertTrue($0.analyticsContext?.isExcluded == true) }
        ForumUI.open(2, addition: true, context: context, analyticsContext: AnalyticsContext(excluded: true))
        XCTAssertEqual(State.navigations, 1); XCTAssertEqual(State.legacy, 0); XCTAssertTrue(State.listNavigation.controllers.isEmpty)
    }
    func testLegacyOverloadsKeepUnscopedRouting() {
        let context = Context()
        ForumUI.open(2, addition: true, context: context)
        XCTAssertNil(State.listNavigation.controller?.analyticsContext)
        let d = ForumUI.openTopic(7, peerId: 2, context: context, isMonoforum: true).start()
        XCTAssertEqual(State.legacy, 1); XCTAssertEqual(State.navigations, 0); XCTAssertEqual(State.exclusions, 0)
        d.dispose()
    }
}
