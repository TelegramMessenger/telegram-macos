typealias Window = Int
typealias InputDataModalController = MemberModal
final class NSView {}
final class TelegramChannel: Peer {}
enum AdminBadgeType { case none, owner, admin }
struct BadgeText { let attributedString: NSAttributedString }
__TAG_TYPES__
__TAG_CONFIGURATION__
enum TagValidation { case none }
enum TagScreen { case chatMemberTagInfo, chatSavedTagName }
final class TagContent: ViewController {
    let subscription = MetaDisposable()
    var analyticsScreen: TagScreen?
    var validateData: (Int) -> TagValidation = { _ in .none }
    var onDeinit: (() -> Void)?
    var updateDatas: ([String: SavedTagInput]) -> TagValidation = { _ in .none }
    var leftModalHeader: ModalHeaderData?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {
        super.init(); TagProbe.check?(); subscription.set(dataSignal.start())
    }
    func returnKeyAction() -> TagValidation { validateData(0) }
    deinit { subscription.dispose(); onDeinit?() }
}
final class TagModalInteractions {
    let accept: () -> Void
    init(acceptTitle: String, accept: @escaping () -> Void, singleButton: Bool) { self.accept = accept }
}
final class TagModal: ViewController {
    let content: TagContent
    let interactions: TagModalInteractions
    var _hasBorder = true
    var modal: TagModal? { self }
    init(_ content: TagContent, modalInteractions: TagModalInteractions) {
        self.content = content; self.interactions = modalInteractions; super.init(); TagProbe.check?()
    }
    func close() { TagProbe.check?(); TagProbe.closes += 1 }
}
extension CommonStrings { var userTagInfoUnderstood: String { "Understood" } }
func showModal(with controller: TagModal, for window: Int) { TagProbe.check?(); TagProbe.modal = controller }
func tagEntries(_ state: TagState, arguments: TagArguments, config: UserTagInfoConfiguration) -> [CommonEntry] {
    TagProbe.check?(); TagProbe.config = config; TagProbe.dismiss = arguments.dismiss; TagProbe.renders += 1
    return []
}
func deliverOnPrepareQueue<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
    if TagProbe.deferRendering { return TagProbe.renderGate.get() |> filter { $0 } |> take(1) |> mapToSignal { _ in signal } }
    return signal
}
__TAG_FACTORY__
struct ChatHistoryUIHooks {
    static var shared = ChatHistoryUIHooks()
    var pushReactionPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId, MessageId) -> Void = { _, _, _, _ in ReactionListProbe.legacyCalls += 1; ReactionListProbe.check?() }
    var makeChannelParticipantController: (any AccountContextProtocol, PeerId, RenderedChannelParticipant) -> MemberModal = { context, peerId, participant in
        ChannelParticipantController(context: context.concrete, peerId: peerId, participant: participant)
    }
