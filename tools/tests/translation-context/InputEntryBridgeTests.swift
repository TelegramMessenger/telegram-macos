struct InputTextViewHooks {
    static var shared = InputTextViewHooks()
    var showTranslate: (Context, Int, String?, String, @escaping (NSAttributedString) -> Void) -> Void = { _, _, _, _, _ in }
    var showPremiumBoarding: (Context, Int) -> Void = { _, _ in }
__INPUT_HOOKS__
}
struct AppAppearance { let languageCode = "fr" }
let appAppearance = AppAppearance()
enum EntryProbe {
    static var presented: Modal?
    static var arguments: [String?] = []
}
func showModal(with controller: Modal, for window: Int) { Probe.check?(); EntryProbe.presented = controller }
func TranslateModalController(context: Context, from: String?, toLang: String, text: String, onUse: @escaping (NSAttributedString) -> Void, analyticsContext: AnalyticsContext) -> Modal {
    Probe.check?(); EntryProbe.arguments = [from, toLang, text]
    var state = State(); state.translated = "result"
    return makeTranslation(context, analyticsContext: analyticsContext, initialState: state, onUse: onUse)
}
func installInputEntryBridge() {
    var hooks = InputTextViewHooks()
__INPUT_BRIDGES__
    InputTextViewHooks.shared = hooks
}
final class InputEntryBridgeTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; EntryProbe.presented = nil; EntryProbe.arguments = []
        FeatureNavigationHooks.shared = FeatureNavigationHooks()
        installInputEntryBridge()
    }
    override func tearDown() {
        Probe.check = nil; EntryProbe.presented = nil
        InputTextViewHooks.shared = InputTextViewHooks(); FeatureNavigationHooks.shared = FeatureNavigationHooks()
        super.tearDown()
    }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func testOrdinaryBridgePassesExactScopeAndLanguageArguments() {
        let source = origin()
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        var result: NSAttributedString?
        InputTextViewHooks.shared.showTranslateObserved(context, 1, "en", "input", analyticsContext: source, onUse: { result = $0 })
        XCTAssertEqual(EntryProbe.arguments, ["en", "fr", "input"])
        XCTAssertTrue(EntryProbe.presented?.analyticsContext?.scope === source.scope)
        EntryProbe.presented?.interactions?.accept()
        XCTAssertEqual(result?.string, "result")
        XCTAssertNil(result?.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil))
    }
    func testPrivateBridgeAndCompletionRetainExclusionAfterModalRelease() {
        let source = origin(-1)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var result: NSAttributedString?
        InputTextViewHooks.shared.showTranslateObserved(context, 1, nil, "input", analyticsContext: source, onUse: { Probe.check?(); result = $0 })
        XCTAssertTrue(EntryProbe.presented!.analyticsContext!.isExcluded)
        let accept = EntryProbe.presented!.interactions!.accept
        EntryProbe.presented = nil; XCTAssertFalse(hub.policy.hasExclusions)
        accept()
        XCTAssertEqual(result?.string, "result")
        XCTAssertNotNil(result?.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil))
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPremiumBridgePreservesTranslationsSourceAndContext() {
        let source = origin(-1)
        var called = false
        FeatureNavigationHooks.shared.showPremiumBoardingWithContext = { _, window, kind, features, _, inherited in
            called = true; XCTAssertEqual(window, 1); XCTAssertEqual(kind, .translations); XCTAssertTrue(features)
            XCTAssertTrue(inherited.isExcluded); XCTAssertTrue(self.hub.policy.hasExclusions)
        }
        InputTextViewHooks.shared.showPremiumBoardingObserved(context, 1, analyticsContext: source)
        XCTAssertTrue(called); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPremiumTranslationSourceMapsToExistingFeature() {
        XCTAssertEqual(PremiumBoardingSource.translations.logSource, .translations)
        XCTAssertEqual(PremiumBoardingSource.aiCompose.logSource, .ai_compose)
    }
    func testAccountChangedBeforeEntryCannotRegainEligibility() {
        let source = origin(); hub.policy.setOwner(Account())
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        var result: NSAttributedString?
        InputTextViewHooks.shared.showTranslateObserved(context, 1, nil, "input", analyticsContext: source, onUse: { result = $0 })
        XCTAssertTrue(EntryProbe.presented!.analyticsContext!.scope?.isValid != true)
        EntryProbe.presented!.interactions!.accept()
        XCTAssertNotNil(result?.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil))
    }
}
