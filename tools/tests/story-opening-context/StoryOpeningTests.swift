import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct MessageId: Hashable { let peerId: PeerId; let id: Int }
struct StoryId: Equatable { let peerId: PeerId; let id: Int32 }
struct Message { let id: MessageId; var containsSecretMedia = false; var peers: [PeerId: Peer] = [:] }
struct Peer {
    let id: PeerId
    var isMonoForum = false
    var canManageDirect = true
    var restricted = false
    init(id: PeerId, isMonoForum: Bool = false, canManageDirect: Bool = true, restricted: Bool = false) { self.id = id; self.isMonoForum = isMonoForum; self.canManageDirect = canManageDirect; self.restricted = restricted }
    init(_ peer: Peer) { self = peer }
    func _asPeer() -> Peer { self }
    struct Access { let canManageDirect: Bool }
    var groupAccess: Access { Access(canManageDirect: canManageDirect) }
    func restrictionText(_ settings: Int) -> String? { restricted ? "restricted" : nil }
}
struct StoryInitialIndex {
    let peerId: PeerId
    let id: Int32?
    let messageId: MessageId?
    var takeControl: (PeerId, MessageId?, StoryId) -> Int? = { _, _, _ in nil }
    var setProgress: ((Signal<Never, NoError>) -> Void)?
}
__POLICY__
__CONTEXT__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId < 0 ? .excluded : peerId == 0 ? .unresolved : .ordinary }
}
final class Analytics {
    static var shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited)
    }
