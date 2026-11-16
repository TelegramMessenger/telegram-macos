import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct MessageId: Equatable { let peerId: PeerId; let id: Int }
class Peer { let id: PeerId; init(_ id: PeerId) { self.id = id } }
final class TelegramUser: Peer {}
struct Message {
    struct ForwardInfo { let author: Peer? }
    let id: MessageId
    var author: Peer?
    var containsSecretMedia = false
    var forwardInfo: ForwardInfo?
    var peers: [PeerId: Peer] = [:]
}
struct EngineMessage { let message: Message; init(_ message: Message) { self.message = message } }
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
final class Account { let postbox = CommonPostbox() }
final class Engine {
    let account = Account()
    let messages = Messages()
    final class Messages {
        var ensured: [EngineMessage] = []
        func ensureMessagesAreLocallyAvailable(messages: [EngineMessage]) { ensured += messages }
    }
}
protocol AccountContextProtocol {
    var engine: Engine { get }
    var peerId: PeerId { get }
    var bindings: Bindings { get }
}
extension AccountContextProtocol { var concrete: AccountContext { self as! AccountContext } }
final class AccountContext: AccountContextProtocol {
    let engine = Engine()
    let peerId: PeerId = 1
    let bindings = Bindings()
    var isPremium = false
}
final class Bindings {
    let navigation = NavigationViewController()
    func rootNavigation() -> NavigationViewController { navigation }
}
class ViewController { var analyticsContext: AnalyticsContext? }
final class NavigationViewController {
    var pushed: [ViewController] = []
    func push(_ controller: ViewController) { pushed.append(controller) }
}
typealias ThreadInfo = Int
typealias PeerExpiringStoryListContext = Int
typealias PeerMediaCollectionMode = Int
struct ThreadData { let peerId: PeerId; let threadId: Int64; var isMonoforumPost = false }
enum ChatLocation {
    case peer(PeerId), thread(ThreadData)
    var peerId: PeerId { switch self { case let .peer(id): return id; case let .thread(data): return data.peerId } }
    var threadId: Int64? { if case let .thread(data) = self { return data.threadId }; return nil }
}
enum ChatMode: Equatable {
    enum ThreadMode: Equatable { case topic(origin: MessageId) }
    case thread(mode: ThreadMode)
    case history, saved, topic
    var isSavedMessagesThread: Bool { self == .saved }
    struct Custom { enum Kind { case searchHashtag, other }; let kind: Kind }
    var customChatContents: Custom? { nil }
}
enum ChatInitialAction: Equatable { case album(Int32, Int), source(MessageId?, Int?), pollOption(Data), other }
struct ChatFocusTarget {
    let messageId: MessageId
    var string: String?
    var pollOptionId: Data?
    init(messageId: MessageId?, string: String? = nil, pollOptionId: Data? = nil) { self.messageId = messageId ?? MessageId(peerId: 0, id: 0); self.string = string; self.pollOptionId = pollOptionId }
}
enum TableScrollState { case CenterEmpty }
struct Presentation {
    var reportMode: Int?
    var isTopicMode = false
    var initialAction: ChatInitialAction?
    func updatedInitialAction(_ action: ChatInitialAction) -> Presentation { var value = self; value.initialAction = action; return value }
}
let repliesPeerId: PeerId = 99
final class ChatInteraction {
    let interactionContext: any AccountContextProtocol
    let chatLocation: ChatLocation
    var peer: Peer?
    var peerId: PeerId { chatLocation.peerId }
    var mode: ChatMode
    var inheritedAnalyticsContext: AnalyticsContext?
    var presentation = Presentation()
    var isGlobalSearchMessage = false
    var focused: (MessageId?, ChatFocusTarget)?
    var invoked = 0
    var topic: Int?
    var selectedTag: SavedLocationTag?
    func setLocationTag(_ tag: SavedLocationTag?) { selectedTag = tag }
    init(_ context: AccountContext, location: ChatLocation, mode: ChatMode = .history) {
        interactionContext = context; chatLocation = location; self.mode = mode
        focusMessageId = { [weak self] from, target, _ in self?.focused = (from, target) }
    }
    func captureAnalyticsContext(sourcePeerId: PeerId? = nil) -> AnalyticsContext {
        let origin = Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inheritedAnalyticsContext)
        return sourcePeerId.map { origin.restricting(peerId: $0) } ?? origin
    }
    func captureAnalyticsContext(inherited: AnalyticsContext) -> AnalyticsContext {
        let current = captureAnalyticsContext()
        guard !current.isExcluded, current.scope?.isValid == true else { return current }
        return Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inherited)
    }
    var focusMessageId: (MessageId?, ChatFocusTarget, TableScrollState) -> Void = { _, _, _ in }
    func update(_ action: (Presentation) -> Presentation) { presentation = action(presentation) }
    func invokeInitialAction() { invoked += 1 }
    func threadInfo(_ peerId: PeerId, holder: Int) -> ThreadInfo? { topic }
