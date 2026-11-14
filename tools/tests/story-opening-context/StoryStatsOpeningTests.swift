typealias EnginePeer = Peer
struct EngineStoryItem { let id: Int32 }
__STATS_SUBJECT__
struct EngineMessage {
    let message: Message
    init(_ message: Message) { self.message = message }
    var id: MessageId { message.id }
    var peers: [PeerId: Peer] { message.peers }
    var containsSecretMedia: Bool { message.containsSecretMedia }
}
enum StatsTarget { case message(EngineMessage); case story(EnginePeer, EngineStoryItem) }
typealias StatsGraph = Int
final class StatsSurface: ModalViewController {
    var open: (StatsTarget) -> Void = { _ in }
    var graph: (StatsGraph, Int64) -> Signal<StatsGraph?, NoError> = { _, _ in .single(nil) }
}
enum StatsProbe {
    static var updates: [[PeerId]] = []
    static var graph: ((StatsGraph, Int64) -> Signal<StatsGraph?, NoError>)?
    static var onUpdate: (() -> Void)?
}
func updatePeersCustom(transaction: Transaction, peers: [Peer], update: (Peer?, Peer) -> Peer?) {
    StatsProbe.onUpdate?()
    StatsProbe.updates.append(peers.map(\.id))
}
func MessageStatsController(_ context: any AccountContextProtocol, subject: MessageStatsSubject, analyticsContext: AnalyticsContext? = nil) -> StatsSurface {
__STATS_PREFIX__
    Probe.setup?()
    let controller = StatsSurface()
__STATS_ASSIGN__
    let loadDetailedGraphImpl = StatsProbe.graph
    controller.graph = { graph, x in
__STATS_GRAPH__
    }
    controller.open = { target in
__STATS_OPEN__
    }
    return controller
}
struct StatisticsHooks {
__OVERVIEW_HOOKS__
    var makeMonetizationController: (any AccountContextProtocol, PeerId) -> ViewController = { _, _ in OverviewProbe.makeChild() }
    var makeStarMonetizationController: (any AccountContextProtocol, PeerId) -> ViewController = { _, _ in OverviewProbe.makeChild() }
    var makeBoostStatsController: (any AccountContextProtocol, PeerId) -> ViewController = { _, _ in OverviewProbe.makeChild() }
    static var shared = StatisticsHooks(openMessage: { _, _ in }, showStory: { _, _, _ in })
__STATS_HOOKS__
}
struct ChatNavigationHooks {
    static var shared = ChatNavigationHooks()
__STATS_CHAT_HOOK__
}
extension ChatLocation { static func peer(_ id: PeerId) -> ChatLocation { ChatLocation(peerId: id) } }
struct Focus { let messageId: MessageId }
final class ChatAdditionController: ModalViewController {
    let context: AccountContext
    let chatLocation: ChatLocation
    let focusTarget: Focus
    init(context: AccountContext, chatLocation: ChatLocation, focusTarget: Focus) {
        self.context = context; self.chatLocation = chatLocation; self.focusTarget = focusTarget
        super.init(); Probe.setup?()
    }
    func inheritAnalyticsContext(_ context: AnalyticsContext) { analyticsContext = context }
}
func installStatsBridges() {
    do {
        var hooks = FeatureNavigationHooks.shared
__STATS_FEATURE_BRIDGE__
        FeatureNavigationHooks.shared = hooks
    }
    do {
        var hooks = ChatNavigationHooks()
__STATS_CHAT_BRIDGE__
        ChatNavigationHooks.shared = hooks
    }
    do {
        var hooks = StatisticsHooks(openMessage: { context, messageId in
__STATS_LEGACY_CHAT_BRIDGE__
        }, showStory: { context, peer, id in
            StoryModalController.ShowSingleStory(context: context as! AccountContext, storyId: StoryId(peerId: peer, id: id), initialId: nil)
        })
__STATS_BRIDGE__
        StatisticsHooks.shared = hooks
    }
}
struct StoryContentItem { let storyItem: EngineStoryItem; let peer: EnginePeer? }
final class StatsStoryHost {
    let context: AccountContext
    let chatInteraction: ChatInteraction
    var closed = false
    init(_ context: AccountContext) { self.context = context; chatInteraction = ChatInteraction(chatLocation: .peer(2), context: context) }
    func close() { closed = true }
    func action() -> (StoryContentItem) -> Void {
        let context = self.context
        return { [weak self] story in
__STORY_STATS_ACTION__
        }
    }
}
struct MenuData { let message: Message }
func statsMenuAction(_ context: AccountContext, _ chatInteraction: ChatInteraction, _ message: Message) -> () -> Void {
    let data = MenuData(message: message)
    let messageId = message.id
    return {
__MESSAGE_STATS_ACTION__
    }
}
final class StoryStatsOpeningTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    let item = EngineStoryItem(id: 1)
    let peer = Peer(id: 2)
    let message = Message(id: MessageId(peerId: 2, id: 7), peers: [2: Peer(id: 2)])
    override func setUp() {
        Probe.shown = []; Probe.setup = nil; Probe.onShow = nil
        Probe.state = .single(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        StatsProbe.updates = []; StatsProbe.graph = nil; StatsProbe.onUpdate = nil
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installStatsBridges()
    }
    override func tearDown() {
        Probe.shown = []; Probe.setup = nil; Probe.onShow = nil
        StatsProbe.graph = nil; StatsProbe.onUpdate = nil
        context = nil; Analytics.shared = Analytics()
    }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
    func stats() throws -> StatsSurface { try XCTUnwrap(context.bindings.navigation.controller as? StatsSurface) }
    func viewer() throws -> StoryModalController<AccountContext> { try XCTUnwrap(Probe.shown.last as? StoryModalController<AccountContext>) }
    func testStoryStatsSourceClosesViewerAndPreservesOrdinaryScope() throws {
        let host = StatsStoryHost(context); let original = origin()
        host.chatInteraction.inheritedAnalyticsContext = original
        host.action()(StoryContentItem(storyItem: item, peer: peer))
        XCTAssertTrue(host.closed); XCTAssertTrue(try stats().analyticsContext?.scope === original.scope)
        try stats().open(.story(Peer(id: 3), item)); pump()
        XCTAssertTrue(try viewer().analyticsContext?.scope === original.scope)
        XCTAssertEqual(StatsProbe.updates, [[3]])
    }
    func testPrivateStoryStatsSourceCannotBecomeOrdinaryForwardedStory() throws {
        let host = StatsStoryHost(context); host.chatInteraction.inheritedAnalyticsContext = origin(.excluded)
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        host.action()(StoryContentItem(storyItem: item, peer: peer))
        XCTAssertTrue(host.closed); XCTAssertTrue(try stats().analyticsContext?.isExcluded == true)
        try stats().open(.story(Peer(id: 3), item)); pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testReleasedStoryOwnerUsesUnresolvedProvenance() throws {
        var host: StatsStoryHost? = StatsStoryHost(context)
        let action = host!.action(); host = nil
        action(StoryContentItem(storyItem: item, peer: peer))
        XCTAssertTrue(try stats().analyticsContext?.isExcluded == true)
    }
    func testMessageMenuCapturesSourceAndRetainsOrdinaryScope() throws {
        let interaction = ChatInteraction(chatLocation: .peer(2), context: context)
        let original = origin(); interaction.inheritedAnalyticsContext = original
        statsMenuAction(context, interaction, message)()
        XCTAssertTrue(try stats().analyticsContext?.scope === original.scope)
        try stats().open(.story(peer, item)); pump()
        XCTAssertTrue(try viewer().analyticsContext?.scope === original.scope)
    }
    func testSecretMediaInMessageMenuIsDeniedBeforeStatsConstruction() throws {
        let interaction = ChatInteraction(chatLocation: .peer(2), context: context)
        interaction.inheritedAnalyticsContext = origin()
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var secret = message; secret.containsSecretMedia = true
        statsMenuAction(context, interaction, secret)()
        XCTAssertTrue(try stats().analyticsContext?.isExcluded == true)
    }
    func testSecretPeerStatsSubjectAndMissingOriginAreExcluded() {
        let supplied = origin()
        let secret = MessageStatsController(context, subject: .messageId(MessageId(peerId: -2, id: 1)), analyticsContext: supplied)
        XCTAssertTrue(secret.analyticsContext?.isExcluded == true)
        let unknown = MessageStatsController(context, subject: .story(item, peer))
        XCTAssertTrue(unknown.analyticsContext?.isExcluded == true)
    }
    func testOrdinaryForwardedMessageRetainsScopeAndFocus() throws {
        let original = origin()
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: original)
        controller.open(.message(EngineMessage(message)))
        let chat = try XCTUnwrap(context.bindings.navigation.controller as? ChatAdditionController)
        XCTAssertTrue(chat.analyticsContext?.scope === original.scope)
        XCTAssertEqual(chat.focusTarget.messageId, message.id)
        XCTAssertEqual(chat.chatLocation.peerId, message.id.peerId)
        XCTAssertEqual(StatsProbe.updates, [[2]])
    }
    func testPrivateForwardedMessageProtectsChatFactoryAndPeerUpdate() throws {
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: origin())
        var secret = message; secret.containsSecretMedia = true
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        StatsProbe.onUpdate = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        controller.open(.message(EngineMessage(secret)))
        let chat = try XCTUnwrap(context.bindings.navigation.controller as? ChatAdditionController)
        XCTAssertTrue(chat.analyticsContext?.isExcluded == true)
        XCTAssertEqual(StatsProbe.updates, [[2]])
    }
    func testPrivateStatsOriginRemainsPrivateForOrdinaryForwardedMessage() throws {
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: origin(.excluded))
        controller.open(.message(EngineMessage(message)))
        let chat = try XCTUnwrap(context.bindings.navigation.controller as? ChatAdditionController)
        XCTAssertTrue(chat.analyticsContext?.isExcluded == true)
    }
    func testDeferredPeerUpdateKeepsPrivateLifetimeAfterScreenRelease() {
        var controller: StatsSurface? = MessageStatsController(context, subject: .story(item, peer), analyticsContext: origin(.excluded))
        context.account.postbox.deferTransactions = true
        controller?.open(.message(EngineMessage(message))); controller = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        StatsProbe.onUpdate = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let pending = context.account.postbox.pendingTransactions
        context.account.postbox.pendingTransactions = []
        pending.forEach { $0() }
        XCTAssertEqual(StatsProbe.updates, [[2]])
    }
    func testAccountSwitchBeforeDeferredPeerUpdateKeepsDeniedOrigin() {
        let original = origin()
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: original)
        context.account.postbox.deferTransactions = true
        controller.open(.message(EngineMessage(message)))
        let other = AccountContext(); hub.policy.setOwner(other.account)
        StatsProbe.onUpdate = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let pending = context.account.postbox.pendingTransactions
        context.account.postbox.pendingTransactions = []
        pending.forEach { $0() }
        XCTAssertEqual(StatsProbe.updates, [[2]])
        XCTAssertFalse(original.scope?.isValid ?? true)
    }
    func testAccountSwitchBeforeSelectionCannotRegrant() throws {
        let original = origin()
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: original)
        let other = AccountContext(); hub.policy.setOwner(other.account)
        controller.open(.story(peer, item)); pump()
        XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testRevocationBeforeSelectionCannotRegrant() throws {
        let original = origin()
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: original)
        original.scope?.exclude()
        controller.open(.story(peer, item)); pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testGraphProviderAndLateResultRemainExcluded() {
        var subscriber: Subscriber<StatsGraph?, NoError>?
        StatsProbe.graph = { _, _ in
            XCTAssertTrue(self.hub.policy.hasExclusions)
            return Signal { subscriber = $0; return ActionDisposable { XCTAssertTrue(self.hub.policy.hasExclusions) } }
        }
        var controller: StatsSurface? = MessageStatsController(context, subject: .story(item, peer), analyticsContext: origin(.excluded))
        var received: StatsGraph?
        let disposable = controller?.graph(1, 2).start(next: { value in
            XCTAssertTrue(self.hub.policy.hasExclusions); received = value
        })
        controller = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        subscriber?.putNext(3); subscriber?.putCompletion(); subscriber = nil
        XCTAssertEqual(received, 3); disposable?.dispose()
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testLegacyChatFallbackReceivesExplicitUnresolvedContext() throws {
        StatisticsHooks.shared.openMessageWithContext = nil
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: origin(.excluded))
        controller.open(.message(EngineMessage(message)))
        let chat = try XCTUnwrap(context.bindings.navigation.controller as? ChatAdditionController)
        XCTAssertTrue(chat.analyticsContext?.isExcluded == true)
        XCTAssertNil(chat.analyticsContext?.scope)
    }
    func testDirectLegacyChatOpeningProtectsConstructionBeforeInheritance() throws {
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        StatisticsHooks.shared.openMessage(context, message.id)
        let chat = try XCTUnwrap(context.bindings.navigation.controller as? ChatAdditionController)
        XCTAssertTrue(chat.analyticsContext?.isExcluded == true)
    }
    func testGraphMissingProviderCompletesWithoutInventedOutcome() {
        let controller = MessageStatsController(context, subject: .story(item, peer), analyticsContext: origin())
        var values = 0, completed = false
        _ = controller.graph(1, 2).start(next: { value in
            values += 1; XCTAssertNil(value)
        }, completed: { completed = true })
        XCTAssertEqual(values, 1); XCTAssertTrue(completed)
    }
    func testLegacyStatsOpenFallbackIsFunctionalButUnresolved() throws {
        FeatureNavigationHooks.shared.openStoryStatsWithContext = nil
        FeatureNavigationHooks.shared.openStoryStatsObserved(context, item, peer, analyticsContext: origin())
        XCTAssertTrue(try stats().analyticsContext?.isExcluded == true)
        ChatNavigationHooks.shared.pushMessageStatsWithContext = nil
        ChatNavigationHooks.shared.pushMessageStatsObserved(context, message, analyticsContext: origin())
        XCTAssertTrue(try stats().analyticsContext?.isExcluded == true)
        StatisticsHooks.shared.showStoryWithContext = nil
        try stats().open(.story(peer, item)); pump()
        XCTAssertNil(try viewer().analyticsContext?.scope)
    }
}
