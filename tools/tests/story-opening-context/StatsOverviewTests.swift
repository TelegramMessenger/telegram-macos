typealias ViewController = ModalViewController
struct SectionControllerItem { let title: () -> String; let controller: ViewController }
class SectionViewController: ViewController {
    let sections: [SectionControllerItem]
    init(sections: [SectionControllerItem], selected: Int, hasBar: Bool) {
        self.sections = sections; super.init(); Probe.setup?()
    }
}
final class ChannelStatsSegmentController: SectionViewController {
    let stats: ViewController
    let boosts: ViewController
    let monetization: ViewController?
    let stars: ViewController?
    let context: any AccountContextProtocol
    let peerId: PeerId
    let onlyMonetization: Bool
__SEGMENT__
}
struct PeerEquatable { let peer: Peer }
enum StatsPostItem { case message(Message, Int); case story(EngineStoryItem, PeerEquatable, Int) }
final class OverviewSurface: ViewController {
    var openPost: (StatsPostItem) -> Void = { _ in }
    var openPeer: (PeerId) -> Void = { _ in }
}
func ChannelStatsViewController(_ context: any AccountContextProtocol, peerId: PeerId, analyticsContext: AnalyticsContext? = nil) -> ViewController {
__CHANNEL_PREFIX__
    Probe.setup?()
    let controller = OverviewSurface()
__CHANNEL_CONTEXT__
__OPEN_POST__
    controller.openPost = openPost
    return controller
}
func GroupStatsViewController(_ context: any AccountContextProtocol, peerId: PeerId, analyticsContext: AnalyticsContext? = nil) -> ViewController {
__GROUP_PREFIX__
    Probe.setup?()
    let controller = OverviewSurface()
__GROUP_CONTEXT__
__OPEN_GROUP_PEER__
    controller.openPeer = openPeerInfo
    return controller
}
enum OverviewProbe {
    static var childContext: AnalyticsContext?
    static var frozen = false
    static var frozenAlerts = 0
    static var lookup: Signal<ProfilePeerView, NoError> = .single(ProfilePeerView(peer: Peer(id: 2), monoforum: nil))
    static var onLookup: (() -> Void)?
    static var initialMediaContext: AnalyticsContext?
    static func makeChild() -> ViewController {
        Probe.setup?(); let child = ViewController(); child.analyticsContext = childContext; return child
    }
}
typealias NavigationViewController = Navigation
typealias ThreadInfo = Int
typealias PeerExpiringStoryListContext = Int
typealias PeerMediaCollectionMode = Int
typealias ProfileGiftsContext = Int
typealias TelegramChannel = Peer
enum ViewControllerState { case Normal, Edit }
struct ProfilePeerView { let peer: Peer?; let monoforum: Peer? }
func peerViewMainPeer(_ view: ProfilePeerView) -> Peer? { view.peer }
func peerViewMonoforumMainPeer(_ view: ProfilePeerView) -> Peer? { view.monoforum }
extension AccountContextProtocol {
    var isFrozen: Bool { OverviewProbe.frozen }
    var contentSettings: Int { 0 }
}
extension Postbox {
    func peerView(id: PeerId) -> Signal<ProfilePeerView, NoError> { OverviewProbe.onLookup?(); return OverviewProbe.lookup }
}
struct PeerInfoUIHooks {
    static let shared = PeerInfoUIHooks()
    func freezeAlert(_ context: any AccountContextProtocol) { OverviewProbe.frozenAlerts += 1; Probe.setup?() }
}
final class ProfileMedia: ViewController {
    var mode: Int?
    func setMode(_ mode: Int) { self.mode = mode }
    func inheritAnalyticsContext(_ inherited: AnalyticsContext) {
        if inherited.isExcluded { analyticsContext?.scope?.exclude() }
        if let current = analyticsContext, current.isExcluded || (!inherited.isExcluded && current.scope?.isValid != true) { return }
        analyticsContext = inherited
    }
}
final class ProfileView {
    var shakes = 0
    func shake(beep: Bool) { shakes += 1 }
}
final class PeerInfoController<Context: AccountContextProtocol>: ViewController {
    enum Source { case none }
    let context: Context
    let peerId: PeerId
    let mediaController = ProfileMedia()
    let view = ProfileView()
    var state = ViewControllerState.Normal
    init(context: Context, peer: Peer, threadInfo: ThreadInfo? = nil, stories: PeerExpiringStoryListContext? = nil, isAd: Bool = false, source: Source = .none, mediaMode: PeerMediaCollectionMode? = nil, starGiftsProfile: ProfileGiftsContext? = nil, albumId: Int32? = nil, initialState: ViewControllerState = .Normal, analyticsContext: AnalyticsContext? = nil) {
        self.context = context; peerId = peer.id
        super.init(); self.analyticsContext = analyticsContext; Probe.setup?(); state = initialState
        mediaController.analyticsContext = OverviewProbe.initialMediaContext
    }
__PROFILE_PUSH__
}
final class ChannelBoostStatsController: ViewController {
    init(context: any AccountContextProtocol, peerId: PeerId) {
        super.init(); Probe.setup?(); analyticsContext = OverviewProbe.childContext
    }
}
struct ProfilePeer { let isSupergroup: Bool }
final class OverviewArguments {
    let context: AccountContext
    let peerId: PeerId
    var peer: ProfilePeer?
    var origin: AnalyticsContext
    var pushed: ViewController?
    init(_ context: AccountContext, peerId: PeerId, origin: AnalyticsContext) { self.context = context; self.peerId = peerId; self.origin = origin }
    func captureAnalyticsContext() -> AnalyticsContext { Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: origin) }
    func pushViewController(_ controller: ViewController) { pushed = controller }
