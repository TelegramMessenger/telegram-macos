struct TemporaryParticipant: Equatable {
    let peer: Peer
    static func == (lhs: TemporaryParticipant, rhs: TemporaryParticipant) -> Bool { lhs.peer.id == rhs.peer.id }
}
struct PeerInputActivity {}
struct PeerStoryStats {}
struct ChannelMemberListState {
    enum LoadingState { case ready(hasMore: Bool) }
    let list: [RenderedChannelParticipant]
    let peerStoryStats: [PeerId: PeerStoryStats]
    let loadingState: LoadingState
}
final class PeerChannelMemberCategoryControl {}
struct PeerView { let peer: Peer?; let cachedData: Any? }
func peerViewMainPeer(_ view: PeerView) -> Peer? { view.peer }
struct CachedGroupData {
    struct Participants { let participants: [ChannelParticipant] }
    let participants: Participants?
}
enum PostboxViewKey: Hashable { case peerStoryStats(peerIds: Set<PeerId>) }
struct PeerStoryStatsView { let storyStats: [PeerId: PeerStoryStats] }
struct CombinedView { let views: [PostboxViewKey: Any] }
struct StoryInitialIndex { let peerId: PeerId }
struct ActivityCategory {
    enum Category { case global }
    let peerId: PeerId
    let category: Category
}
struct TableScrollListener {
    let action: (Int) -> Void
    init(dispatchWhenVisibleRangeUpdated: Bool, _ action: @escaping (Int) -> Void) { self.action = action }
}
final class ShortPeerRowItem {
    let peer: Peer
    init(_ peer: Peer) { self.peer = peer }
}
let prepareQueue = Queue.mainQueue()
extension Account {
    func peerInputActivities(peerId: ActivityCategory) -> Signal<[(PeerId, PeerInputActivity)], NoError> { GroupProbe.check?(); return .single([]) }
    var viewTracker: GroupTracker { GroupProbe.tracker }
}
final class GroupTracker {
    func refreshStoryStatsForPeerIds(peerIds: [PeerId]) { GroupProbe.check?(); GroupProbe.refreshes.append(peerIds) }
}
extension CommonPostbox {
    func loadedPeerWithId(_ peerId: PeerId) -> Signal<Peer, NoError> { GroupProbe.check?(); return GroupProbe.lookup(peerId) }
    func peerView(id: PeerId) -> Signal<PeerView, NoError> { GroupProbe.check?(); return GroupProbe.peerView(id) }
    func combinedView(keys: [PostboxViewKey]) -> Signal<CombinedView, NoError> {
        GroupProbe.check?(); GroupProbe.storyLookups += 1
        return .single(CombinedView(views: [:]))
    }
}
extension Engine { var peers: GroupPeers { GroupProbe.peers } }
final class GroupPeers {
    func removePeerMember(peerId: PeerId, memberId: PeerId) -> Signal<Void, NoError> {
        GroupProbe.check?(); GroupProbe.groupRemovals.append((peerId, memberId))
        return Signal { subscriber in
            GroupProbe.check?(); GroupProbe.removeSink = subscriber
            return ActionDisposable { GroupProbe.check?(); GroupProbe.operationDisposals += 1 }
        }
    }
}
extension MemberManager {
    func recent(peerId: PeerId, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl) {
        GroupProbe.check?(); GroupProbe.recentCallback = updated
        updated(ChannelMemberListState(list: [], peerStoryStats: [:], loadingState: .ready(hasMore: true)))
        return (ActionDisposable { GroupProbe.check?(); GroupProbe.recentDisposals += 1 }, PeerChannelMemberCategoryControl())
    }
    func loadMore(peerId: PeerId, control: PeerChannelMemberCategoryControl) { GroupProbe.check?(); GroupProbe.pages.append(peerId) }
}
final class StoryModalController<C: AccountContextProtocol> {
    static func ShowStories(context: C, isHidden: Bool, initialId: StoryInitialIndex?, singlePeer: Bool, analyticsContext: AnalyticsContext) {
        GroupProbe.stories.append((initialId?.peerId, analyticsContext))
    }
}
func ChannelParticipantController(context: AccountContext, peerId: PeerId, participant: RenderedChannelParticipant, analyticsContext: AnalyticsContext? = nil) -> MemberModal {
    let content = makeMember(context: context, peerId: peerId, participant: participant, analyticsContext: analyticsContext)
    let modal = MemberModal(content); modal.analyticsContext = content.analyticsContext
    return modal
}
func installMemberListBridge() {
    var hooks = PeerInfoNavigationHooks.shared
__MEMBER_LIST_BRIDGE__
    PeerInfoNavigationHooks.shared = hooks
}
__MEMBER_LIST_ARGUMENTS__
func groupPeersEntries<C: AccountContextProtocol>(state: GroupPeersState, isEditing: Bool, viewAndStories: (PeerView, [PeerId: PeerStoryStats]), inputActivities: [PeerId: PeerInputActivity], memberListState: ChannelMemberListState, arguments: GroupPeersArguments<C>) -> [CommonEntry] {
    GroupProbe.check?(); GroupProbe.states.append(state)
    GroupProbe.remove = arguments.removePeer; GroupProbe.openInfo = arguments.openInfo
    GroupProbe.promote = arguments.promote; GroupProbe.restrict = arguments.restrict
    GroupProbe.showMore = arguments.showMore; GroupProbe.openStory = arguments.openStory
    GroupProbe.profile = arguments.peerInfo
    return [CommonEntry(peerId: 3, open: { arguments.peerInfo(3) })]
}
__MEMBER_LIST_FACTORY__
enum GroupProbe {
    static let tracker = GroupTracker()
    static let peers = GroupPeers()
    static var check: (() -> Void)?
    static var peerView: (PeerId) -> Signal<PeerView, NoError> = { .single(PeerView(peer: Peer($0), cachedData: nil)) }
    static var lookup: (PeerId) -> Signal<Peer, NoError> = { .single(Peer($0)) }
    static var recentCallback: ((ChannelMemberListState) -> Void)?
    static var recentDisposals = 0
    static var operationDisposals = 0
    static var storyLookups = 0
    static var removeSink: Subscriber<Void, NoError>?
    static var states: [GroupPeersState] = []
    static var pages: [PeerId] = []
    static var groupRemovals: [(PeerId, PeerId)] = []
    static var refreshes: [[PeerId]] = []
    static var stories: [(PeerId?, AnalyticsContext)] = []
    static var remove: (PeerId) -> Void = { _ in }
    static var profile: (PeerId) -> Void = { _ in }
    static var showMore: () -> Void = {}
    static var openStory: (StoryInitialIndex?) -> Void = { _ in }
    static var openInfo: (RenderedChannelParticipant) -> Void = { _ in }
    static var promote: (RenderedChannelParticipant) -> Void = { _ in }
    static var restrict: (RenderedChannelParticipant) -> Void = { _ in }
    static func reset() {
        check = nil; peerView = { .single(PeerView(peer: Peer($0), cachedData: nil)) }; lookup = { .single(Peer($0)) }
        recentCallback = nil; recentDisposals = 0; operationDisposals = 0; storyLookups = 0; removeSink = nil
        states = []; pages = []; groupRemovals = []; refreshes = []; stories = []
        remove = { _ in }; profile = { _ in }; showMore = {}; openStory = { _ in }
        openInfo = { _ in }; promote = { _ in }; restrict = { _ in }
    }
}
final class MemberListContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    let selected = RenderedChannelParticipant(peer: Peer(3), participant: ChannelParticipant(peerId: 3))
    override func setUp() {
        GroupProbe.reset(); MemberProbe.reset(); MediaProbe.created = []; Probe.construction = nil; Probe.profiles = []
        Analytics.shared = Analytics(); context = AccountContext(); hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installMemberBridge(); installMemberListBridge()
    }
    override func tearDown() { GroupProbe.reset(); MemberProbe.reset(); MediaProbe.created = []; Probe.profiles = []; context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func make(_ peerId: PeerId = 1000, _ source: AnalyticsContext? = nil) -> InputDataController {
        PeerMediaGroupMembersController(context: context, peerId: peerId, editing: .single(false), analyticsContext: source)
    }
    func expectExcluded() {
        GroupProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        MemberProbe.check = GroupProbe.check
    }
    func testOrdinaryProfileStoryAndParticipantActionsKeepSource() {
        let source = origin(); let controller = make(1000, source)
        XCTAssertTrue(controller.analyticsContext?.scope === source.scope)
        GroupProbe.profile(3); GroupProbe.openStory(StoryInitialIndex(peerId: 3)); GroupProbe.openInfo(selected)
        XCTAssertTrue(Probe.profiles.last?.origin?.scope === source.scope)
        XCTAssertTrue(GroupProbe.stories.last?.1.scope === source.scope)
        XCTAssertTrue(MemberProbe.modal?.content.analyticsContext?.scope === source.scope)
    }
    func testOrdinaryPromotionAndRestrictionKeepSourceAndReturnedRights() {
        let source = origin(); let controller = make(1000, source)
        GroupProbe.promote(selected); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.scope === source.scope)
        GroupProbe.restrict(selected); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.scope === source.scope)
        MemberProbe.modal?.updated?(TelegramChatBannedRights(flags: [], untilDate: 7))
        XCTAssertEqual(MemberProbe.removals.last?.2, 7); MemberProbe.rightsSink?.putCompletion()
        withExtendedLifetime(controller) {}
    }
    func testPrivateProviderRowsAndDisposalRemainExcluded() {
        expectExcluded(); var controller: InputDataController? = make(1000, origin(.excluded))
        XCTAssertTrue(hub.policy.hasExclusions); XCTAssertEqual(controller?.entries.count, 1)
        GroupProbe.recentCallback?(ChannelMemberListState(list: [], peerStoryStats: [:], loadingState: .ready(hasMore: false)))
        MediaProbe.created = []; controller = nil
        XCTAssertEqual(GroupProbe.recentDisposals, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testDelayedPeerResolutionClassifiesPrivateGroupBeforeStoryLookupAndRows() {
        var sink: Subscriber<PeerView, NoError>?
        GroupProbe.peerView = { _ in Signal { sink = $0; return EmptyDisposable } }
        let source = origin(); let controller = make(2, source)
        expectExcluded()
        sink?.putNext(PeerView(peer: Peer(-2), cachedData: CachedGroupData(participants: .init(participants: [ChannelParticipant(peerId: 3)]))))
        XCTAssertTrue(source.scope?.isExcluded == true); XCTAssertEqual(GroupProbe.storyLookups, 1)
        GroupProbe.openInfo(selected); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        withExtendedLifetime(controller) {}
    }
    func testPrivatePaginationAndVisibleRefreshAfterParentRelease() {
        var controller: InputDataController? = make(1000, origin(.excluded))
        controller!.didLoad?(controller!, 0)
        let page = controller!.tableView.scroll; let refresh = controller!.tableView.listener!.action
        MediaProbe.created = []; controller = nil
        XCTAssertFalse(hub.policy.hasExclusions); expectExcluded()
        page(CommonPosition(direction: .bottom)); refresh(0)
        XCTAssertEqual(GroupProbe.pages, [1000]); XCTAssertEqual(GroupProbe.refreshes, [[]])
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testVisibleRefreshUsesActualUserRowsOnly() {
        let controller = make(1000, origin(.excluded)); controller.didLoad?(controller, 0)
        controller.tableView.visibleItems = [ShortPeerRowItem(TelegramUser(3)), ShortPeerRowItem(Peer(4))]
        expectExcluded(); controller.tableView.listener?.action(0)
        XCTAssertEqual(GroupProbe.refreshes, [[3]])
    }
    func testPrivateActionsSurviveListClosure() {
        var controller: InputDataController? = make(1000, origin(.excluded))
        MediaProbe.created = []; controller = nil; XCTAssertNil(controller)
        expectExcluded(); GroupProbe.promote(selected); GroupProbe.restrict(selected); GroupProbe.openInfo(selected)
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        GroupProbe.openStory(StoryInitialIndex(peerId: 3)); GroupProbe.profile(3)
        XCTAssertTrue(GroupProbe.stories.last?.1.isExcluded == true); XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
    }
    func testPrivateRemovalProtectsDelayedLookupProviderAndCleanup() {
        var sink: Subscriber<Peer, NoError>?
        GroupProbe.lookup = { _ in Signal { sink = $0; return EmptyDisposable } }
        var controller: InputDataController? = make(2, origin(.excluded))
        expectExcluded(); GroupProbe.remove(3); sink?.putNext(Peer(3))
        XCTAssertEqual(GroupProbe.groupRemovals.count, 1)
        XCTAssertTrue(GroupProbe.states.last?.removingParticipantIds.contains(3) == true)
        GroupProbe.removeSink?.putCompletion()
        XCTAssertFalse(GroupProbe.states.last?.removingParticipantIds.contains(3) == true)
        MediaProbe.created = []; controller = nil; XCTAssertNil(controller)
        XCTAssertEqual(GroupProbe.operationDisposals, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testChannelRemovalUsesExistingBanAndPrivateResolvedMemberRevokesScope() {
        var sink: Subscriber<Peer, NoError>?
        GroupProbe.lookup = { _ in Signal { sink = $0; return EmptyDisposable } }
        let source = origin(); let controller = make(1000, source)
        GroupProbe.remove(3); expectExcluded(); sink?.putNext(Peer(-3))
        XCTAssertTrue(source.scope?.isExcluded == true); XCTAssertEqual(MemberProbe.removals.last?.2, Int32.max)
        MemberProbe.rightsSink?.putCompletion(); withExtendedLifetime(controller) {}
    }
    func testAccountSwitchDuringLookupCannotRestoreOrdinaryContext() {
        var sink: Subscriber<PeerView, NoError>?
        GroupProbe.peerView = { _ in Signal { sink = $0; return EmptyDisposable } }
        let controller = make(1000, origin()); let other = AccountContext(); hub.policy.setOwner(other.account)
        expectExcluded(); sink?.putNext(PeerView(peer: Peer(1000), cachedData: nil))
        GroupProbe.openInfo(selected); XCTAssertNil(MemberProbe.modal?.analyticsContext?.scope)
        withExtendedLifetime(controller) {}
    }
    func testRepresentedSecretMemberCannotLosePrivacyInHooks() {
        let controller = make(1000, origin()); expectExcluded()
        let privateMember = RenderedChannelParticipant(peer: Peer(3), participant: ChannelParticipant(peerId: -4))
        GroupProbe.openInfo(privateMember); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        GroupProbe.promote(privateMember); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        GroupProbe.restrict(privateMember); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        withExtendedLifetime(controller) {}
    }
    func testLegacyHooksAndDisabledListKeepActionsFunctional() {
        hub.policy.isEnabled = false; expectExcluded()
        PeerInfoNavigationHooks.shared.showRestrictMemberWithContext = nil
        PeerInfoNavigationHooks.shared.showChannelParticipantWithContext = nil
        let controller = make()
        GroupProbe.openInfo(selected); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        GroupProbe.restrict(selected); XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        GroupProbe.showMore(); XCTAssertNil(GroupProbe.states.last?.hasShowMoreButton)
        withExtendedLifetime(controller) {}
    }
}
