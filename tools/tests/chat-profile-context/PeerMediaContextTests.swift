typealias Context = AccountContext
struct Namespaces { struct Peer { static let CloudUser = 1; static let CloudChannel = 2 } }
extension Int64 { var namespace: Int { self < 0 ? -1 : (self >= 1000 ? 2 : 1) } }
extension Peer { var isBot: Bool { false } }
typealias ProfileGiftsContext = Int
struct ExternalSearchMessages { let title: String? }
struct PeerMediaExternalSearchData {
    let initialMode: Int?
    let searchResult: Signal<ExternalSearchMessages?, NoError>
    let loadMore: () -> Void
}
struct MediaTag { let tagsValue: Set<Int> }
class MediaBase: ViewController {
    let context: AccountContext
    init(_ context: AccountContext) { self.context = context; super.init() }
}
class MediaSurface: ViewController {
    init(_ name: String) { super.init(); Probe.construction?(); analyticsContext = Probe.childOrigin; MediaProbe.created.append((name, self)) }
}
final class InputDataController: MediaSurface {
    var commonSubscription = MetaDisposable()
    var title = ""
    var entries: [CommonEntry] = []
    var analyticsScreen: CommonScreen?
    var bar = CommonBar(height: 0)
    var contextObject: AnyObject?
    var onDeinit: (() -> Void)?
    var getBackgroundColor: (() -> CommonColor)?
    var didLoad: ((InputDataController, Int) -> Void)?
    let tableView = CommonTable()
    deinit { commonSubscription.dispose(); onDeinit?() }
    var selectRecommendation: (PeerId) -> Void = { _ in }
    var selectPremium: () -> Void = {}
    var interaction: ChatInteraction?
    var focus: ((MessageId?, ChatFocusTarget, TableScrollState) -> Void)?
    var opened: (PeerId, Bool, MessageId?, ChatInitialAction?, AnalyticsContext) -> Void = { _, _, _, _, _ in }
}
class StoryListContext {}
func BotPreviewStoryListContext(account: Account, engine: Engine, peerId: PeerId, language: String?, assumeEmpty: Bool) -> StoryListContext { Probe.construction?(); return StoryListContext() }
func PeerStoryListContext(account: Account, peerId: PeerId, isArchived: Bool, folderId: Int?) -> StoryListContext { Probe.construction?(); return StoryListContext() }
extension AccountContextProtocol { var account: Account { engine.account } }
func SavedPeersController(context: AccountContext) -> InputDataController { InputDataController("savedPeers") }
func PeerMediaGiftsController(context: AccountContext, peerId: PeerId, starGiftsProfile: ProfileGiftsContext?) -> ViewController { MediaSurface("gifts") }
struct PeerInfoNavigationHooks {
    static var shared = makeCommonFactoryHooks()
__COMMON_FACTORY_HOOK__
__MEMBER_LIST_HOOKS__
__TAG_PEER_HOOK__
}
final class PeerMediaPhotosController<C>: MediaSurface {
    enum Tags { case photoOrVideo, gif }
    init(_ context: C, chatInteraction: ChatInteraction, threadInfo: ThreadInfo?, peerId: PeerId, tags: Tags) { super.init(tags == .gif ? "gifs" : "grid"); MediaProbe.interactions.append(chatInteraction) }
}
final class PeerMediaListController<C>: MediaSurface {
    init(context: C, peerId: PeerId, threadInfo: ThreadInfo?, chatInteraction: ChatInteraction) { super.init("list"); MediaProbe.interactions.append(chatInteraction) }
}
final class StoryMediaController<C>: MediaSurface {
    init(context: C, peerId: PeerId, listContext: StoryListContext, isArchived: Bool = false) { super.init(isArchived ? "archiveStories" : "stories") }
}
extension ChatInteraction {
    convenience init(chatLocation: ChatLocation, context: AccountContext, mode: ChatMode = .history, isPeerSavedMessages: Bool = false) { self.init(context, location: chatLocation, mode: mode) }
}
final class PeerMediaController: MediaBase {
    var navigationController: NavigationViewController? { context.bindings.navigation }
    let peerId: PeerId
    let externalSearchData: PeerMediaExternalSearchData?
    let mode: Int?
    let threadInfo: ThreadInfo?
    let isProfileIntended: Bool
    let initialMode: Int?
    let starGiftsProfile: ProfileGiftsContext?
    var savedMessages: InputDataController?
    var gifts: ViewController?
    var interactions: ChatInteraction
    let mediaGrid: PeerMediaPhotosController<Context>
    let storyListContext: StoryListContext
    let archiveStoryListContext: StoryListContext?
    let archiveStories: StoryMediaController<Context>?
    let saved: InputDataController
    let modeValue = ValuePromise<Int?>(nil, ignoreRepeated: true)
    let externalDisposable = MetaDisposable()
    let tagsList = [MediaTag(tagsValue: [1]), MediaTag(tagsValue: [2]), MediaTag(tagsValue: [])]
    let editing = ValuePromise(false, ignoreRepeated: true)
    let listControllers: [PeerMediaListController<Context>]
    let members: ViewController
    let commonGroups: ViewController
    let gifs: PeerMediaPhotosController<Context>
    let stories: StoryMediaController<Context>
    let similarChannels: ViewController
    let similarBots: ViewController
    var pollsController: InputDataController?
__MEDIA_INIT__
        Probe.media.append((peerId, threadInfo))
    }
