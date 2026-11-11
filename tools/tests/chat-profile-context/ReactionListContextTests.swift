typealias CGImage = Int
extension Peer { var isGroup: Bool { true }; var isSupergroup: Bool { false } }
extension CommonStrings {
    var chatReactionContextFilterByTag: String { "Filter" }
    var chatReactionContextRemoveTag: String { "Remove" }
    func chatContextMessageContainsEmojiOther(_ count: Int) -> String { "Pack" }
}
enum MenuAnimation {
    case menu_tag_filter, menu_tag_rename, menu_tag_remove
    var value: Int { 0 }
}
class ContextMenuItem {
    enum Mode { case destruct }
    let handler: () -> Void
    var image: Int? { didSet { ReactionListProbe.check?() } }
    init(_ title: String, handler: @escaping () -> Void, itemMode: Mode? = nil, itemImage: Int? = nil) { self.handler = handler; ReactionListProbe.check?() }
}
final class ContextSeparatorItem: ContextMenuItem { init() { super.init("", handler: {}) } }
final class ContextMenu {
    var items: [ContextMenuItem] = [] { didSet { ReactionListProbe.check?() } }
    var loadMore: (() -> Void)?
    init() { ReactionListProbe.check?() }
    func addItem(_ item: ContextMenuItem) { items.append(item) }
}
struct ReactionListFile {
    var emojiReference: StickerPackReference? { nil }
    var staticIcon: ReactionListFile { self }
    func _parse() -> ReactionListFile { self }
}
final class ReactionPeerMenu: ContextMenuItem {
    enum Source { case builtin(ReactionListFile), custom(Int64, ReactionListFile?), stars(ReactionListFile, ReactionListFile?) }
    init(title: String, handler: @escaping () -> Void, peer: Peer, context: any AccountContextProtocol, reaction: Source, readTimestamp: Int32?, message: Message, canDelete: Bool, analyticsContext: AnalyticsContext) { super.init(title, handler: handler) }
}
func canDeleteReactionsInChat(message: Message) -> Bool { false }
enum ChatMediaStickerPackPreviewSource { case emoji(StickerPackReference), stickers(StickerPackReference) }
struct ChatMediaUIHooks {
    static var shared = ChatMediaUIHooks()
    var makeStickerPackPreview: (any AccountContextProtocol, PeerId?, [ChatMediaStickerPackPreviewSource]) -> ReactionStickerModal = { context, peerId, sources in
        StickerPackPreviewModalController(context, peerId: peerId, references: sources.map(mapChatMediaStickerPackPreviewSource))
    }
__PACK_HOOK__
}
func showModal(with controller: ReactionStickerModal, for window: Int) { PackProbe.check?(); PackProbe.presented = controller }
final class MessageContainsPacksMenuItem: ContextMenuItem {
    init(title: String, handler: @escaping () -> Void, packs: [StickerPackReference], context: any AccountContextProtocol) { super.init(title, handler: handler) }
}
final class EngineMessageReactionListContext {
    struct Item { let peer: Peer; let timestamp: Int32? }
    struct State { let items: [Item]; let canLoadMore: Bool }
    var state: Signal<State, NoError> {
        ReactionListProbe.check?()
        return Signal { sink in
            ReactionListProbe.check?(); ReactionListProbe.stateSink = sink
            return ActionDisposable { ReactionListProbe.check?(); ReactionListProbe.disposals += 1 }
        }
    }
    func loadMore() { ReactionListProbe.check?(); ReactionListProbe.pages += 1 }
}
extension Engine.Messages {
    func messageReactionList(message: EngineMessage, readStats: Int?, reaction: MessageReaction.Reaction) -> EngineMessageReactionListContext {
        ReactionListProbe.check?(); ReactionListProbe.providers += 1; return EngineMessageReactionListContext()
    }
}
final class ReactionListModel {
    enum Source { case builtin(ReactionListFile), custom(Int64, ReactionListFile?, ReactionListFile?), stars(ReactionListFile, ReactionListFile?) }
    let analyticsContext: AnalyticsContext
    let context: any AccountContextProtocol
    let message: Message
    let value = MessageReaction(value: .builtin("tag"))
    let text: BadgeText? = nil
    let currentTag: MessageReaction.Reaction? = nil
    let source: Source = .builtin(ReactionListFile())
    var canViewList = true
    let disposable = MetaDisposable()
    let delayDisposable = MetaDisposable()
    let action: (MessageReaction.Reaction, Bool) -> Void = { _, _ in }
    let openInfo: (PeerId) -> Void
    private var menu: ContextMenu?
    private var reactions: EngineMessageReactionListContext?
    private let avatarDisposable = MetaDisposable()
    init(context: any AccountContextProtocol, message: Message, analyticsContext: AnalyticsContext?, openInfo: @escaping (PeerId) -> Void) {
__REACTION_LIST_ADMISSION__
        self.context = context; self.message = message; self.openInfo = openInfo
    }
__REACTION_LIST_METHODS__
}
func installReactionProfileBridge() {
    var hooks = ChatHistoryUIHooks.shared
__REACTION_PROFILE_BRIDGE__
    ChatHistoryUIHooks.shared = hooks
}
func makeReactionListRow(_ chatInteraction: ChatInteraction, message: Message) -> ReactionListModel {
    let context = chatInteraction.interactionContext
__REACTION_PROFILE_ORIGIN__
    return ReactionListModel(context: context, message: message, analyticsContext: origin, openInfo: { peerId in
__REACTION_PROFILE_ROW__
    })
}
enum ReactionListProbe {
    static var check: (() -> Void)?
    static var stateSink: Subscriber<EngineMessageReactionListContext.State, NoError>?
    static var avatarSinks: [Subscriber<(Int?, Bool), NoError>] = []
    static var providers = 0
    static var disposals = 0
    static var avatarDisposals = 0
    static var pages = 0
    static var legacyCalls = 0
    static var profileSources: [PeerInfoController.Source] = []
    static func avatar(_ peerId: PeerId) -> Signal<(Int?, Bool), NoError> {
        check?()
        return Signal { sink in
            check?(); avatarSinks.append(sink)
            return ActionDisposable { check?(); avatarDisposals += 1 }
        }
    }
    static func reset() {
        check = nil; stateSink = nil; avatarSinks = []; providers = 0; disposals = 0
        avatarDisposals = 0; pages = 0; legacyCalls = 0; profileSources = []
    }
}
final class ReactionListContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        ReactionListProbe.reset(); Probe.profiles = []; Probe.construction = nil
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        ChatHistoryUIHooks.shared = ChatHistoryUIHooks(); installReactionProfileBridge()
    }
    override func tearDown() { Probe.construction = nil; ReactionListProbe.reset(); Probe.profiles = []; context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func row(_ source: AnalyticsContext, secret: Bool = false, sourcePeer: PeerId = 2) -> ReactionListModel {
        let parent = ChatInteraction(context, location: .peer(sourcePeer)); parent.inheritedAnalyticsContext = source
        return makeReactionListRow(parent, message: Message(id: MessageId(peerId: sourcePeer, id: 7), containsSecretMedia: secret))
    }
    func deliver(_ peers: [PeerId] = [3], more: Bool = false) {
        ReactionListProbe.stateSink?.putNext(.init(items: peers.map { .init(peer: Peer($0), timestamp: 9) }, canLoadMore: more))
    }
    func finish() {
        ReactionListProbe.stateSink?.putCompletion()
        for sink in ReactionListProbe.avatarSinks { sink.putCompletion() }
    }
    func expectExcluded() { ReactionListProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }; Probe.construction = ReactionListProbe.check }
    func testOrdinaryProfilePreservesOriginalScopeAndReactionMessageSource() {
        let source = origin(); let row = row(source); let menu = row.loadMenu()!
        deliver(); finish(); menu.items.first?.handler()
        XCTAssertEqual(ReactionListProbe.providers, 1); XCTAssertEqual(Probe.profiles.last?.peerId, 3)
        XCTAssertTrue(Probe.profiles.last?.origin?.scope === source.scope)
        XCTAssertEqual(ReactionListProbe.profileSources, [.reaction(row.message.id)])
    }
    func testPrivateSourceProtectsLoadingRowsAvatarsPaginationAndProfileAfterCompletion() {
        let row = row(origin(.excluded)); expectExcluded(); let menu = row.loadMenu()!
        deliver(more: true); menu.loadMore?()
        ReactionListProbe.avatarSinks.first?.putNext((5, false)); XCTAssertEqual(menu.items.first?.image, 5)
        finish(); XCTAssertFalse(hub.policy.hasExclusions); menu.items.first?.handler()
        XCTAssertEqual(ReactionListProbe.pages, 1); XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
        XCTAssertEqual(ReactionListProbe.disposals, 1); XCTAssertEqual(ReactionListProbe.avatarDisposals, 1)
    }
    func testSecretMediaAndUnknownSourceCannotReachProfileWithGrant() {
        for (secret, peer) in [(true, Int64(2)), (false, Int64(0)), (false, Int64(-1))] {
            let row = row(origin(), secret: secret, sourcePeer: peer); expectExcluded(); let menu = row.loadMenu()!
            deliver(); finish(); menu.items.first?.handler()
            XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
        }
    }
    func testPrivateSelectedPeerRestrictsAvatarAndProfile() {
        let row = row(origin()); let menu = row.loadMenu()!
        expectExcluded(); deliver([-1]); finish(); menu.items.first?.handler()
        XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
    }
    func testDisabledAndLegacyRowsRemainFunctionalWithoutGrant() {
        hub.policy.isEnabled = false
        let row = ReactionListModel(context: context, message: Message(id: MessageId(peerId: 2, id: 8)), analyticsContext: nil, openInfo: { _ in ReactionListProbe.legacyCalls += 1; ReactionListProbe.check?() })
        expectExcluded(); let menu = row.loadMenu()!; deliver(); finish(); menu.items.first?.handler()
        XCTAssertEqual(ReactionListProbe.legacyCalls, 1)
    }
    func testRetainedProfileHandlerRevalidatesAccountAfterLoadingEnds() {
        let row = row(origin()); let menu = row.loadMenu()!; deliver(); finish()
        let other = AccountContext(); hub.policy.setOwner(other.account); expectExcluded(); menu.items.first?.handler()
        XCTAssertNil(Probe.profiles.last?.origin?.scope); XCTAssertEqual(Probe.profiles.count, 1)
    }
    func testRevokedCachedMenuCannotAcquireNewProfileScope() {
        let source = origin(); let row = row(source); let menu = row.loadMenu()!; deliver(); finish()
        source.scope?.exclude(); expectExcluded(); XCTAssertTrue(row.loadMenu() === menu); menu.items.first?.handler()
        XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
        XCTAssertEqual(ReactionListProbe.providers, 1)
    }
    func testCancellationGuardsProviderDisposalAndStopsDelivery() {
        let row = row(origin(.excluded)); expectExcluded(); let menu = row.loadMenu()!; row.cancelMenu()
        deliver(); XCTAssertTrue(menu.items.isEmpty); XCTAssertEqual(ReactionListProbe.disposals, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testReleasedReactionKeepsExistingNoNavigationBehavior() {
        var row: ReactionListModel? = row(origin(.excluded)); let menu = row!.loadMenu()!; deliver(); finish()
        weak var weakRow = row; row = nil; XCTAssertNil(weakRow); expectExcluded(); menu.items.first?.handler(); menu.loadMore?()
        XCTAssertTrue(Probe.profiles.isEmpty); XCTAssertEqual(ReactionListProbe.pages, 0)
    }
    func testUnavailableListDoesNotStartProvider() {
        let row = row(origin(.excluded)); row.canViewList = false; expectExcluded()
        XCTAssertNil(row.loadMenu()); XCTAssertEqual(ReactionListProbe.providers, 0)
    }
    func testObservedLegacyHookKeepsGuardAndSourceValidation() {
        ChatHistoryUIHooks.shared.pushReactionPeerInfoWithContext = nil; expectExcluded()
        ChatHistoryUIHooks.shared.pushReactionPeerInfoObserved(context.bindings.rootNavigation(), context, 3, MessageId(peerId: -1, id: 7), analyticsContext: origin())
        XCTAssertEqual(ReactionListProbe.legacyCalls, 1); XCTAssertTrue(Probe.profiles.isEmpty)
    }
    func testOwnerReleaseDisposesPendingStateAndAvatarWork() {
        var row: ReactionListModel? = row(origin(.excluded)); expectExcluded()
        let menu = row!.loadMenu()!; deliver()
        let pendingAvatar = ReactionListProbe.avatarSinks.first
        weak var weakRow = row; row = nil
        XCTAssertNil(weakRow); XCTAssertEqual(ReactionListProbe.disposals, 1); XCTAssertEqual(ReactionListProbe.avatarDisposals, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
        pendingAvatar?.putNext((8, false)); XCTAssertNil(menu.items.first?.image)
    }
    func testStateReplacementDisposesOldAvatarsBeforeUpdatingRows() {
        let row = row(origin(.excluded)); expectExcluded(); let menu = row.loadMenu()!
        deliver([3]); let oldAvatar = ReactionListProbe.avatarSinks.first
        deliver([4]); XCTAssertEqual(ReactionListProbe.avatarDisposals, 1)
        oldAvatar?.putNext((8, false)); XCTAssertNil(menu.items.first?.image)
        finish(); XCTAssertEqual(ReactionListProbe.avatarDisposals, 2)
        menu.items.first?.handler(); XCTAssertEqual(Probe.profiles.last?.peerId, 4)
    }
}
