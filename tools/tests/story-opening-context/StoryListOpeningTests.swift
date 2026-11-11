struct SettingsHooks {
    static var shared = SettingsHooks(showStories: { _, _, _, _ in })
__SETTINGS_HOOK__
}
struct StoriesHooks {
    static var shared = StoriesHooks(showListStory: { _, _, _, _ in })
__LIST_HOOK__
}
func installListBridges() {
    do {
        var hooks = SettingsHooks(showStories: { context, hidden, initial, single in
            StoryModalController.ShowStories(context: context as! AccountContext, isHidden: hidden, initialId: initial, singlePeer: single)
        })
__SETTINGS_BRIDGE__
        SettingsHooks.shared = hooks
    }
    do {
        var hooks = StoriesHooks(showListStory: { context, list, peer, initial in
            StoryModalController.ShowListStory(context: context as! AccountContext, listContext: list, peerId: peer, initialId: initial)
        })
__LIST_BRIDGE__
        StoriesHooks.shared = hooks
    }
}
final class AccountHost: ModalViewController {
    let context: AccountContext
    init(_ context: AccountContext) { self.context = context }
    func action() -> (StoryInitialIndex?) -> Void {
        let context = self.context
        return { [weak self] initialId in
__SETTINGS_ACTION__
        }
    }
}
final class SearchList: StoryListContext {}
final class ListSurface: ModalViewController {
    let controller = ModalViewController()
    var list: SearchList?
    var open: (StoryInitialIndex?) -> Void = { _ in }
    var openPeer: (PeerId) -> Void = { _ in }
    var openRepost: (StoryId) -> Void = { _ in }
    var premium: () -> Void = {}
}
func makeSearch(_ context: AccountContext, source: SearchSource = .hashtag(nil, ""), analyticsContext: AnalyticsContext? = nil) -> ListSurface {
__SEARCH_PREFIX__
    Probe.setup?()
    let modalController = ListSurface()
    let controller = modalController.controller
__SEARCH_CONTENT__
__SEARCH_MODAL__
    let contextObject = SearchList()
    modalController.list = contextObject
    modalController.open = { [weak contextObject] initialId in
__SEARCH_OPEN__
    }
    return modalController
}
enum PremiumSource { case storyViewers }
struct FeatureNavigationHooks {
__STATS_FEATURE_HOOK__
    static var shared = FeatureNavigationHooks()
    static var received: AnalyticsContext?
    func showPremiumBoardingObserved(_ context: any AccountContextProtocol, _ window: Window, _ source: PremiumSource, _ expanded: Bool, _ theme: Int, analyticsContext: AnalyticsContext) {
        Self.received = analyticsContext
    }
}
func makeViewers(_ context: AccountContext, peerId: PeerId, analyticsContext: AnalyticsContext? = nil) -> ListSurface {
__VIEWERS_PREFIX__
    Probe.setup?()
    let getControl: ((PeerId, Any?) -> Int?)? = nil
    let setProgress: ((PeerId, Signal<Never, NoError>) -> Void)? = { _, signal in _ = signal.start() }
    let modalController = ListSurface()
    let controller = modalController.controller
__VIEWER_CONTENT__
__VIEWER_MODAL__
    modalController.openPeer = { peerId in
__VIEWER_OPEN__
    }
    modalController.openRepost = { storyId in
__VIEWER_REPOST__
    }
    modalController.premium = {
__VIEWER_PREMIUM__
    }
    return modalController
}
final class MediaListHost: ModalViewController {
    let context: AccountContext
    let peerId: PeerId
    var currentContext: StoryListContext?
    init(_ context: AccountContext, peerId: PeerId) { self.context = context; self.peerId = peerId }
    func action() -> (StoryInitialIndex?) -> Void {
        let context = self.context
        let peerId = self.peerId
        return { [weak self] initialId in
__MEDIA_OPEN__
        }
    }
}
enum Area { case venue }
enum SearchSource { case hashtag(PeerId?, String); case mediaArea(Area) }
enum ListProbe { static var shown: ListSurface? }
func StoryFoundListController(context: AccountContext, source: SearchSource, presentation: Int, analyticsContext: AnalyticsContext?) -> ListSurface {
    makeSearch(context, source: source, analyticsContext: analyticsContext)
}
func showModal(with surface: ListSurface, for window: Window) { ListProbe.shown = surface }
final class StorySourceHost {
    let context: AccountContext
    let chatInteraction: ChatInteraction
    init(_ context: AccountContext) { self.context = context; chatInteraction = ChatInteraction(chatLocation: .peer(2), context: context) }
    func hashtag() -> (String) -> Void {
        let context = self.context
        return { [weak self] string in
__HASHTAG__
        }
    }
    func venue() -> (Area) -> Void {
        let context = self.context
        return { [weak self] area in
__VENUE__
        }
    }
}
final class StoryListOpeningTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.shown = []; Probe.setup = nil; Probe.onShow = nil
        Probe.state = .single(StoryContentContextState(slice: Slice(peer: Peer(id: 2))))
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installListBridges(); FeatureNavigationHooks.received = nil; ListProbe.shown = nil
    }
    override func tearDown() { ListProbe.shown = nil; Probe.shown = []; Probe.setup = nil; context = nil; FeatureNavigationHooks.received = nil; Analytics.shared = Analytics() }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
    func viewer() throws -> StoryModalController<AccountContext> { try XCTUnwrap(Probe.shown.last as? StoryModalController<AccountContext>) }
    func testSettingsRootCapturesOrdinaryScopeAndPreservesInheritedScope() throws {
        let host = AccountHost(context)
        host.action()(nil); pump()
        XCTAssertTrue(try viewer().analyticsContext?.scope?.isValid == true)
        let inherited = origin(); host.analyticsContext = inherited
        host.action()(nil); pump()
        XCTAssertTrue(try viewer().analyticsContext?.scope === inherited.scope)
    }
    func testSettingsPrivateAndRevokedContextsCannotRegrant() throws {
        let host = AccountHost(context)
        let original = origin(); host.analyticsContext = original
        original.scope?.exclude()
        host.action()(nil); pump()
        XCTAssertNil(try viewer().analyticsContext?.scope)
        host.analyticsContext = origin(.excluded)
        host.action()(nil); pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testReleasedSettingsOwnerDoesNotOpen() {
        var host: AccountHost? = AccountHost(context)
        let action = host!.action(); host = nil
        action(nil); pump(); XCTAssertTrue(Probe.shown.isEmpty)
    }
    func testSearchRetainsOriginalContextOnBothControllersAndSelection() throws {
        let original = origin()
        let surface = makeSearch(context, analyticsContext: original)
        XCTAssertTrue(surface.analyticsContext?.scope === original.scope)
        XCTAssertTrue(surface.controller.analyticsContext?.scope === original.scope)
        surface.open(StoryInitialIndex(peerId: 2, id: 1, messageId: nil))
        pump(); XCTAssertTrue(try viewer().analyticsContext?.scope === original.scope)
    }
    func testSearchPrivateOriginSurvivesClosedParentAndDifferentSelectedPeer() throws {
        let original = origin(.excluded)
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let parent = original.beginPresentation()
        let surface = makeSearch(context, analyticsContext: original)
        parent.end()
        surface.open(StoryInitialIndex(peerId: 3, id: 1, messageId: nil))
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testPrivateHashtagScopeIsExcludedBeforeControllerConstruction() throws {
        let original = origin()
        Probe.setup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let surface = makeSearch(context, source: .hashtag(-2, "tag"), analyticsContext: original)
        XCTAssertTrue(surface.analyticsContext?.isExcluded == true)
        surface.open(nil); pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testUnknownSearchOriginStillOpensWithoutAnalytics() throws {
        let surface = makeSearch(context)
        surface.open(nil); pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
    }
    func testSearchSelectionRechecksAccountAndSelectedPeer() throws {
        let original = origin()
        let surface = makeSearch(context, analyticsContext: original)
        surface.open(StoryInitialIndex(peerId: -2, id: 1, messageId: nil))
        pump(); XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
        let other = AccountContext(); hub.policy.setOwner(other.account)
        surface.open(nil); pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testReleasedSearchListCannotOpenThroughRetainedCallback() {
        let surface = makeSearch(context, analyticsContext: origin())
        surface.list = nil; surface.open(nil)
        pump(); XCTAssertTrue(Probe.shown.isEmpty)
    }
    func testViewersRepostPeerAndPremiumKeepOriginalScope() throws {
        let original = origin()
        let surface = makeViewers(context, peerId: 2, analyticsContext: original)
        XCTAssertTrue(surface.analyticsContext?.scope === original.scope)
        XCTAssertTrue(surface.controller.analyticsContext?.scope === original.scope)
        surface.openPeer(3); pump()
        XCTAssertTrue(try viewer().analyticsContext?.scope === original.scope)
        surface.openRepost(StoryId(peerId: 4, id: 1)); pump()
        XCTAssertTrue(try viewer().analyticsContext?.scope === original.scope)
        surface.premium(); XCTAssertTrue(FeatureNavigationHooks.received?.scope === original.scope)
    }
    func testViewersPrivateOriginRemainsPrivateAfterParentRelease() throws {
        let original = origin(.excluded)
        let parent = original.beginPresentation()
        let surface = makeViewers(context, peerId: 2, analyticsContext: original)
        parent.end()
        surface.openRepost(StoryId(peerId: 3, id: 1)); pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
        surface.openPeer(3); pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
        surface.premium(); XCTAssertTrue(FeatureNavigationHooks.received?.isExcluded == true)
    }
    func testViewersPrivatePeerAndUnknownOriginAreDenied() throws {
        let surface = makeViewers(context, peerId: -2, analyticsContext: origin())
        surface.openRepost(StoryId(peerId: 2, id: 1)); pump()
        XCTAssertTrue(try viewer().analyticsContext?.isExcluded == true)
        let unknown = makeViewers(context, peerId: 2)
        unknown.openPeer(2); pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testMediaListRequiresKnownParentAndKeepsItsScope() throws {
        let host = MediaListHost(context, peerId: 2); host.currentContext = StoryListContext()
        let original = origin(); host.analyticsContext = original
        host.action()(nil); pump(); XCTAssertTrue(try viewer().analyticsContext?.scope === original.scope)
        host.analyticsContext = nil
        host.action()(nil); pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testMissingMediaListOrOwnerDoesNotOpen() {
        var host: MediaListHost? = MediaListHost(context, peerId: 2)
        let action = host!.action()
        action(nil); pump(); XCTAssertTrue(Probe.shown.isEmpty)
        host?.currentContext = StoryListContext(); host = nil
        action(nil); pump(); XCTAssertTrue(Probe.shown.isEmpty)
    }
    func testHashtagAndVenueIngressCarryOrdinaryStoryScope() throws {
        let host = StorySourceHost(context)
        let original = origin(); host.chatInteraction.inheritedAnalyticsContext = original
        host.hashtag()("tag")
        XCTAssertTrue(ListProbe.shown?.analyticsContext?.scope === original.scope)
        host.venue()(.venue)
        XCTAssertTrue(ListProbe.shown?.analyticsContext?.scope === original.scope)
        ListProbe.shown?.open(nil); pump()
        XCTAssertTrue(try viewer().analyticsContext?.scope === original.scope)
    }
    func testHashtagAndVenueIngressNeverRefreshPrivateOrMissingOwner() throws {
        var host: StorySourceHost? = StorySourceHost(context)
        host?.chatInteraction.inheritedAnalyticsContext = origin(.excluded)
        host?.hashtag()("tag")
        XCTAssertTrue(ListProbe.shown?.analyticsContext?.isExcluded == true)
        let venue = host!.venue(); host = nil
        venue(.venue)
        XCTAssertTrue(ListProbe.shown?.analyticsContext?.isExcluded == true)
        ListProbe.shown?.open(nil); pump()
        XCTAssertNil(try viewer().analyticsContext?.scope)
    }
    func testLegacySettingsAndListFallbacksRemainFunctionalAndExcluded() throws {
        SettingsHooks.shared.showStoriesWithContext = nil
        StoriesHooks.shared.showListStoryWithContext = nil
        let original = origin()
        SettingsHooks.shared.showStoriesObserved(context, false, nil, false, analyticsContext: original)
        pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
        StoriesHooks.shared.showListStoryObserved(context, StoryListContext(), 2, nil, analyticsContext: original)
        pump(); XCTAssertNil(try viewer().analyticsContext?.scope)
        XCTAssertEqual(Probe.shown.count, 2)
    }
}