__MEDIA_INHERIT__
    func polls() -> InputDataController {
__PREPARE_ORIGIN__
__POLL_FACTORY__
        return pollsController!
    }
    func installNavigation() {
        let context = self.context
        let peerId = self.peerId
        let threadInfo = self.threadInfo
        let interactions = self.interactions
__MEDIA_OPEN_CHAT__
__MEDIA_OPEN_INFO__
    }
    deinit { externalDisposable.dispose() }
}
enum MediaProbe {
    static var created: [(String, ViewController)] = []
    static var interactions: [ChatInteraction] = []
    static var navigationMode: ChatMode?
}
final class ChatAdditionController: ViewController {
    let interaction: ChatInteraction
    init(context: AccountContext, chatLocation: ChatLocation, focusTarget: ChatFocusTarget? = nil) {
        interaction = ChatInteraction(context, location: chatLocation); super.init(); Probe.construction?()
    }
    func inheritAnalyticsContext(_ origin: AnalyticsContext) { analyticsContext = origin; interaction.inheritedAnalyticsContext = origin }
}
func PeerMediaSavedMessagesController(context: AccountContext, peerId: PeerId, analyticsContext: AnalyticsContext? = nil) -> InputDataController {
__SAVED_ORIGIN__
    let chatInteraction = ChatInteraction(context, location: .peer(peerId))
__SAVED_INTERACTION__
__SAVED_OPEN__
    let controller = InputDataController("saved")
__SAVED_CONTEXT__
    controller.interaction = chatInteraction
    controller.focus = chatInteraction.focusMessageId
    return controller
}
func PeerMediaPollsController(context: AccountContext, peerId: PeerId, analyticsContext: AnalyticsContext? = nil) -> InputDataController {
__POLLS_ORIGIN__
    let chatInteraction = ChatInteraction(context, location: .peer(peerId))
__POLLS_INTERACTION__
__POLLS_OPEN__
    let controller = InputDataController("polls")
__POLLS_CONTEXT__
    controller.interaction = chatInteraction
    controller.focus = chatInteraction.focusMessageId
    return controller
}
final class ProfileMediaRoot: ViewController {
    let starGiftsProfile: ProfileGiftsContext? = nil
    let mediaController: PeerMediaController
    init(context: AccountContext, peer: Peer, linkedBotChannelId: PeerId? = nil, analyticsContext: AnalyticsContext? = nil) {
__PROFILE_PREFIX__
        Probe.construction?()
        let threadInfo: ThreadInfo? = nil
        let mediaMode: Int? = nil
__PROFILE_MEDIA__
        super.init()
__PROFILE_CONTEXT__
    }
}

