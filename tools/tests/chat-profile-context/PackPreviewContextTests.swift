enum StickerPackReference: Hashable, ExpressibleByIntegerLiteral {
    case id(id: Int64, accessHash: Int64), name(String)
    init(integerLiteral value: Int64) { self = .id(id: value, accessHash: 0) }
}
enum StickerPackPreviewSource: Hashable {
    case stickers(StickerPackReference), emoji(StickerPackReference)
    var reference: StickerPackReference { switch self { case let .stickers(id), let .emoji(id): return id } }
}
struct ItemCollectionId { typealias Namespace = Int }
extension Namespaces { enum ItemCollection { static let CloudStickerPacks = 1; static let CloudEmojiPacks = 2 } }
struct PackCollectionId: Equatable { let id: Int64 }
struct PackInfo {
    let id: PackCollectionId
    var accessHash: Int64 { 0 }
    var title: String { "Pack" }
    var shortName: String { String(id.id) }
    init(id: Int64) { self.id = PackCollectionId(id: id) }
    func _parse() -> PackInfo { self }
}
struct TelegramMediaFile { let fileId: Int64 }
struct StickerPackItem: ExpressibleByIntegerLiteral {
    let file: TelegramMediaFile
    init(integerLiteral value: Int64) { file = TelegramMediaFile(fileId: value) }
}
enum PackResult { case none, fetching, result(PackInfo, [StickerPackItem], Bool) }
enum PreviewState {
    enum Source { case stickers, emoji }
    struct Collection { let info: PackInfo; let items: [StickerPackItem]; let installed: Bool }
    case loading(Source), loaded(source: Source, collections: [Collection])
}
struct PreviewStateEquatable { let value: PreviewState; init(_ value: PreviewState) { self.value = value } }
struct PackState: Equatable {
    var preview: PreviewStateEquatable
    var installed: Set<StickerPackPreviewSource>
    var premiumFile: Int?
    static func == (lhs: PackState, rhs: PackState) -> Bool { false }
}
extension CommonStrings { var stickerSetDontExist: String { "Not found" } }
func alert(for window: Int, info: String) { PackProbe.check?(); PackProbe.alerts += 1 }
final class PackContent: ViewController {
    let subscription = MetaDisposable()
    var onDeinit: (() -> Void)?
    var didAppear: (Int) -> Void = { _ in }
    init(_ signal: Signal<InputDataSignalValue, NoError>) { super.init(); PackProbe.check?(); subscription.set(signal.start()) }
    deinit { subscription.dispose(); onDeinit?() }
}
final class ReactionStickerModal: ViewController {
    let content: PackContent
    var reload: () -> Void = {}
    var getOrigin: () -> AnalyticsContext = { Analytics.shared.unresolvedContext() }
    var dismiss: () -> Void = {}
    init(_ content: PackContent) { self.content = content; super.init(); PackProbe.check?() }
    func close() { PackProbe.check?(); PackProbe.closes += 1 }
}
extension SavedStickers {
    func loadedStickerPack(reference: StickerPackReference, forceActualized: Bool) -> Signal<PackResult, NoError> {
        PackProbe.check?(); PackProbe.references.append(reference)
        return Signal { sink in
            PackProbe.check?(); PackProbe.sinks.append(sink)
            return ActionDisposable { PackProbe.check?(); PackProbe.disposals += 1 }
        }
    }
}
func packEntries(_ state: PackState) -> [CommonEntry] { PackProbe.check?(); PackProbe.renders += 1; return [] }
__PACK_SOURCE_MAP__
func installPackBridge() {
    var hooks = ChatMediaUIHooks.shared
__PACK_BRIDGE__
    ChatMediaUIHooks.shared = hooks
}
func StickerPackPreviewModalController(_ context: any AccountContextProtocol, peerId: PeerId?, references: [StickerPackPreviewSource], analyticsContext: AnalyticsContext? = nil) -> ReactionStickerModal {
__PACK_PREFIX__
    var close: (() -> Void)?
__PACK_RELOAD__
__PACK_RENDER__
    let controller = PackContent(signal)
__PACK_CONTROLLER__
__PACK_CLEANUP__
    let modalController = ReactionStickerModal(controller)
__PACK_MODALCONTROLLER__
__PACK_CLOSE__
    modalController.getOrigin = getAnalyticsContext
    modalController.reload = reload
    modalController.dismiss = { close?() }
__PACK_LOADING__
    let applyState: (PackState) -> Void = { state in
__PACK_APPLY_GUARD__
        PackProbe.check?(); PackProbe.applies += 1
    }
__PACK_STATE_SUBSCRIPTION__
    return modalController
}
func packReactionAction(context: any AccountContextProtocol, message: Message, origin: AnalyticsContext) -> () -> Void {
    let sources: [ChatMediaStickerPackPreviewSource] = [.emoji(42)]
    return {
__PACK_REACTION_ACTION__
    }
}
enum PackProbe {
    static var check: (() -> Void)?
    static var presented: ReactionStickerModal?
    static var references: [StickerPackReference] = []
    static var sinks: [Subscriber<PackResult, NoError>] = []
    static var disposals = 0
    static var renders = 0
    static var applies = 0
    static var alerts = 0
    static var closes = 0
    static func reset() {
        check = nil; presented = nil; sinks = []; references = []; disposals = 0; renders = 0; applies = 0; alerts = 0; closes = 0
    }
}
final class PackPreviewContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        PackProbe.reset(); TagProbe.reset(); Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        ChatMediaUIHooks.shared = ChatMediaUIHooks(); installPackBridge()
    }
    override func tearDown() { PackProbe.reset(); TagProbe.reset(); context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func open(_ source: AnalyticsContext? = nil, peer: PeerId? = 2, references: [StickerPackPreviewSource] = [.emoji(42)]) -> ReactionStickerModal {
        StickerPackPreviewModalController(context, peerId: peer, references: references, analyticsContext: source)
    }
    func expectExcluded() { PackProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testReactionEntryPreservesOrdinaryOriginBeforeFactoryAndIntoContent() {
        let source = origin(); packReactionAction(context: context, message: Message(id: MessageId(peerId: 2, id: 7)), origin: source)()
        XCTAssertTrue(PackProbe.presented?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(PackProbe.presented?.content.analyticsContext?.scope === source.scope)
        XCTAssertEqual(PackProbe.references, [42]); XCTAssertEqual(PackProbe.alerts, 0)
    }
    func testPrivateReactionOriginSurvivesOrdinaryPackDestinationAndDelayedLoading() {
        expectExcluded(); packReactionAction(context: context, message: Message(id: MessageId(peerId: 2, id: 7)), origin: origin(.excluded))()
        PackProbe.sinks.first?.putNext(.result(PackInfo(id: 42), [1], true))
        PackProbe.presented?.content.didAppear(0); PackProbe.presented?.dismiss()
        XCTAssertTrue(PackProbe.presented?.analyticsContext?.isExcluded == true)
        XCTAssertGreaterThan(PackProbe.renders, 1); XCTAssertEqual(PackProbe.closes, 1)
    }
    func testPrivateOrUnknownPeerAndMissingOriginAreFailClosed() {
        for peer in [Int64(-1), 0, 2] {
            expectExcluded(); let modal = open(peer == 2 ? nil : origin(), peer: peer)
            XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
        }
    }
    func testReloadDisposesPreviousFetchAndRetainsPrivateOrigin() {
        expectExcluded(); let modal = open(origin(.excluded)); let old = PackProbe.sinks.first
        modal.reload(); XCTAssertEqual(PackProbe.references, [42, 42]); XCTAssertEqual(PackProbe.disposals, 1)
        let count = PackProbe.renders; old?.putNext(.none); XCTAssertEqual(PackProbe.renders, count)
        PackProbe.sinks.last?.putNext(.result(PackInfo(id: 42), [], false)); XCTAssertGreaterThan(PackProbe.renders, count)
    }
    func testOwnerReleaseDisposesPendingPackFetchAndEndsExclusion() {
        expectExcluded(); var modal: ReactionStickerModal? = open(origin(.excluded)); let sink = PackProbe.sinks.first
        weak var weakModal = modal; modal = nil
        XCTAssertNil(weakModal); XCTAssertEqual(PackProbe.disposals, 1); XCTAssertFalse(hub.policy.hasExclusions)
        sink?.putNext(.none); XCTAssertEqual(PackProbe.alerts, 0)
    }
    func testOriginGetterRetainsPrivateAncestryAfterControllerRelease() {
        var modal: ReactionStickerModal? = open(origin(.excluded)); let getOrigin = modal!.getOrigin; modal = nil
        let resolved = getOrigin(); XCTAssertTrue(resolved.isExcluded); XCTAssertNil(resolved.scope)
    }
    func testOrdinaryGetterKeepsOriginalScopeAfterReleaseAndCannotRenewAfterAccountChange() {
        let source = origin(); var modal: ReactionStickerModal? = open(source, peer: nil); let getOrigin = modal!.getOrigin; modal = nil
        XCTAssertTrue(getOrigin().scope === source.scope)
        let other = AccountContext(); hub.policy.setOwner(other.account); XCTAssertNil(getOrigin().scope)
    }
    func testDeferredRenderingAndLaterRevocationRemainExcluded() {
        TagProbe.deferRendering = true; let source = origin(); let modal = open(source)
        source.scope?.exclude(); expectExcluded(); TagProbe.renderGate.set(true)
        modal.content.didAppear(0); modal.reload(); XCTAssertFalse(modal.getOrigin().scope?.isValid == true)
    }
    func testEmptyReferencesUseMissingPackBehaviorWithoutIndexCrash() {
        expectExcluded(); let modal = open(origin(.excluded), references: [])
        XCTAssertTrue(PackProbe.references.isEmpty); XCTAssertEqual(PackProbe.alerts, 1); XCTAssertEqual(PackProbe.closes, 1)
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
    }
    func testLegacyHookAndDisabledCollectionRemainFunctionalWithoutGrant() {
        ChatMediaUIHooks.shared.makeStickerPackPreviewWithContext = nil; hub.policy.isEnabled = false; expectExcluded()
        packReactionAction(context: context, message: Message(id: MessageId(peerId: 2, id: 7)), origin: origin(.excluded))()
        XCTAssertTrue(PackProbe.presented?.content.analyticsContext?.isExcluded == true)
        XCTAssertEqual(PackProbe.references, [42])
    }
}