__CAPTURE__
}
final class ContentView { var bounds = CGRect.zero }
final class Window { let contentView: ContentView? = ContentView() }
final class Account { let postbox = Postbox() }
final class Engine {
    let account = Account()
    let messages = EngineMessages()
    let peers = EnginePeers()
}
protocol AccountContextProtocol {
    var engine: Engine { get }
    var peerId: PeerId { get }
    var window: Window { get }
    var account: Account { get }
    var bindings: Bindings { get }
}
final class AccountContext: AccountContextProtocol {
    let engine = Engine()
    let peerId: PeerId = 1
    let window = Window()
    let bindings = Bindings()
    var account: Account { engine.account }
}
final class Bindings {
    let navigation = Navigation()
    func rootNavigation() -> Navigation { navigation }
}
final class Navigation {
    enum Style { case push }
    var controller: AnyObject?
    var pushes = 0
    func push(_ value: ModalViewController, _ animated: Bool = true, style: Style? = nil) { controller = value; pushes += 1 }
}
enum Stories { struct StoredItem {} }
struct Stored { func get<T>(_ type: T.Type) -> T? { Stories.StoredItem() as? T } }
final class Transaction {
    var exists = true
    func getStory(id: StoryId) -> Stored? { exists ? Stored() : nil }
}
final class Postbox {
    let transactionValue = Transaction()
    var deferTransactions = false
    var pendingTransactions: [() -> Void] = []
    func transaction<T>(_ action: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Probe.setup?()
        return Signal { subscriber in
            let run = {
                subscriber.putNext(action(self.transactionValue))
                subscriber.putCompletion()
            }
            if self.deferTransactions { self.pendingTransactions.append(run) } else { run() }
            return EmptyDisposable
        }
    }
}
final class EngineMessages {
    func refreshStories(peerId: PeerId, ids: [Int32]) -> Signal<Never, NoError> { .complete() }
}
enum Resolve: Equatable {
    case progress, found
    var result: Peer? { self == .found ? Peer(id: 2) : nil }
}
final class EnginePeers {
    var result: Signal<Resolve, NoError> = .single(.found)
    func resolvePeerByName(name: String, referrer: String?) -> Signal<Resolve, NoError> { Probe.setup?(); return result }
}
struct Slice { let peer: Peer; let item = Item() }
struct Item { let storyItem = 0 }
struct StoryContentContextState { let slice: Slice? }
protocol StoryContentContext { var state: Signal<StoryContentContextState, NoError> { get } }
final class Content: StoryContentContext {
    let state: Signal<StoryContentContextState, NoError>
    init() { Probe.setup?(); state = Probe.state }
}
final class StoryListContext {}
func StoryContentContextImpl(context: any AccountContextProtocol, isHidden: Bool, focusedPeerId: PeerId?, singlePeer: Bool) -> Content { Content() }
func SingleStoryContentContextImpl(context: any AccountContextProtocol, storyId: StoryId, readGlobally: Bool) -> Content { Content() }
func PeerStoryListContentContextImpl(context: any AccountContextProtocol, peerId: PeerId, listContext: StoryListContext, initialId: Int32?) -> Content { Content() }
let prepareQueue = Queue.mainQueue()
func waitUntilStoryMediaPreloaded(context: any AccountContextProtocol, peerId: PeerId, storyItem: Int) -> Signal<Never, NoError> { Probe.setup?(); return .complete() }
func showModalProgress<T>(signal: Signal<T, NoError>, for window: Window) -> Signal<T, NoError> { Probe.setup?(); return signal }
enum Animation { case animateBackground }
func showModal<Context>(with controller: StoryModalController<Context>, for window: Window, animationType: Animation) {
    Probe.shown.append(controller)
    Probe.onShow?()
}
func showModalText(for window: Window, text: String) { Probe.errors += 1; Probe.setup?() }
struct Strings { let storyErrorNotExist = "missing"; let alertUserDoesntExists = "missing peer" }
func strings() -> Strings { Strings() }
func getWindow(_ context: AccountContext) -> Window { context.window }
let darkAppearance = 0
enum Mode { case stories }
class ModalViewController {
    var analyticsContext: AnalyticsContext?
    var _frameRect = CGRect.zero
    struct Bar { let height: Int }
    var bar = Bar(height: 0)
    enum Screen { case storiesViewer }
    var analyticsScreen: Screen?
}
final class EntertainmentViewController<Context: AccountContextProtocol>: ModalViewController {
    init(size: CGSize, context: Context, mode: Mode, presentation: Int) { super.init(); Probe.setup?() }
}
final class EmojiesController<Context: AccountContextProtocol>: ModalViewController {
    init(_ context: Context, presentation: Int) { super.init(); Probe.setup?() }
}
final class StoryInteraction {}
enum Location { case peer(PeerId) }
final class ChatInteraction {
    var interactionContext: any AccountContextProtocol { context }
    let context: any AccountContextProtocol
    var inheritedAnalyticsContext: AnalyticsContext?
    init(chatLocation: Location, context: any AccountContextProtocol) { self.context = context }
    var openChatPeerStories: (MessageId, PeerId, ((Signal<Never, NoError>) -> Void)?) -> Void = { _, _, _ in }
    func captureAnalyticsContext(sourcePeerId: PeerId? = nil) -> AnalyticsContext {
        Analytics.shared.captureContext(engine: context.engine, peerId: sourcePeerId ?? context.peerId, inherited: inheritedAnalyticsContext)
    }
    func captureAnalyticsContext(inherited: AnalyticsContext) -> AnalyticsContext {
        let current = captureAnalyticsContext()
        guard !current.isExcluded, current.scope?.isValid == true else { return current }
        return Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: inherited)
    }