__TAG_PARTICIPANT_HOOK__
__REACTION_PROFILE_HOOK__
}
func installTagPeerBridge() {
    var hooks = PeerInfoNavigationHooks.shared
__TAG_PEER_BRIDGE__
    PeerInfoNavigationHooks.shared = hooks
}
func installTagChatBridge() {
    var hooks = ChatNavigationHooks.shared
__TAG_CHAT_BRIDGE__
    ChatNavigationHooks.shared = hooks
}
func installTagParticipantBridge() {
    var hooks = ChatHistoryUIHooks()
__TAG_PARTICIPANT_BRIDGE__
    ChatHistoryUIHooks.shared = hooks
}
final class TagRow {
    let context: AccountContext
    let chatInteraction: ChatInteraction
    var message: Message?
    var adminBadgeCanEdit = false
    var adminBadgeAuthorId: PeerId? = 3
    var adminBadge: BadgeText? = BadgeText(attributedString: NSAttributedString(string: "  helper  "))
    var adminBadgeRankType = AdminBadgeType.admin
    init(_ context: AccountContext, origin: AnalyticsContext, message: Message?) {
        self.context = context; self.message = message
        self.chatInteraction = ChatInteraction(context, location: .peer(2))
        chatInteraction.peer = TelegramChannel(2); chatInteraction.inheritedAnalyticsContext = origin
    }
__TAG_ROW__
}
struct GroupTagArguments { let context: AccountContext; let analyticsContext: AnalyticsContext }
func groupTagCallback(context: AccountContext, origin: AnalyticsContext, participant: RenderedChannelParticipant) -> (NSView) -> Void {
    let arguments = GroupTagArguments(context: context, analyticsContext: origin)
    let sortedParticipants = [participant]; let i = 0
    let channel: TelegramChannel? = TelegramChannel(2)
    let tag = "helper"; let badgeType = AdminBadgeType.admin
    var badgeAction: ((NSView) -> Void)?
__TAG_GROUP_BADGE__
    return badgeAction!
}
extension MemberManager {
    func fetchParticipant(peerId: PeerId, participantId: PeerId) -> Signal<RenderedChannelParticipant?, NoError> {
        TagProbe.check?(); TagProbe.fetches.append((peerId, participantId))
        return Signal { sink in
            TagProbe.check?(); TagProbe.fetchSink = sink
            return ActionDisposable { TagProbe.check?(); TagProbe.disposals += 1 }
        }
    }
}
enum TagProbe {
    static var check: (() -> Void)?
    static var modal: TagModal?
    static var dismiss: (() -> Void)?
    static var config: UserTagInfoConfiguration?
    static var renders = 0
    static var closes = 0
    static var disposals = 0
    static var deferRendering = false
    static var renderGate = ValuePromise<Bool>(false, ignoreRepeated: true)
    static var fetches: [(PeerId, PeerId)] = []
    static var fetchSink: Subscriber<RenderedChannelParticipant?, NoError>?
    static var morph: (() -> NSView?)?
    static func reset() {
        check = nil; modal = nil; dismiss = nil; config = nil; renders = 0; closes = 0; disposals = 0
        deferRendering = false; renderGate = ValuePromise<Bool>(false, ignoreRepeated: true)
        fetches = []; fetchSink = nil; morph = nil
    }
}
final class MemberTagContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    let selected = RenderedChannelParticipant(peer: Peer(3), participant: ChannelParticipant(peerId: 3))
    override func setUp() {
        TagProbe.reset(); MemberProbe.reset(); GroupProbe.reset(); MediaProbe.created = []; Probe.construction = nil
        Analytics.shared = Analytics(); context = AccountContext(); hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installTagPeerBridge(); installTagChatBridge(); installTagParticipantBridge()
    }
    override func tearDown() { TagProbe.reset(); MemberProbe.reset(); GroupProbe.reset(); MediaProbe.created = []; context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func message(secret: Bool = false, peerId: PeerId = 2) -> Message { Message(id: MessageId(peerId: peerId, id: 1), author: Peer(3), containsSecretMedia: secret) }
    func row(_ source: AnalyticsContext? = nil, secret: Bool = false) -> TagRow { TagRow(context, origin: source ?? origin(), message: message(secret: secret)) }
    func expectExcluded() {
        TagProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }; MemberProbe.check = TagProbe.check
    }
    func testChatInformationKeepsExactScopeAndDisplayValues() {
        let source = origin(); let row = row(source); row.adminBadgeInteraction(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(TagProbe.modal?.content.analyticsContext?.scope === source.scope)
        XCTAssertEqual(TagProbe.config?.tag, "helper"); XCTAssertEqual(TagProbe.config?.authorName, "member")
        XCTAssertEqual(TagProbe.config?.canEditRank, false); XCTAssertEqual(TagProbe.fetches.count, 0)
    }
    func testSecretMediaInformationAndDismissalRemainExcluded() {
        let row = row(secret: true); expectExcluded(); row.adminBadgeInteraction(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
        TagProbe.dismiss?(); TagProbe.modal?.interactions.accept()
        XCTAssertEqual(TagProbe.closes, 2)
        TagProbe.modal = nil; XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPrivateBadgeAuthorRestrictsInformationBeforeConstruction() {
        let row = row(); row.adminBadgeAuthorId = -3
        expectExcluded(); row.adminBadgeInteraction(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testPrivateMessageAuthorRestrictsInformationBeforeConstruction() {
        let row = row(); row.message?.author = Peer(-3)
        expectExcluded(); row.adminBadgeInteraction(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testMissingMessageFailsClosedWithoutBlockingInformation() {
        let row = TagRow(context, origin: origin(), message: nil)
        expectExcluded(); row.adminBadgeInteraction(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testGroupCallbackAfterOwnerLossRetainsPrivateSource() {
        let callback = groupTagCallback(context: context, origin: origin(.excluded), participant: selected)
        expectExcluded(); callback(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
        XCTAssertEqual(TagProbe.config?.tag, "helper")
    }
    func testGroupCallbackRejectsPrivateRepresentedMember() {
        let callback = groupTagCallback(context: context, origin: origin(), participant: RenderedChannelParticipant(peer: Peer(3), participant: ChannelParticipant(peerId: -4)))
        expectExcluded(); callback(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testEditableBadgeKeepsSourceThroughFetchAndMorph() {
        let source = origin(); let row = row(source); row.adminBadgeCanEdit = true
        let view = NSView(); row.adminBadgeInteraction(view)
        XCTAssertEqual(TagProbe.fetches.first?.0, 2); XCTAssertEqual(TagProbe.fetches.first?.1, 3)
        TagProbe.fetchSink?.putNext(selected); TagProbe.fetchSink?.putCompletion()
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(TagProbe.morph?() === view); XCTAssertEqual(TagProbe.disposals, 1)
    }
    func testSecretEditableBadgeProtectsFetchAndReturnedDialog() {
        let row = row(secret: true); row.adminBadgeCanEdit = true; expectExcluded()
        row.adminBadgeInteraction(NSView()); XCTAssertTrue(hub.policy.hasExclusions)
        TagProbe.fetchSink?.putNext(selected); TagProbe.fetchSink?.putCompletion()
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRowLossSkipsOpeningAndKeepsLookupPrivateUntilCompletion() {
        var row: TagRow? = self.row(origin(.excluded)); row!.adminBadgeCanEdit = true
        expectExcluded(); row!.adminBadgeInteraction(NSView()); row = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        TagProbe.fetchSink?.putNext(selected); TagProbe.fetchSink?.putCompletion()
        XCTAssertNil(MemberProbe.modal); XCTAssertEqual(TagProbe.disposals, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPrivateRequestedAuthorProtectsProviderConstruction() {
        let row = row(); row.adminBadgeCanEdit = true; row.adminBadgeAuthorId = -3
        expectExcluded(); row.adminBadgeInteraction(NSView())
        TagProbe.fetchSink?.putNext(selected); TagProbe.fetchSink?.putCompletion()
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
    }
    func testPrivateReturnedParticipantIsClassifiedBeforeConstruction() {
        let row = row(); row.adminBadgeCanEdit = true; row.adminBadgeInteraction(NSView())
        MemberProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        TagProbe.fetchSink?.putNext(RenderedChannelParticipant(peer: Peer(3), participant: ChannelParticipant(peerId: -4)))
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
        TagProbe.fetchSink?.putCompletion()
    }
    func testAccountChangeDuringLookupCannotRenewOrigin() {
        let row = row(); row.adminBadgeCanEdit = true; row.adminBadgeInteraction(NSView())
        let other = AccountContext(); hub.policy.setOwner(other.account); expectExcluded()
        TagProbe.fetchSink?.putNext(selected); TagProbe.fetchSink?.putCompletion()
        XCTAssertNil(MemberProbe.modal?.analyticsContext?.scope)
    }
    func testMissingParticipantKeepsNoOpenBehavior() {
        let row = row(origin(.excluded)); row.adminBadgeCanEdit = true; expectExcluded(); row.adminBadgeInteraction(NSView())
        TagProbe.fetchSink?.putNext(nil); TagProbe.fetchSink?.putCompletion()
        XCTAssertNil(MemberProbe.modal); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testDelayedRenderingRetainsPrivateContext() {
        TagProbe.deferRendering = true; let row = row(origin(.excluded)); expectExcluded(); row.adminBadgeInteraction(NSView())
        XCTAssertEqual(TagProbe.renders, 0); XCTAssertTrue(hub.policy.hasExclusions)
        TagProbe.renderGate.set(true); XCTAssertEqual(TagProbe.renders, 1)
        TagProbe.modal = nil; XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRenderingAfterAccountChangeDoesNotRegainScope() {
        TagProbe.deferRendering = true; let row = row(); row.adminBadgeInteraction(NSView())
        let other = AccountContext(); hub.policy.setOwner(other.account); expectExcluded()
        TagProbe.renderGate.set(true); XCTAssertEqual(TagProbe.renders, 1)
        XCTAssertFalse(TagProbe.modal?.analyticsContext?.scope?.isValid == true)
    }
    func testLegacyTagBridgesAndDisabledEditingRemainFunctional() {
        hub.policy.isEnabled = false; expectExcluded()
        ChatNavigationHooks.shared.showUserTagInfoWithContext = nil
        PeerInfoNavigationHooks.shared.showUserTagInfoWithContext = nil
        ChatHistoryUIHooks.shared.makeChannelParticipantControllerWithContext = nil
        let row = row(); row.adminBadgeInteraction(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true); TagProbe.modal = nil
        groupTagCallback(context: context, origin: origin(.excluded), participant: selected)(NSView())
        XCTAssertTrue(TagProbe.modal?.analyticsContext?.isExcluded == true); TagProbe.modal = nil
        row.adminBadgeCanEdit = true; row.adminBadgeInteraction(NSView())
        TagProbe.fetchSink?.putNext(selected); TagProbe.fetchSink?.putCompletion()
        XCTAssertTrue(MemberProbe.modal?.analyticsContext?.isExcluded == true)
    }
}