__INTERACTION__
    func clear() {
__CLEAR__
    }
}
struct ProfileCall { let peerId: PeerId; let thread: Int?; let stories: Int?; let mode: Int?; let album: Int32?; let origin: AnalyticsContext? }
struct NavigationCall { let peerId: PeerId; let focus: ChatFocusTarget?; let action: ChatInitialAction?; let additional: Bool; let origin: AnalyticsContext? }
enum Probe {
    static var profiles: [ProfileCall] = []
    static var chats: [NavigationCall] = []
    static var media: [(PeerId, Int?)] = []
    static var childOrigin: AnalyticsContext?
    static var construction: (() -> Void)?
    static func makeMedia(_ peerId: PeerId, _ thread: Int?) -> ViewController {
        construction?(); media.append((peerId, thread)); let result = ViewController(); result.analyticsContext = childOrigin; return result
    }
}
struct ChatUIHooks {
    static var shared = ChatUIHooks()
    var navigateToChatWithFocus: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?) -> Void = { _, _, location, focus, action in
        Probe.construction?(); Probe.chats.append(NavigationCall(peerId: location.peerId, focus: focus, action: action, additional: false, origin: nil))
    }
    var navigateToChatWithFocusAdditional: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?, Bool) -> Void = { _, _, location, focus, action, additional in
        Probe.construction?(); Probe.chats.append(NavigationCall(peerId: location.peerId, focus: focus, action: action, additional: additional, origin: nil))
    }
    var makeThreadPeerMediaController: (any AccountContextProtocol, PeerId, ThreadInfo?, Bool) -> ViewController = { _, peerId, thread, _ in Probe.makeMedia(peerId, thread) }
    var makePeerMediaController: (any AccountContextProtocol, PeerId, Bool) -> ViewController = { _, peerId, _ in Probe.makeMedia(peerId, nil) }
    var pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId, ThreadInfo?, PeerExpiringStoryListContext?, PeerMediaCollectionMode?, Int32?) -> Void = { _, _, peerId, thread, stories, mode, album in
        Probe.construction?(); Probe.profiles.append(ProfileCall(peerId: peerId, thread: thread, stories: stories, mode: mode, album: album, origin: nil))
    }