__INTERACTION__
}
enum StoryMorphLab { static var closeActiveStory: (() -> Void)? }
final class StoryModalController<Context: AccountContextProtocol>: ModalViewController {
    let context: Context
    let stories: StoryContentContext
    let initialId: StoryInitialIndex?
    let entertainment: EntertainmentViewController<Context>
    let emoji: EmojiesController<Context>
    let interactions: StoryInteraction
    let chatInteraction: ChatInteraction
    func close() {}
__INIT__
__OPEN__
    func nestedAction() -> (StoryId) -> Void {
        let context = self.context
        return { [weak self] storyId in
__NESTED__
        }
    }
}
final class PeerInfoArguments<Context: AccountContextProtocol> {
    let context: Context
    let origin: AnalyticsContext
    init(_ context: Context, _ origin: AnalyticsContext) { self.context = context; self.origin = origin }
    func captureAnalyticsContext() -> AnalyticsContext { origin }
__PROFILE__
}
struct ChatUIHooks {
    static var shared = ChatUIHooks(showSingleStory: { _, _, _, _ in }, showStories: { _, _, _, _ in })
__HOOKS__
}
func installBridge() {
    var hooks = ChatUIHooks(showSingleStory: { context, storyId, initialId, callback in
        StoryModalController.ShowSingleStory(context: context as! AccountContext, storyId: storyId, initialId: initialId, emptyCallback: callback)
    }, showStories: { context, hidden, initial, single in
        StoryModalController.ShowStories(context: context as! AccountContext, isHidden: hidden, initialId: initial, singlePeer: single)
    })
__BRIDGE__
    ChatUIHooks.shared = hooks
}
struct Entry { let message: Message }
final class History { var originalView: HistoryValue? = HistoryValue() }
final class HistoryValue { var entries: [Entry] = [] }
struct ChatLocation { var peerId: PeerId }
final class ChatController {
    let context: AccountContext
    let chatInteraction: ChatInteraction
    var historyView: History? = History()
    let chatLocation = ChatLocation(peerId: 2)
    init(_ context: AccountContext) {
        self.context = context
        chatInteraction = ChatInteraction(chatLocation: .peer(2), context: context)
        let peerId: PeerId = 2
__CHAT__
    }
    func findStoryControl(_ messageId: MessageId?, _ storyId: StoryId, _ peerId: PeerId, useAvatar: Bool = false) -> Int? { 7 }
}
__LINK_ORIGIN__
func openLink(_ context: AccountContext, messageId: MessageId?, analyticsContext: AnalyticsContext?) {
    let username = "example"
    let storyId: Int32 = 1
    func afterComplete(_ value: Bool) {}
__LINK__
}
enum Probe {
    static var state: Signal<StoryContentContextState, NoError> = .single(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
    static var shown: [ModalViewController] = []
    static var setup: (() -> Void)?
    static var onShow: (() -> Void)?
    static var errors = 0
}
final class StoryOpeningTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    let story = StoryId(peerId: 2, id: 1)
    let message = MessageId(peerId: 2, id: 10)
    override func setUp() {
        Probe.shown = []; Probe.setup = nil; Probe.onShow = nil; Probe.errors = 0
        Probe.state = .single(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installBridge()
    }
    override func tearDown() {
        Probe.setup = nil; Probe.onShow = nil; Probe.shown = []
        context = nil; Analytics.shared = Analytics()
    }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
    func viewer() throws -> StoryModalController<AccountContext> { try XCTUnwrap(Probe.shown.last as? StoryModalController<AccountContext>) }
    func assertBound(_ origin: AnalyticsContext, file: StaticString = #filePath, line: UInt = #line) throws {
        let controller = try viewer()
        for value in [controller.analyticsContext, controller.chatInteraction.inheritedAnalyticsContext, controller.entertainment.analyticsContext, controller.emoji.analyticsContext] {
            XCTAssertTrue(value?.scope === origin.scope, file: file, line: line)
            XCTAssertEqual(value?.isExcluded, origin.isExcluded, file: file, line: line)
        }
    }
    func testOrdinarySingleRootPreservesExactScopeIntoAllChildren() throws {
        let original = origin()
        StoryModalController.ShowSingleStory(context: context, storyId: story, initialId: nil, analyticsContext: original)
        pump(); try assertBound(original)
        XCTAssertTrue(original.scope?.isValid == true)
    }
    func testOrdinaryListAndFeedPreserveScope() throws {
        let original = origin()
        StoryModalController.ShowListStory(context: context, listContext: StoryListContext(), peerId: 2, initialId: nil, analyticsContext: original)
        pump(); try assertBound(original)
        StoryModalController.ShowStories(context: context, isHidden: false, initialId: nil, analyticsContext: original)
        pump(); try assertBound(original)
        XCTAssertEqual(Probe.shown.count, 2)
    }
    func testSecretOriginProtectsFactoriesAndDelayedStoryLoadAfterParentEnds() throws {
        let original = origin(.excluded)
        let parent = original.beginPresentation()
        var subscriber: Subscriber<StoryContentContextState, NoError>?
        Probe.state = Signal { subscriber = $0; return EmptyDisposable }
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        StoryModalController.ShowSingleStory(context: context, storyId: story, initialId: nil, analyticsContext: original)
        parent.end()
        XCTAssertTrue(hub.policy.hasExclusions)
        subscriber?.putNext(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        subscriber = nil; pump()
        try assertBound(original)
    }
    func testMissingOriginAndSecretTargetNeverCreateGrantButStillOpen() throws {
        StoryModalController.ShowSingleStory(context: context, storyId: story, initialId: nil)
        pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
        let original = origin()
        StoryModalController.ShowSingleStory(context: context, storyId: StoryId(peerId: -2, id: 1), initialId: nil, analyticsContext: original)
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testLoadedSecretSliceRestrictsOrdinaryFeedOrigin() throws {
        let original = origin()
        Probe.state = .single(StoryContentContextState(slice: Slice(peer: Peer(id: -2))))
        StoryModalController.ShowStories(context: context, isHidden: false, initialId: nil, analyticsContext: original)
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testLegacyHookFallbackOpensWithoutGrant() throws {
        ChatUIHooks.shared.showSingleStoryWithContext = nil
        ChatUIHooks.shared.showSingleStoryObserved(context, story, nil, nil, analyticsContext: origin(.excluded))
        pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testPrivateLoadedSliceProtectsPreloadConstruction() throws {
        let original = origin()
        var subscriber: Subscriber<StoryContentContextState, NoError>?
        Probe.state = Signal { subscriber = $0; return EmptyDisposable }
        StoryModalController.ShowStories(context: context, isHidden: false, initialId: nil, analyticsContext: original)
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        subscriber?.putNext(StoryContentContextState(slice: Slice(peer: Peer(id: -2))))
        subscriber = nil; pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testAccountSwitchProtectsDeferredFeedPreloadConstruction() throws {
        let original = origin()
        var subscriber: Subscriber<StoryContentContextState, NoError>?
        Probe.state = Signal { subscriber = $0; return EmptyDisposable }
        StoryModalController.ShowStories(context: context, isHidden: false, initialId: nil, analyticsContext: original)
        let other = AccountContext()
        hub.policy.setOwner(other.account)
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        subscriber?.putNext(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        subscriber = nil; pump()
        XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testRevocationDuringLoadingCannotRefreshScope() throws {
        let original = origin()
        var subscriber: Subscriber<StoryContentContextState, NoError>?
        Probe.state = Signal { subscriber = $0; return EmptyDisposable }
        StoryModalController.ShowSingleStory(context: context, storyId: story, initialId: nil, analyticsContext: original)
        original.scope?.exclude()
        subscriber?.putNext(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        subscriber = nil; pump()
        XCTAssertNil(try viewer().analyticsContext?.scope)
        XCTAssertTrue(try viewer().chatInteraction.inheritedAnalyticsContext?.isExcluded == true)
    }
    func testAccountSwitchAndForeignAccountCannotRebindOrigin() throws {
        let original = origin()
        let foreign = AccountContext()
        hub.policy.setOwner(foreign.account)
        StoryModalController.ShowSingleStory(context: foreign, storyId: story, initialId: nil, analyticsContext: original)
        pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testFeedProgressSubscriptionAndCancellationOwnExclusion() {
        var subscriber: Subscriber<StoryContentContextState, NoError>?
        Probe.state = Signal { subscriber = $0; return EmptyDisposable }
        var progress: Signal<Never, NoError>?
        let initial = StoryInitialIndex(peerId: 2, id: nil, messageId: nil, setProgress: { progress = $0 })
        StoryModalController.ShowStories(context: context, isHidden: false, initialId: initial, analyticsContext: origin(.excluded))
        let disposable = progress?.start()
        XCTAssertNotNil(subscriber)
        XCTAssertTrue(hub.policy.hasExclusions)
        disposable?.dispose(); subscriber = nil
        XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertTrue(Probe.shown.isEmpty)
    }
    func testEmptyStoryCallbackRunsUnderOriginalExclusion() {
        context.account.postbox.transactionValue.exists = false
        var called = false
        StoryModalController.ShowSingleStory(context: context, storyId: story, initialId: nil, emptyCallback: {
            called = true; XCTAssertTrue(self.hub.policy.hasExclusions)
        }, analyticsContext: origin(.excluded))
        XCTAssertTrue(called); XCTAssertTrue(Probe.shown.isEmpty)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testChatMessageAndAvatarOriginsPreserveScope() throws {
        let original = origin()
        let chat = ChatController(context)
        chat.chatInteraction.inheritedAnalyticsContext = original
        chat.historyView?.originalView?.entries = [Entry(message: Message(id: message))]
        chat.chatInteraction.openStory(message, story)
        pump(); try assertBound(original)
        chat.chatInteraction.openChatPeerStories(message, 2, nil)
        pump(); try assertBound(original)
    }
    func testMissingOrSecretMessageCannotBecomeOrdinaryStoryOrigin() throws {
        let chat = ChatController(context)
        chat.chatInteraction.inheritedAnalyticsContext = origin()
        chat.chatInteraction.openStory(message, story)
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
        chat.historyView?.originalView?.entries = [Entry(message: Message(id: message, containsSecretMedia: true))]
        chat.chatInteraction.openStory(message, story)
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testLinkRetainsSecretOriginAcrossResolutionIntoOrdinaryChat() throws {
        let chat = ChatController(context)
        chat.chatInteraction.inheritedAnalyticsContext = origin()
        chat.historyView?.originalView?.entries = [Entry(message: Message(id: message))]
        context.bindings.navigation.controller = chat
        var subscriber: Subscriber<Resolve, NoError>?
        context.engine.peers.result = Signal { subscriber = $0; return EmptyDisposable }
        openLink(context, messageId: message, analyticsContext: origin(.excluded))
        XCTAssertTrue(hub.policy.hasExclusions)
        subscriber?.putNext(.found); subscriber?.putCompletion(); subscriber = nil
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testNestedStoryAndProfilePreservePrivateOrigin() throws {
        let original = origin(.excluded)
        let profile = PeerInfoArguments(context, original)
        profile.openStory(nil)
        pump(); try assertBound(original)
        let first = try viewer()
        first.nestedAction()(story)
        pump(); try assertBound(original)
        XCTAssertEqual(Probe.shown.count, 2)
    }
    func testOwnerLossInNestedStoryCannotMintGrant() throws {
        var first: StoryModalController<AccountContext>? = StoryModalController(context: context, stories: Content(), initialId: nil, analyticsContext: origin())
        let action = first!.nestedAction()
        weak var released = first
        first = nil
        XCTAssertNil(released)
        action(story)
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testAccountChangesAfterLoadingStartsCannotRegrant() throws {
        let original = origin()
        var subscriber: Subscriber<StoryContentContextState, NoError>?
        Probe.state = Signal { subscriber = $0; return EmptyDisposable }
        StoryModalController.ShowSingleStory(context: context, storyId: story, initialId: nil, analyticsContext: original)
        let other = AccountContext()
        hub.policy.setOwner(other.account)
        subscriber?.putNext(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        subscriber = nil; pump()
        XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testDirectOrdinaryLinkPreservesScope() throws {
        let original = origin()
        openLink(context, messageId: nil, analyticsContext: original)
        pump(); try assertBound(original)
    }
}