__PROFILE_STATS__
__CHANNEL_STATS__
__GROUP_STATS__
}
final class StatsOverviewTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.shown = []; Probe.setup = nil; Probe.onShow = nil
        Probe.state = .single(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        OverviewProbe.childContext = nil; OverviewProbe.frozen = false; OverviewProbe.frozenAlerts = 0
        OverviewProbe.initialMediaContext = nil; OverviewProbe.onLookup = nil
        OverviewProbe.lookup = .single(ProfilePeerView(peer: Peer(id: 2), monoforum: nil))
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installStatsBridges()
    }
    override func tearDown() {
        Probe.shown = []; Probe.setup = nil; OverviewProbe.childContext = nil; OverviewProbe.onLookup = nil; OverviewProbe.initialMediaContext = nil
        context = nil; Analytics.shared = Analytics()
    }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
    func profile() throws -> PeerInfoController<AccountContext> { try XCTUnwrap(context.bindings.navigation.controller as? PeerInfoController<AccountContext>) }
    func testChannelTabsReceiveExactScopeBeforeSectionConstruction() {
        let original = origin()
        let segment = ChannelStatsSegmentController(context, peerId: 2, isChannel: true, monetization: true, stars: true, analyticsContext: original)
        XCTAssertEqual(segment.sections.count, 4)
        for item in segment.sections { XCTAssertTrue(item.controller.analyticsContext?.scope === original.scope) }
        XCTAssertTrue(segment.analyticsContext?.scope === original.scope)
    }
    func testPrivateGroupAndMonetizationOnlyConstructionIsProtected() {
        let original = origin(.excluded)
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let group = ChannelStatsSegmentController(context, peerId: 2, isChannel: false, analyticsContext: original)
        XCTAssertEqual(group.sections.count, 2)
        XCTAssertTrue(group.stats.analyticsContext?.isExcluded == true)
        let money = ChannelStatsSegmentController(context, peerId: 2, isChannel: true, monetization: true, stars: true, onlyMonetization: true, analyticsContext: original)
        XCTAssertEqual(money.sections.count, 2)
        XCTAssertTrue(money.sections.allSatisfy { $0.controller.analyticsContext?.isExcluded == true })
    }
    func testPrivateChildContextIsNeverOverwrittenByOrdinaryParent() {
        let original = origin(); OverviewProbe.childContext = origin(.excluded)
        let segment = ChannelStatsSegmentController(context, peerId: 2, isChannel: true, monetization: true, stars: true, analyticsContext: original)
        XCTAssertTrue(segment.boosts.analyticsContext?.isExcluded == true)
        XCTAssertTrue(segment.monetization?.analyticsContext?.isExcluded == true)
        XCTAssertTrue(segment.stars?.analyticsContext?.isExcluded == true)
    }
    func testUnknownAndSecretOverviewOriginsCannotGrant() {
        let unknown = ChannelStatsSegmentController(context, peerId: 2, isChannel: true)
        XCTAssertTrue(unknown.analyticsContext?.isExcluded == true)
        let secret = ChannelStatsSegmentController(context, peerId: -2, isChannel: true, analyticsContext: origin())
        XCTAssertTrue(secret.analyticsContext?.isExcluded == true)
    }
    func testChannelStoryAndMessageDetailsKeepScopeAndClassifySecretMedia() throws {
        let original = origin()
        let controller = try XCTUnwrap(ChannelStatsViewController(context, peerId: 2, analyticsContext: original) as? OverviewSurface)
        controller.openPost(.story(EngineStoryItem(id: 1), PeerEquatable(peer: Peer(id: 3)), 0))
        XCTAssertTrue((context.bindings.navigation.controller as? StatsSurface)?.analyticsContext?.scope === original.scope)
        controller.openPost(.message(Message(id: MessageId(peerId: 3, id: 1), containsSecretMedia: true), 0))
        XCTAssertTrue((context.bindings.navigation.controller as? StatsSurface)?.analyticsContext?.isExcluded == true)
    }
    func testGroupParticipantProfileKeepsScopeAcrossLookup() throws {
        let original = origin()
        let controller = try XCTUnwrap(GroupStatsViewController(context, peerId: 2, analyticsContext: original) as? OverviewSurface)
        controller.openPeer(2); pump()
        XCTAssertTrue(try profile().analyticsContext?.scope === original.scope)
        XCTAssertTrue(try profile().mediaController.analyticsContext?.scope === original.scope)
    }
    func testPrivateGroupProfileLookupSurvivesParentRelease() throws {
        var subscriber: Subscriber<ProfilePeerView, NoError>?
        OverviewProbe.lookup = Signal { subscriber = $0; return EmptyDisposable }
        var controller: OverviewSurface? = GroupStatsViewController(context, peerId: 2, analyticsContext: origin(.excluded)) as? OverviewSurface
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        OverviewProbe.onLookup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        controller?.openPeer(2); controller = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        subscriber?.putNext(ProfilePeerView(peer: Peer(id: 2), monoforum: nil)); subscriber = nil; pump()
        XCTAssertTrue(try profile().analyticsContext?.isExcluded == true)
    }
    func testExistingProfileTightensButCannotLosePrivateOrigin() throws {
        let original = origin()
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: original)
        pump(); let existing = try profile()
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, mediaMode: 4, initialState: .Edit, analyticsContext: origin(.excluded))
        XCTAssertTrue(existing.analyticsContext?.isExcluded == true)
        XCTAssertEqual(existing.state, .Edit); XCTAssertEqual(existing.mediaController.mode, 4)
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: origin())
        XCTAssertTrue(existing.analyticsContext?.isExcluded == true)
        XCTAssertEqual(context.bindings.navigation.pushes, 1); XCTAssertEqual(existing.view.shakes, 2)
    }
    func testExistingRevokedScopeIsNotReplacedByFreshOrdinaryOrigin() throws {
        let original = origin()
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: original)
        pump(); let existing = try profile()
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        let replacement = origin()
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: replacement)
        XCTAssertNil(existing.analyticsContext?.scope)
    }
    func testResolvedPrivatePeerIsClassifiedBeforeProfileConstruction() throws {
        OverviewProbe.lookup = .single(ProfilePeerView(peer: Peer(id: -2), monoforum: nil))
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: origin())
        pump(); XCTAssertTrue(try profile().analyticsContext?.isExcluded == true)
    }
    func testMonoforumResolutionPreservesRequestedPrivateOrigin() throws {
        OverviewProbe.lookup = .single(ProfilePeerView(peer: Peer(id: -2, isMonoForum: true, canManageDirect: false), monoforum: Peer(id: 3)))
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: -2, analyticsContext: origin())
        pump(); XCTAssertEqual(try profile().peerId, 3)
        XCTAssertTrue(try profile().analyticsContext?.isExcluded == true)
    }
    func testFrozenAndRestrictedProfilesKeepFunctionalGuards() {
        OverviewProbe.frozen = true
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: origin(.excluded))
        XCTAssertEqual(OverviewProbe.frozenAlerts, 1); XCTAssertEqual(context.bindings.navigation.pushes, 0)
        OverviewProbe.frozen = false
        OverviewProbe.lookup = .single(ProfilePeerView(peer: Peer(id: 2, restricted: true), monoforum: nil))
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: origin())
        pump(); XCTAssertEqual(context.bindings.navigation.pushes, 0)
    }
    func testProfileMediaPrivateContextIsNotWeakened() throws {
        OverviewProbe.initialMediaContext = origin(.excluded)
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: origin())
        pump(); XCTAssertTrue(try profile().mediaController.analyticsContext?.isExcluded == true)
    }
    func testAccountSwitchDuringProfileLookupCannotRegrant() throws {
        let original = origin()
        var subscriber: Subscriber<ProfilePeerView, NoError>?
        OverviewProbe.lookup = Signal { subscriber = $0; return EmptyDisposable }
        PeerInfoController.push(navigation: context.bindings.navigation, context: context, peerId: 2, analyticsContext: original)
        let other = AccountContext(); hub.policy.setOwner(other.account)
        subscriber?.putNext(ProfilePeerView(peer: Peer(id: 2), monoforum: nil)); subscriber = nil; pump()
        XCTAssertNil(try profile().analyticsContext?.scope)
    }
    func testProfileStatisticsActionsKeepInheritedScopeAndRouting() throws {
        let original = origin()
        let arguments = OverviewArguments(context, peerId: 2, origin: original)
        arguments.stats(1, monetization: true, stars: true)
        let segment = try XCTUnwrap(arguments.pushed as? ChannelStatsSegmentController)
        XCTAssertTrue(segment.analyticsContext?.scope === original.scope)
        XCTAssertNotNil(segment.monetization); XCTAssertNil(segment.stars)
        arguments.openStats(canSeeTon: false, canSeeStars: true)
        XCTAssertTrue((arguments.pushed as? ChannelStatsSegmentController)?.onlyMonetization == true)
        XCTAssertTrue(arguments.pushed?.analyticsContext?.scope === original.scope)
        arguments.peer = ProfilePeer(isSupergroup: true); arguments.groupStats(1)
        XCTAssertTrue(arguments.pushed is ChannelStatsSegmentController)
        arguments.peer = ProfilePeer(isSupergroup: false); arguments.groupStats(1)
        XCTAssertTrue(arguments.pushed is OverviewSurface)
    }
    func testBoostFallbackKeepsPrivateChildAndSource() throws {
        let arguments = OverviewArguments(context, peerId: 2, origin: origin())
        OverviewProbe.childContext = origin(.excluded)
        arguments.stats(0, monetization: false, stars: false)
        XCTAssertTrue(arguments.pushed is ChannelBoostStatsController)
        XCTAssertTrue(arguments.pushed?.analyticsContext?.isExcluded == true)
    }
    func testLegacyProfileHookKeepsUnknownProvenance() throws {
        StatisticsHooks.shared.openPeerInfoWithContext = nil
        StatisticsHooks.shared.openPeerInfoObserved(context, 2, analyticsContext: origin())
        pump(); XCTAssertTrue(try profile().analyticsContext?.isExcluded == true)
    }
}