final class PeerMediaContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        Probe.childOrigin = nil; Probe.construction = nil; Probe.profiles = []; Probe.chats = []; Probe.media = []
        MediaProbe.created = []; MediaProbe.interactions = []
        installBridge(); installMediaBridge()
    }
    override func tearDown() { Probe.construction = nil; MediaProbe.created = []; MediaProbe.interactions = []; Probe.childOrigin = nil; Probe.profiles = []; Probe.chats = []; context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func testAllOrdinaryEagerChildrenAndInteractionsShareOriginalScope() {
        let source = origin()
        let media = PeerMediaController(context: context, peerId: 1, isProfileIntended: true, isBot: false, analyticsContext: source)
        XCTAssertEqual(Set(MediaProbe.created.map { $0.0 }), ["gifts", "grid", "archiveStories", "saved", "list", "members", "commonGroups", "gifs", "stories", "similarChannels", "similarBots"])
        for (_, child) in MediaProbe.created { XCTAssertTrue(child.analyticsContext?.scope === source.scope) }
        for interaction in MediaProbe.interactions { XCTAssertTrue(interaction.inheritedAnalyticsContext?.scope === source.scope) }
        XCTAssertTrue(media.saved.interaction?.inheritedAnalyticsContext?.scope === source.scope)
    }
    func testPrivateConstructionAndChildrenRemainExcludedAfterRootRelease() {
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var media: PeerMediaController? = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: origin(.excluded))
        let saved = media!.saved
        weak var weakMedia = media; media = nil
        XCTAssertNil(weakMedia)
        for (_, child) in MediaProbe.created { XCTAssertTrue(child.analyticsContext?.isExcluded == true) }
        XCTAssertTrue(saved.interaction?.inheritedAnalyticsContext?.isExcluded == true)
        saved.interaction?.openInfoFromMessage(3, false, nil, nil, message: Message(id: MessageId(peerId: 2, id: 1)))
        XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
    }
    func testUnknownAndSecretPeerConstructorsCannotGrant() {
        let unknown = PeerMediaController(context: context, peerId: 2, isBot: true)
        XCTAssertTrue(unknown.analyticsContext?.isExcluded == true)
        let secret = PeerMediaController(context: context, peerId: -2, isBot: false, analyticsContext: origin())
        XCTAssertTrue(secret.analyticsContext?.isExcluded == true)
    }
    func testLazyPollsPreserveScopeAndDoNotRecreateController() {
        let source = origin(); let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: source)
        let polls = media.polls()
        XCTAssertTrue(media.polls() === polls)
        XCTAssertTrue(polls.analyticsContext?.scope === source.scope)
        XCTAssertTrue(polls.interaction?.inheritedAnalyticsContext?.scope === source.scope)
    }
    func testLazyPollsAfterRevocationAreProtectedAndCannotRegrant() {
        let source = origin(); let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: source)
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        XCTAssertNil(media.polls().analyticsContext?.scope)
    }
    func testPrivateReuseExcludesPreviouslyCapturedSavedAndPollScopes() {
        let source = origin(); let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: source)
        let polls = media.polls(); let savedOrigin = media.saved.interaction!.captureAnalyticsContext()
        media.inheritAnalyticsContext(origin(.excluded))
        XCTAssertTrue(source.isExcluded); XCTAssertTrue(savedOrigin.isExcluded)
        XCTAssertTrue(polls.interaction?.inheritedAnalyticsContext?.isExcluded == true)
        for (_, child) in MediaProbe.created { XCTAssertTrue(child.analyticsContext?.isExcluded == true) }
    }
    func testReuseCannotReviveUnknownPrivateOrRevokedContainer() {
        let unknown = PeerMediaController(context: context, peerId: 2, isBot: false)
        unknown.inheritAnalyticsContext(origin()); XCTAssertTrue(unknown.analyticsContext?.isExcluded == true)
        let source = origin(); let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: source)
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        media.inheritAnalyticsContext(origin()); XCTAssertNil(media.analyticsContext?.scope)
    }
    func testStricterChildPrivacySurvivesOrdinaryParent() {
        let source = origin(); Probe.childOrigin = origin(.excluded)
        let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: source)
        XCTAssertTrue(media.mediaGrid.analyticsContext?.isExcluded == true)
        XCTAssertTrue(media.stories.analyticsContext?.isExcluded == true)
    }
    func testProfilePassesOriginBeforeMediaAndRejectsLinkedPrivatePeer() {
        let source = origin(); let profile = ProfileMediaRoot(context: context, peer: Peer(2), analyticsContext: source)
        XCTAssertTrue(profile.mediaController.analyticsContext?.scope === source.scope)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let privateProfile = ProfileMediaRoot(context: context, peer: Peer(2), linkedBotChannelId: -3, analyticsContext: source)
        XCTAssertTrue(privateProfile.analyticsContext?.isExcluded == true)
        XCTAssertTrue(privateProfile.mediaController.analyticsContext?.isExcluded == true)
    }
    func testForeignAccountOriginCannotEnterMediaChildren() {
        let source = origin(); let other = AccountContext(); hub.policy.setOwner(other.account)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let media = PeerMediaController(context: other, peerId: 2, isBot: false, analyticsContext: source)
        XCTAssertNil(media.analyticsContext?.scope)
        for (_, child) in MediaProbe.created { XCTAssertNil(child.analyticsContext?.scope) }
    }
    func testSavedAndPollEntityNavigationClassifiesSecretMedia() {
        for factory in [PeerMediaSavedMessagesController, PeerMediaPollsController] {
            let controller = factory(context, 2, origin())
            controller.interaction?.openInfoFromMessage(3, true, nil, nil, message: Message(id: MessageId(peerId: 2, id: 1), containsSecretMedia: true))
            XCTAssertTrue(Probe.chats.last?.origin?.isExcluded == true)
        }
    }
    func testSavedAndPollFocusRetainPrivateOriginBeforeChatConstruction() {
        for factory in [PeerMediaSavedMessagesController, PeerMediaPollsController] {
            let controller = factory(context, 2, origin(.excluded))
            Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            controller.focus?(nil, ChatFocusTarget(messageId: MessageId(peerId: 3, id: 1)), .CenterEmpty)
            XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
        }
    }
    func testExternalSearchDeliveryRetainsExclusionAfterFactoryReturns() {
        var sink: Subscriber<ExternalSearchMessages?, NoError>?
        let signal = Signal<ExternalSearchMessages?, NoError> { sink = $0; return EmptyDisposable }
        let media = PeerMediaController(context: context, peerId: 2, externalSearchData: PeerMediaExternalSearchData(initialMode: nil, searchResult: signal, loadMore: {}), isBot: false, analyticsContext: origin(.excluded))
        XCTAssertTrue(hub.policy.hasExclusions)
        sink?.putNext(ExternalSearchMessages(title: "title")); media.externalDisposable.dispose()
        XCTAssertTrue(hub.policy.hasExclusions)
        (media.commonGroups as? InputDataController)?.commonSubscription.dispose()
        XCTAssertTrue(hub.policy.hasExclusions)
        (media.members as? InputDataController)?.commonSubscription.dispose()
        XCTAssertFalse(hub.policy.hasExclusions)
    }
}

