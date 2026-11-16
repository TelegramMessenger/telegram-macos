enum JSON: Equatable { case string(String) }
__EVENT_NAMES__
__EVENT__
enum AnalyticsEvents {
__EVENT_ENUMS__
__SAVED_TAG_EVENT_ENUM__
__EVENT_BUILDER__
__SAVED_TAG_EVENT_BUILDER__
}
extension Analytics {
    func send(_ event: @autoclosure () -> AnalyticsEvent, scope: AnalyticsScope?) {
        policy.sync {
            guard policy.accepts(scope) else { return }
            RecommendationProbe.events.append(event())
        }
    }
}
__SIMILAR_HOOKS__
__SIMILAR_BRIDGE__
final class Arguments {
    let openInfo: (PeerId) -> Void
    let premium: () -> Void
    init(context: any AccountContextProtocol, openInfo: @escaping (PeerId) -> Void, premium: @escaping () -> Void) { self.openInfo = openInfo; self.premium = premium }
}
extension AccountContextProtocol { var window: Int { 0 } }
final class PremiumBoardingController: ViewController {
    enum Source { case recommended_channels, saved_tags, message_effects }
    let source: Source
    let openFeatures: Bool
    init(context: any AccountContextProtocol, source: Source, openFeatures: Bool = false, analyticsContext: AnalyticsContext) {
        self.source = source; self.openFeatures = openFeatures
        super.init(); Probe.construction?(); self.analyticsContext = analyticsContext
    }
}
func prem(with controller: PremiumBoardingController, for window: Int, morphSource: (() -> AnyObject?)? = nil) { Probe.construction?(); RecommendationProbe.premium.append(controller); SavedPremiumProbe.morph = morphSource }
enum RecommendationProbe {
    static var events: [AnalyticsEvent] = []
    static var premium: [PremiumBoardingController] = []
}
func SimilarChannelsController(context: AccountContext, peerId: PeerId, recommendedChannels: Int?, analyticsContext: AnalyticsContext? = nil) -> InputDataController {
__CHANNEL_PREFIX__
    Probe.construction?()
__CHANNEL_ACTIONS__
    let controller = InputDataController("similarChannels")
__CHANNEL_CONTEXT__
    controller.selectRecommendation = arguments.openInfo
    controller.selectPremium = arguments.premium
    return controller
}
func SimilarBotsController(context: AccountContext, peerId: PeerId, recommendedBots: Int?, analyticsContext: AnalyticsContext? = nil) -> InputDataController {
__BOT_PREFIX__
    Probe.construction?()
__BOT_ACTIONS__
    let controller = InputDataController("similarBots")
__BOT_CONTEXT__
    controller.selectRecommendation = arguments.openInfo
    controller.selectPremium = arguments.premium
    return controller
}
final class RecommendationContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = AccountContext()
        hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        Probe.childOrigin = nil; Probe.construction = nil; Probe.media = []
        MediaProbe.created = []; MediaProbe.interactions = []
        RecommendationProbe.events = []; RecommendationProbe.premium = []
        installSimilarPeersUIHooks()
    }
    override func tearDown() {
        Probe.construction = nil; Probe.childOrigin = nil
        MediaProbe.created = []; MediaProbe.interactions = []
        RecommendationProbe.events = []; RecommendationProbe.premium = []; context = nil
    }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func make(_ bot: Bool = false, _ origin: AnalyticsContext? = nil) -> InputDataController {
        if bot { return SimilarBotsController(context: context, peerId: 2, recommendedBots: nil, analyticsContext: origin) }
        return SimilarChannelsController(context: context, peerId: 2, recommendedChannels: nil, analyticsContext: origin)
    }
    func testConstructionRecordsNothingAndPeerSelectionCarriesOnlyCategories() {
        for bot in [false, true] {
            RecommendationProbe.events = []
            let source = origin(); let controller = make(bot, source)
            XCTAssertTrue(RecommendationProbe.events.isEmpty)
            controller.selectRecommendation(3)
            XCTAssertEqual(RecommendationProbe.events.count, 1)
            XCTAssertEqual(RecommendationProbe.events.last?.params, ["kind": .string(bot ? "bot" : "channel"), "selection": .string("peer")])
            XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.scope === source.scope)
        }
    }
    func testPremiumSelectionIsIntentAndCarriesOriginalScope() {
        let source = origin(); let controller = make(true, source)
        controller.selectPremium()
        XCTAssertEqual(RecommendationProbe.events.count, 1)
        XCTAssertEqual(RecommendationProbe.events.last?.params, ["kind": .string("bot"), "selection": .string("premium")])
        XCTAssertTrue(RecommendationProbe.premium.last?.analyticsContext?.scope === source.scope)
        XCTAssertTrue(context.bindings.navigation.pushed.isEmpty)
    }
    func testPrivateOriginSurvivesClosingRecommendationScreenBeforeSelection() {
        var controller: InputDataController? = make(false, origin(.excluded))
        let select = controller!.selectRecommendation; let premium = controller!.selectPremium
        MediaProbe.created = []; controller = nil
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        select(3); premium()
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
        XCTAssertTrue(RecommendationProbe.premium.last?.analyticsContext?.isExcluded == true)
    }
    func testUnknownOriginsAreFunctionalAndSilent() {
        let controller = make()
        controller.selectRecommendation(3); controller.selectPremium()
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        XCTAssertEqual(context.bindings.navigation.pushed.count, 1)
        XCTAssertEqual(RecommendationProbe.premium.count, 1)
        XCTAssertTrue(controller.analyticsContext?.isExcluded == true)
    }
    func testSecretDestinationIsClassifiedBeforeEventAndChatConstruction() {
        let controller = make(false, origin())
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        controller.selectRecommendation(-3)
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
    }
    func testRevokedScopeCannotEmitOrBeRefreshedAtSelection() {
        let source = origin(); let controller = make(false, source)
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        controller.selectRecommendation(3); controller.selectPremium()
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        XCTAssertNil(context.bindings.navigation.pushed.last?.analyticsContext?.scope)
        XCTAssertFalse(RecommendationProbe.premium.last?.analyticsContext?.scope?.isValid == true)
    }
    func testAccountSwitchCannotEmitOrRefreshScope() {
        let controller = make(false, origin()); let other = AccountContext()
        hub.policy.setOwner(other.account)
        controller.selectRecommendation(3); controller.selectPremium()
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        XCTAssertNil(context.bindings.navigation.pushed.last?.analyticsContext?.scope)
    }
    func testDisabledAnalyticsKeepsBothActionsFunctional() {
        hub.policy.isEnabled = false
        let controller = make(true, origin()); controller.selectRecommendation(3); controller.selectPremium()
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
        XCTAssertEqual(context.bindings.navigation.pushed.count, 1); XCTAssertEqual(RecommendationProbe.premium.count, 1)
    }
    func testForeignAccountOriginIsRejectedBeforeConstruction() {
        let other = AccountContext(); hub.policy.setOwner(other.account)
        let foreign = hub.captureContext(owner: other.account, privacy: .ordinary)
        hub.policy.setOwner(context.account)
        Probe.construction = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let controller = make(false, foreign); controller.selectRecommendation(3)
        XCTAssertTrue(RecommendationProbe.events.isEmpty); XCTAssertNil(controller.analyticsContext?.scope)
    }
    func testLegacyBridgeFallbackRemainsExcludedAfterOpening() {
        var hooks = SimilarPeersHooks.shared; hooks.openChatWithContext = nil; SimilarPeersHooks.install(hooks)
        let controller = make(true, origin(.excluded)); controller.selectRecommendation(3)
        XCTAssertTrue(context.bindings.navigation.pushed.last?.analyticsContext?.isExcluded == true)
        XCTAssertTrue(RecommendationProbe.events.isEmpty)
    }
    func testParentMediaPassesScopeAndTighteningExcludesCapturedCallbacks() {
        let source = origin(); let media = PeerMediaController(context: context, peerId: 2, isBot: false, analyticsContext: source)
        let channels = media.similarChannels as! InputDataController
        let bots = media.similarBots as! InputDataController
        channels.selectRecommendation(3); bots.selectPremium()
        XCTAssertEqual(RecommendationProbe.events.count, 2)
        media.inheritAnalyticsContext(origin(.excluded))
        channels.selectRecommendation(4); bots.selectPremium()
        XCTAssertEqual(RecommendationProbe.events.count, 2)
        XCTAssertTrue(RecommendationProbe.premium.last?.analyticsContext?.isExcluded == true)
    }
    func testRepeatedExecutedSelectionsRemainSeparateIntents() {
        let controller = make(false, origin())
        controller.selectRecommendation(3); controller.selectRecommendation(3)
        XCTAssertEqual(RecommendationProbe.events.count, 2)
    }
}
