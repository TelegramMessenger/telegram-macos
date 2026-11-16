final class CommonPostbox {}
struct GroupsInCommonState { let peers: [PeerId] }
final class GroupsInCommonContext {
    let peerId: PeerId
    let state: Signal<GroupsInCommonState, NoError>
    init(account: Account, peerId: PeerId) {
        self.peerId = peerId; state = CommonProbe.state
        Probe.construction?(); CommonProbe.providers.append(peerId)
    }
    func loadMore() { CommonProbe.onLoadMore?(); CommonProbe.pages.append(peerId) }
}
enum CommonProbe {
    static var lookup: (PeerId) -> Signal<Peer?, NoError> = { .single(Peer($0)) }
    static var state: Signal<GroupsInCommonState, NoError> = .single(GroupsInCommonState(peers: [3]))
    static var providers: [PeerId] = []
    static var pages: [PeerId] = []
    static var onLoadMore: (() -> Void)?
    static var onEntries: (() -> Void)?
    static func reset() {
        lookup = { .single(Peer($0)) }; state = .single(GroupsInCommonState(peers: [3]))
        providers = []; pages = []; onLoadMore = nil; onEntries = nil
    }
}
func getPeerView(peerId: PeerId, postbox: CommonPostbox) -> Signal<Peer?, NoError> { Probe.construction?(); return CommonProbe.lookup(peerId) }
struct InputDataSignalValue { let entries: [CommonEntry] }
struct CommonEntry { let peerId: PeerId; let open: () -> Void }
func commonGroupsEntries(state: GroupsInCommonState, arguments: GroupsInCommonArguments, standalone: Bool) -> [CommonEntry] {
    CommonProbe.onEntries?()
    return state.peers.map { peerId in CommonEntry(peerId: peerId, open: { arguments.open(peerId) }) }
}
__COMMON_ARGUMENTS__
__COMMON_FACTORY__
__COMMON_HOOKS__
__COMMON_BRIDGE__
struct CommonBar { let height: Int }
enum CommonScreen { case peerInfoGroupsInCommon, peerInfoMediaGroupsInCommon, peerInfoMediaMembers }
enum CommonColor { case clear, listBackground }
struct CommonTheme { struct Colors { let listBackground = CommonColor.listBackground }; let colors = Colors() }
let theme = CommonTheme()
struct CommonStrings { let peerInfoGroupsInCommon = "Groups in common" }
func strings() -> CommonStrings { CommonStrings() }
struct CommonPosition { enum Direction { case bottom, top }; let direction: Direction }
final class CommonTable {
    enum Elasticity { case none }
    var verticalScrollElasticity = Elasticity.none
    var visibleItems: [AnyObject] = []
    var listener: TableScrollListener?
    func addScroll(listener: TableScrollListener) { self.listener = listener }
    func enumerateVisibleItems(with action: (AnyObject) -> Bool) { for item in visibleItems { if !action(item) { break } } }
    var scroll: (CommonPosition) -> Void = { _ in }
    func setScrollHandler(_ action: @escaping (CommonPosition) -> Void) { scroll = action }
}
extension InputDataController {
    convenience init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {
        self.init("members")
        self.title = title
        commonSubscription.set(dataSignal.start(next: { [weak self] value in self?.entries = value.entries }))
    }
    convenience init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String, hasDone: Bool) {
        self.init("commonGroups")
        self.title = title
        commonSubscription.set(dataSignal.start(next: { [weak self] value in self?.entries = value.entries }))
    }
}
func makeCommonFactoryHooks() -> PeerInfoNavigationHooks {
    var hooks = PeerInfoNavigationHooks()
__COMMON_FACTORY_BRIDGE__
    return hooks
}
struct ChatNavigationHooks {
    static var shared = ChatNavigationHooks()
__COMMON_CHAT_HOOK__
__TAG_CHAT_HOOK__
__SAVED_TAG_HOOK__
}
func installCommonChatBridge() {
    var hooks = ChatNavigationHooks()
__COMMON_CHAT_BRIDGE__
    ChatNavigationHooks.shared = hooks
}
final class CommonUserInfoRow {
    let chatInteraction: ChatInteraction
    var context: any AccountContextProtocol { chatInteraction.interactionContext }
    let _peer: Peer
    let groupsCount: Int
    init(_ interaction: ChatInteraction, peerId: PeerId = 2, count: Int = 1) { chatInteraction = interaction; _peer = Peer(peerId); groupsCount = count }
__COMMON_USER_ROW__
}
final class CommonGroupsContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        Probe.childOrigin = nil; Probe.construction = nil; Probe.media = []
        MediaProbe.created = []; MediaProbe.interactions = []; CommonProbe.reset()
        installGroupsInCommonUIHooks(); installCommonChatBridge()
        PeerInfoNavigationHooks.shared = makeCommonFactoryHooks()
    }
    override func tearDown() {
        Probe.construction = nil; Probe.childOrigin = nil; CommonProbe.reset()
        MediaProbe.created = []; MediaProbe.interactions = []; context = nil
    }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func make(peerId: PeerId = 2, standalone: Bool = false, source: AnalyticsContext? = nil) -> InputDataController {
        GroupsInCommonViewController(context: context, peerId: peerId, standalone: standalone, analyticsContext: source) as! InputDataController
    }
    func testOrdinaryListLookupAndSelectionKeepExactScope() {
        let source = origin(); let controller = make(source: source)
        XCTAssertEqual(CommonProbe.providers, [2]); XCTAssertEqual(controller.entries.count, 1)
        controller.entries[0].open()
        XCTAssertTrue(controller.analyticsContext?.scope === source.scope)
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.scope === source.scope)
    }
    func testPrivateLookupSurvivesDeferredResultAndParentClosure() {
        var sink: Subscriber<Peer?, NoError>?
        CommonProbe.lookup = { _ in Signal { sink = $0; return EmptyDisposable } }
        var controller: InputDataController? = make(source: origin(.excluded))
        XCTAssertTrue(hub.policy.hasExclusions)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        sink?.putNext(Peer(2)); sink = nil
        let open = controller!.entries[0].open
        MediaProbe.created = []; controller = nil
        open()
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testSecretRequestedPeerCannotBecomeOrdinaryAfterResolution() {
        CommonProbe.lookup = { _ in .single(Peer(2)) }
        let controller = make(peerId: -2, source: origin())
        XCTAssertEqual(CommonProbe.providers, [2]); XCTAssertTrue(controller.analyticsContext?.isExcluded == true)
        controller.entries[0].open()
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testResolvedPrivatePeerExcludesOriginalScopeBeforeProviderAndSelection() {
        var sink: Subscriber<Peer?, NoError>?
        CommonProbe.lookup = { _ in Signal { sink = $0; return EmptyDisposable } }
        let source = origin(); let controller = make(source: source)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        sink?.putNext(Peer(-2)); sink = nil
        XCTAssertTrue(source.isExcluded); XCTAssertEqual(CommonProbe.providers, [-2])
        controller.entries[0].open()
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testPaginationRetainsPrivateSourceAndStillLoads() {
        let controller = make(source: origin(.excluded))
        controller.didLoad?(controller, 0)
        CommonProbe.onLoadMore = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        controller.tableView.scroll(CommonPosition(direction: .bottom))
        controller.tableView.scroll(CommonPosition(direction: .top))
        XCTAssertEqual(CommonProbe.pages, [2])
    }
    func testPrivateListUpdatesAreProtectedAfterLookupFinishes() {
        var sink: Subscriber<GroupsInCommonState, NoError>?
        CommonProbe.state = Signal { sink = $0; return EmptyDisposable }
        let controller = make(source: origin(.excluded))
        CommonProbe.onEntries = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        sink?.putNext(GroupsInCommonState(peers: [4, 5]))
        XCTAssertEqual(controller.entries.map { $0.peerId }, [4, 5])
        controller.commonSubscription.dispose(); sink = nil
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPaginationCallbackOutlivesControllerWithoutLosingPrivateOrigin() {
        var controller: InputDataController? = make(source: origin(.excluded))
        controller!.didLoad?(controller!, 0)
        let scroll = controller!.tableView.scroll
        MediaProbe.created = []; controller = nil
        XCTAssertFalse(hub.policy.hasExclusions)
        CommonProbe.onLoadMore = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        scroll(CommonPosition(direction: .bottom))
        XCTAssertEqual(CommonProbe.pages, [2])
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testDisposalCancelsUnfinishedLookupAndReleasesExclusion() {
        var disposed = 0
        CommonProbe.lookup = { _ in Signal { _ in ActionDisposable { disposed += 1 } } }
        var controller: InputDataController? = make(source: origin(.excluded))
        XCTAssertTrue(hub.policy.hasExclusions)
        MediaProbe.created = []; controller = nil
        XCTAssertEqual(disposed, 1); XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertTrue(CommonProbe.providers.isEmpty)
    }
    func testMissingPeerFallsBackToRequestedPeerWithoutNewGrant() {
        CommonProbe.lookup = { _ in .single(nil) }
        let controller = make()
        XCTAssertEqual(CommonProbe.providers, [2]); controller.entries[0].open()
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testAccountSwitchDuringLookupProtectsProviderAndSelection() {
        var sink: Subscriber<Peer?, NoError>?
        CommonProbe.lookup = { _ in Signal { sink = $0; return EmptyDisposable } }
        let controller = make(source: origin()); let other = AccountContext()
        hub.policy.setOwner(other.account)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        sink?.putNext(Peer(2)); sink = nil; controller.entries[0].open()
        XCTAssertNil(context.bindings.navigation.pushed.last?.analyticsContext?.scope)
    }
    func testRevokedSourceCannotRegainScopeAtSelection() {
        let controller = make(source: origin())
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        controller.entries[0].open()
        XCTAssertNil(context.bindings.navigation.pushed.last?.analyticsContext?.scope)
    }
    func testSecretSelectedGroupClassifiedBeforeChatConstruction() {
        CommonProbe.state = .single(GroupsInCommonState(peers: [-3]))
        let controller = make(source: origin())
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        controller.entries[0].open()
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testStandaloneUserCardKeepsOriginAndZeroCountGuard() {
        let interaction = ChatInteraction(context, location: .peer(2)); let source = origin(); interaction.inheritedAnalyticsContext = source
        CommonUserInfoRow(interaction, count: 0).openCommonGroups(); XCTAssertTrue(context.bindings.navigation.pushed.isEmpty)
        CommonUserInfoRow(interaction).openCommonGroups()
        let controller = context.bindings.navigation.pushed.last as! InputDataController
        XCTAssertTrue(controller.analyticsContext?.scope === source.scope)
        XCTAssertEqual(controller.analyticsScreen, .peerInfoGroupsInCommon); XCTAssertEqual(controller.bar.height, 50)
    }
    func testSecretUserCardCannotLoseNamespaceThroughAssociatedOrdinaryPeer() {
        let interaction = ChatInteraction(context, location: .peer(-2))
        CommonUserInfoRow(interaction, peerId: 2).openCommonGroups()
        let controller = context.bindings.navigation.pushed.last as! InputDataController
        controller.entries[0].open()
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testProfileMediaFactoryPassesOriginAndEmbeddedLayout() {
        let source = origin(); let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: source)
        let controller = media.commonGroups as! InputDataController
        XCTAssertTrue(controller.analyticsContext?.scope === source.scope)
        XCTAssertEqual(controller.analyticsScreen, .peerInfoMediaGroupsInCommon); XCTAssertEqual(controller.bar.height, 0)
        controller.entries[0].open(); XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.scope === source.scope)
    }
    func testLegacyHooksAndFactoriesStayFunctionalWithoutGrant() {
        var hooks = GroupsInCommonHooks.shared; hooks.openChatWithContext = nil; GroupsInCommonHooks.install(hooks)
        PeerInfoNavigationHooks.shared.makeGroupsInCommonControllerWithContext = nil
        let controller = PeerInfoNavigationHooks.shared.makeGroupsInCommonControllerObserved(context, 2, analyticsContext: origin()) as! InputDataController
        controller.entries[0].open(); XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
        ChatNavigationHooks.shared.pushGroupsInCommonWithContext = nil
        ChatNavigationHooks.shared.pushGroupsInCommonObserved(context, 2, analyticsContext: origin(.excluded))
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testDisabledCollectionLeavesListSelectionAndPaginationAvailable() {
        hub.policy.isEnabled = false
        let controller = make(); controller.didLoad?(controller, 0)
        controller.tableView.scroll(CommonPosition(direction: .bottom)); controller.entries[0].open()
        XCTAssertEqual(CommonProbe.pages, [2]); XCTAssertEqual(context.bindings.navigation.pushed.count, 1)
    }
}