__HOOKS__
}
func navigateToChat(navigation: NavigationViewController?, context: AccountContext, chatLocation: ChatLocation, focusTarget: ChatFocusTarget?, initialAction: ChatInitialAction?, additional: Bool, analyticsContext: AnalyticsContext) {
    Probe.construction?(); Probe.chats.append(NavigationCall(peerId: chatLocation.peerId, focus: focusTarget, action: initialAction, additional: additional, origin: analyticsContext))
}
enum PeerInfoController {
    enum Source: Equatable { case none, reaction(MessageId) }
    static func push(navigation: NavigationViewController, context: AccountContext, peerId: PeerId, threadInfo: ThreadInfo? = nil, stories: PeerExpiringStoryListContext? = nil, source: Source = .none, mediaMode: PeerMediaCollectionMode? = nil, albumId: Int32? = nil, analyticsContext: AnalyticsContext) {
        ReactionListProbe.profileSources.append(source); Probe.construction?(); Probe.profiles.append(ProfileCall(peerId: peerId, thread: threadInfo, stories: stories, mode: mediaMode, album: albumId, origin: analyticsContext))
    }
}
func installBridge() {
    var hooks = ChatUIHooks()
__BRIDGE__
    ChatUIHooks.shared = hooks
    PeerInfoNavigationHooks.shared = makeCommonFactoryHooks()
    installGroupsInCommonUIHooks()
}
final class ChatController: ViewController {
    let context: AccountContext
    let chatInteraction: ChatInteraction
    var navigationController: NavigationViewController?
    let chatLocationContextHolder = 0
    var stories: Int? = 42
    init(_ context: AccountContext, location: ChatLocation = .peer(2), mode: ChatMode = .history) {
        self.context = context
        self.chatInteraction = ChatInteraction(context, location: location, mode: mode)
        navigationController = context.bindings.rootNavigation()
        super.init()
        let chatInteraction = self.chatInteraction
__HANDLER__
    }
__HEADER__
    func inheritAnalyticsContext(_ origin: AnalyticsContext) { chatInteraction.inheritedAnalyticsContext = origin }
}
func entityCallback(_ interaction: ChatInteraction, message: Message) -> (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void {
    let chatInteraction = interaction
__ENTITY__
    return openInfo
}
final class Row {
    let chatInteraction: ChatInteraction
    var context: any AccountContextProtocol { chatInteraction.interactionContext }
    let peer: Peer?
    let message: Message?
    init(_ interaction: ChatInteraction, peer: Peer?, message: Message?) { chatInteraction = interaction; self.peer = peer; self.message = message }
__ROW__
    func menuProfile(_ peer: Peer) {
        let chatInteraction: ChatInteraction? = self.chatInteraction
        let item = self
__MENU_PROFILE__
    }
    func menuChat(_ peer: Peer) {
        let chatInteraction: ChatInteraction? = self.chatInteraction
        let item = self
__MENU_CHAT__
    }
}

final class ChatProfileTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.profiles = []; Probe.chats = []; Probe.media = []; Probe.childOrigin = nil; Probe.construction = nil
        installBridge()
    }
    override func tearDown() { Probe.construction = nil; Probe.profiles = []; Probe.chats = []; Probe.childOrigin = nil; context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.engine.account, privacy: privacy) }
    func message(_ peerId: PeerId = 2, secret: Bool = false) -> Message { Message(id: MessageId(peerId: peerId, id: 7), containsSecretMedia: secret) }
    func testHeaderKeepsKnownOrdinaryScopeAndStories() throws {
        let chat = ChatController(context); let source = origin(); chat.chatInteraction.inheritedAnalyticsContext = source
        chat.openPeerInfoFromHeader()
        let call = try XCTUnwrap(Probe.profiles.last)
        XCTAssertTrue(call.origin?.scope === source.scope); XCTAssertEqual(call.peerId, 2); XCTAssertEqual(call.stories, 42)
    }
    func testSecretHeaderKeepsExclusionAfterOriginDisappears() throws {
        var chat: ChatController? = ChatController(context, location: .peer(-2))
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        chat?.openPeerInfoFromHeader(); chat = nil
        let source = try XCTUnwrap(Probe.profiles.last?.origin)
        XCTAssertTrue(source.isExcluded)
        let lifetime = source.beginPresentation(); XCTAssertTrue(hub.policy.hasExclusions); lifetime.end()
    }
    func testMessageEntityClassifiesSecretMediaAndPreservesFunctionalAction() throws {
        let chat = ChatController(context); let source = message(secret: true)
        let callback = entityCallback(chat.chatInteraction, message: source)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        callback(3, true, source.id, nil)
        let call = try XCTUnwrap(Probe.chats.last)
        XCTAssertTrue(call.origin?.isExcluded == true); XCTAssertEqual(call.action, .source(source.id, nil)); XCTAssertTrue(call.additional)
    }
    func testEntityOrdinaryProfileRetainsScopeWithoutInventingSourceAction() throws {
        let chat = ChatController(context); let original = origin(); chat.chatInteraction.inheritedAnalyticsContext = original
        entityCallback(chat.chatInteraction, message: message())(3, false, nil, nil)
        XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.scope === original.scope)
        XCTAssertTrue(Probe.chats.isEmpty)
    }
    func testPrivateSourcePeerStaysPrivateWhenAuthorIsOrdinary() throws {
        let chat = ChatController(context)
        Row(chat.chatInteraction, peer: TelegramUser(3), message: message(-2)).openInfo()
        XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.isExcluded == true)
    }
    func testMissingRowMessageDoesNotGrantScope() throws {
        let chat = ChatController(context)
        Row(chat.chatInteraction, peer: TelegramUser(3), message: nil).openInfo()
        XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.isExcluded == true)
    }
    func testForwardAuthorClassifiesOriginalMessage() throws {
        let chat = ChatController(context)
        var source = message(secret: true); source.forwardInfo = .init(author: TelegramUser(3))
        Row(chat.chatInteraction, peer: nil, message: source).openForwardInfo()
        XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.isExcluded == true)
    }
    func testAvatarMenuActionsClassifyTheirMessage() throws {
        let chat = ChatController(context); let peer = TelegramUser(3)
        let row = Row(chat.chatInteraction, peer: peer, message: message(secret: true))
        row.menuProfile(peer); row.menuChat(peer)
        XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.isExcluded == true)
        XCTAssertTrue(try XCTUnwrap(Probe.chats.last).origin?.isExcluded == true)
    }
    func testExplicitPrivateOriginSurvivesInvalidReceivingScope() throws {
        let chat = ChatController(context); chat.chatInteraction.inheritedAnalyticsContext = origin()
        let privateOrigin = origin(.excluded); let lifetime = privateOrigin.beginPresentation(); lifetime.end()
        chat.chatInteraction.openInfoObserved(3, false, nil, nil, analyticsContext: privateOrigin)
        XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.isExcluded == true)
    }
    func testRevokedAndForeignOriginsCannotRegrant() throws {
        let original = origin(); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        let chat = ChatController(context)
        chat.chatInteraction.openInfoObserved(3, false, nil, nil, analyticsContext: original)
        XCTAssertNil(try XCTUnwrap(Probe.profiles.last).origin?.scope)
        let valid = origin(); let other = AccountContext(); hub.policy.setOwner(other.engine.account)
        ChatUIHooks.shared.pushPeerInfoObserved(other.bindings.navigation, other, 3, nil, nil, nil, nil, analyticsContext: valid)
        XCTAssertNil(try XCTUnwrap(Probe.profiles.last).origin?.scope)
    }
    func testLegacyOpenInfoRemainsFunctionalAndUnresolved() throws {
        let chat = ChatController(context)
        chat.chatInteraction.openInfo(3, false, nil, nil)
        XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.isExcluded == true)
    }
    func testLegacyHookFallbacksRunUnderExclusion() {
        ChatUIHooks.shared.pushPeerInfoWithContext = nil; ChatUIHooks.shared.navigateToChatWithContext = nil
        let chat = ChatController(context)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        chat.chatInteraction.openInfoFromMessage(3, false, nil, nil, message: message(secret: true))
        chat.chatInteraction.openInfoFromMessage(3, true, nil, nil, message: message(secret: true))
        XCTAssertEqual(Probe.profiles.count, 1); XCTAssertEqual(Probe.chats.count, 1)
    }
    func testAlbumKeepsProfileRoutingAndSelection() throws {
        let chat = ChatController(context); chat.chatInteraction.topic = 9
        chat.chatInteraction.openInfoFromMessage(2, false, nil, .album(11, 5), message: message())
        let call = try XCTUnwrap(Probe.profiles.last)
        XCTAssertEqual(call.album, 11); XCTAssertEqual(call.mode, 5); XCTAssertEqual(call.thread, 9); XCTAssertTrue(Probe.chats.isEmpty)
    }
    func testSameChatFocusAndInitialActionRemainFunctional() {
        let chat = ChatController(context); let from = message().id; let target = MessageId(peerId: 2, id: 8)
        chat.chatInteraction.openInfoFromMessage(2, true, target, .source(from, nil), message: message(secret: true))
        XCTAssertEqual(chat.chatInteraction.focused?.0, from); XCTAssertEqual(chat.chatInteraction.focused?.1.messageId, target)
        XCTAssertTrue(chat.chatInteraction.inheritedAnalyticsContext?.isExcluded == true)
        XCTAssertEqual(chat.chatInteraction.invoked, 1); XCTAssertTrue(Probe.profiles.isEmpty); XCTAssertTrue(Probe.chats.isEmpty)
        let option = Data([1])
        chat.chatInteraction.openInfoFromMessage(2, true, target, .pollOption(option), message: message())
        XCTAssertEqual(chat.chatInteraction.focused?.1.pollOptionId, option)
    }
    func testSavedThreadUsesMediaAndNonAdditionalChatNavigation() throws {
        let chat = ChatController(context, location: .thread(ThreadData(peerId: 1, threadId: 3)), mode: .saved)
        let original = origin(); chat.chatInteraction.inheritedAnalyticsContext = original; chat.chatInteraction.topic = 3
        chat.openPeerInfoFromHeader()
        XCTAssertEqual(Probe.media.last?.0, 3); XCTAssertEqual(Probe.media.last?.1, 3)
        XCTAssertTrue(try XCTUnwrap(context.bindings.navigation.pushed.last).analyticsContext?.scope === original.scope)
        chat.chatInteraction.openInfoFromMessage(4, true, nil, nil, message: message())
        XCTAssertFalse(try XCTUnwrap(Probe.chats.last).additional)
    }
    func testSelfHeaderMediaPreservesPrivateOriginAndConstructionGuard() throws {
        let chat = ChatController(context, location: .peer(1)); chat.chatInteraction.inheritedAnalyticsContext = origin(.excluded)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        chat.openPeerInfoFromHeader()
        XCTAssertTrue(try XCTUnwrap(context.bindings.navigation.pushed.last).analyticsContext?.isExcluded == true)
    }
    func testMediaDoesNotReplaceStricterChildWithOrdinaryGrant() throws {
        ChatUIHooks.shared.makePeerMediaControllerWithContext = nil
        let original = origin(); Probe.childOrigin = origin(.excluded)
        let child = ChatUIHooks.shared.makePeerMediaControllerObserved(context, 3, isBot: false, analyticsContext: original)
        XCTAssertTrue(child.analyticsContext?.isExcluded == true)
    }
    func testMediaKeepsExplicitPrivateSourceWithRevokedOrdinaryChild() {
        ChatUIHooks.shared.makePeerMediaControllerWithContext = nil
        Probe.childOrigin = origin(); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        let child = ChatUIHooks.shared.makePeerMediaControllerObserved(context, 3, isBot: false, analyticsContext: origin(.excluded))
        XCTAssertTrue(child.analyticsContext?.isExcluded == true)
    }
    func testHeaderGuardsAndMonoforumTargetRemainIntact() throws {
        let blocked = ChatController(context); blocked.chatInteraction.presentation.reportMode = 1; blocked.openPeerInfoFromHeader()
        ChatController(context, location: .peer(repliesPeerId)).openPeerInfoFromHeader()
        XCTAssertTrue(Probe.profiles.isEmpty)
        let chat = ChatController(context, location: .thread(ThreadData(peerId: 2, threadId: -3, isMonoforumPost: true)))
        chat.openPeerInfoFromHeader()
        XCTAssertEqual(Probe.profiles.last?.peerId, -3); XCTAssertTrue(try XCTUnwrap(Probe.profiles.last).origin?.isExcluded == true)
    }
    func testTeardownAndReleasedControllerCannotOpenProfile() {
        var chat: ChatController? = ChatController(context)
        let interaction = chat!.chatInteraction; weak var released = chat; chat = nil
        XCTAssertNil(released)
        interaction.openInfoFromMessage(3, false, nil, nil, message: message())
        XCTAssertTrue(Probe.profiles.isEmpty)
        let live = ChatController(context); live.chatInteraction.clear()
        XCTAssertNil(live.chatInteraction.openInfoWithAnalytics)
        live.chatInteraction.openInfoFromMessage(3, false, nil, nil, message: message())
        XCTAssertTrue(Probe.profiles.isEmpty)
    }
    func testDisabledAnalyticsDoesNotBlockNavigation() {
        hub.policy.isEnabled = false
        let chat = ChatController(context)
        chat.openPeerInfoFromHeader()
        XCTAssertEqual(Probe.profiles.count, 1); XCTAssertNil(Probe.profiles.last?.origin?.scope)
    }
}