struct ChatLocationContextHolder {}
extension Int {
    var message: ThreadData { ThreadData(peerId: 2, threadId: Int64(self)) }
    var isMonoforumPost: Bool { self < 0 }
    var contextHolder: Atomic<ChatLocationContextHolder?> { Atomic(value: nil) }
}
extension ThreadData { var effectiveTopId: MessageId { MessageId(peerId: peerId, id: Int(threadId)) } }
struct PeerInfoUIHooks {
    static var shared = PeerInfoUIHooks()
    var navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, Atomic<ChatLocationContextHolder?>?) -> Void = { _, _, location, mode, focus, _ in
        Probe.construction?(); MediaProbe.navigationMode = mode
        Probe.chats.append(NavigationCall(peerId: location.peerId, focus: focus, action: nil, additional: false, origin: nil))
    }
__MEDIA_NAV_HOOK__
}
func installMediaBridge() {
    var hooks = PeerInfoUIHooks()
__MEDIA_NAV_BRIDGE__
    PeerInfoUIHooks.shared = hooks
}
func navigateToChat(navigation: NavigationViewController?, context: AccountContext, chatLocation: ChatLocation, mode: ChatMode, focusTarget: ChatFocusTarget?, chatLocationContextHolder: Atomic<ChatLocationContextHolder?>?, analyticsContext: AnalyticsContext) {
    Probe.construction?(); MediaProbe.navigationMode = mode
    Probe.chats.append(NavigationCall(peerId: chatLocation.peerId, focus: focusTarget, action: nil, additional: false, origin: analyticsContext))
}
extension PeerMediaContextTests {
    func testMediaThreadNavigationRetainsOriginalScopeAndThreadMode() {
        let source = origin(); let media = PeerMediaController(context: context, peerId: 2, threadInfo: 9, isBot: false, analyticsContext: source)
        media.installNavigation()
        media.interactions.openInfoFromMessage(2, true, MessageId(peerId: 2, id: 4), nil, message: Message(id: MessageId(peerId: 2, id: 1)))
        XCTAssertEqual(MediaProbe.navigationMode, .thread(mode: .topic(origin: MessageId(peerId: 2, id: 9))))
        XCTAssertTrue(Probe.chats.last?.origin?.scope === source.scope)
    }
    func testMediaMonoforumAndProfileCallbacksKeepPrivateSource() {
        let media = PeerMediaController(context: context, peerId: 2, threadInfo: -9, isBot: false, analyticsContext: origin())
        media.installNavigation()
        let source = Message(id: MessageId(peerId: 2, id: 1), containsSecretMedia: true)
        media.interactions.openInfoFromMessage(2, true, nil, nil, message: source)
        XCTAssertEqual(MediaProbe.navigationMode, .history)
        XCTAssertTrue(Probe.chats.last?.origin?.isExcluded == true)
        media.interactions.openInfoFromMessage(3, false, nil, nil, message: source)
        XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
        XCTAssertEqual(Probe.profiles.last?.thread, -9)
    }
    func testMediaLegacyCallbackAndNavigationFallbackFailClosed() {
        let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: origin())
        media.installNavigation(); media.interactions.openInfo(3, false, nil, nil)
        XCTAssertTrue(Probe.profiles.last?.origin?.isExcluded == true)
        PeerInfoUIHooks.shared.navigateToChatWithContext = nil
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        media.interactions.openInfoFromMessage(3, true, nil, nil, message: Message(id: MessageId(peerId: 2, id: 1), containsSecretMedia: true))
        XCTAssertEqual(Probe.chats.count, 1)
    }
}
