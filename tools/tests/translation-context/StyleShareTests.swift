typealias Control = Int
typealias TelegramMediaFile = Int
extension Context { var meUrlPrefix: String { "https://example.invalid/" } }
__TRANSLATE_HOOKS__
struct SharedStyle { let slug: String? }
enum StyleShareProbe {
    static var link: String?
    static var origin: AnalyticsContext?
    static var factories = 0
    static func reset() { link = nil; origin = nil; factories = 0 }
}
struct ShareLinkObject {
    let context: Context
    let link: String
    init(_ context: Context, link: String) { Probe.check?(); self.context = context; self.link = link }
}
func ShareModalController(_ object: ShareLinkObject, analyticsContext: AnalyticsContext) -> Modal {
    Probe.check?(); StyleShareProbe.link = object.link; StyleShareProbe.origin = analyticsContext; StyleShareProbe.factories += 1
    let presentation = analyticsContext.beginPresentation()
    let controller = Controller(.single(.init(entries: [])))
    controller.analyticsContext = analyticsContext
    controller.onDeinit = { presentation.end() }
    let modal = Modal(controller); modal.analyticsContext = analyticsContext
    return modal
}
func styleShareHooks(_ fallback: @escaping (Context, String) -> Void = { _, _ in }) -> TranslateUIHooks {
    TranslateUIHooks(showAboutCocoonModal: { _ in }, shareLink: fallback, followResolvedName: { _, _, _ in }, showStyleEmojiPicker: { _, _, _ in })
}
func installStyleShareBridge() {
    var hooks = styleShareHooks()
__SHARE_BRIDGE__
    TranslateUIHooks.install(hooks)
}
func styleShareAction(_ context: Context, slug: String? = "sample", getAnalyticsContext: @escaping () -> AnalyticsContext) -> () -> Void {
    let style = SharedStyle(slug: slug)
    return {
__SHARE_ACTION__
    }
}
final class StyleShareTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.check = nil; EntryProbe.presented = nil; StyleShareProbe.reset()
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        installStyleShareBridge()
    }
    override func tearDown() {
        Probe.check = nil; EntryProbe.presented = nil; StyleShareProbe.reset()
        TranslateUIHooks.install(.placeholder); super.tearDown()
    }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func excluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testOrdinaryStyleSharePreservesExactScopeAndExistingLink() {
        let source = origin()
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        styleShareAction(context, getAnalyticsContext: { source })()
        XCTAssertTrue(StyleShareProbe.origin?.scope === source.scope)
        XCTAssertTrue(EntryProbe.presented?.analyticsContext?.scope === source.scope)
        XCTAssertEqual(StyleShareProbe.link, "https://example.invalid/addstyle/sample")
        XCTAssertEqual(StyleShareProbe.factories, 1)
    }
    func testPrivateAndUnknownShareActionsRemainExcludedAfterParentRelease() {
        for id: PeerId in [-1, 0] {
            excluded()
            var parent: Modal? = makeTranslation(context, analyticsContext: origin(id))
            let action = styleShareAction(context, getAnalyticsContext: parent!.getOrigin)
            parent = nil; XCTAssertFalse(hub.policy.hasExclusions)
            action()
            XCTAssertTrue(StyleShareProbe.origin!.isExcluded)
            XCTAssertTrue(hub.policy.hasExclusions)
            EntryProbe.presented = nil; XCTAssertFalse(hub.policy.hasExclusions)
        }
        XCTAssertEqual(StyleShareProbe.factories, 2)
    }
    func testRetainedActionCannotReacquireScopeAfterRevocation() {
        let source = origin()
        var parent: Modal? = makeTranslation(context, analyticsContext: source)
        let action = styleShareAction(context, getAnalyticsContext: parent!.getOrigin)
        parent = nil; source.scope?.exclude()
        excluded(); action()
        XCTAssertTrue(StyleShareProbe.origin!.isExcluded)
    }
    func testObservedHookRejectsForeignAccountBeforeObjectConstruction() {
        let source = origin(); hub.policy.setOwner(Account()); excluded()
        TranslateUIHooks.shared.shareLinkObserved(context, "link", analyticsContext: source)
        XCTAssertTrue(StyleShareProbe.origin?.scope?.isValid != true)
        XCTAssertEqual(StyleShareProbe.link, "link")
    }
    func testLegacyShareFallbackKeepsInvocationGuard() {
        var calls = 0
        TranslateUIHooks.install(styleShareHooks { _, link in
            Probe.check?(); calls += 1; XCTAssertEqual(link, "https://example.invalid/addstyle/sample")
        })
        excluded()
        styleShareAction(context, getAnalyticsContext: { self.origin(-1) })()
        XCTAssertEqual(calls, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testNoSlugDoesNotPresentPicker() {
        excluded(); styleShareAction(context, slug: nil, getAnalyticsContext: { self.origin(-1) })()
        XCTAssertEqual(StyleShareProbe.factories, 0); XCTAssertNil(EntryProbe.presented)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testDisabledCollectionStillShares() {
        hub.policy.isEnabled = false; excluded()
        styleShareAction(context, getAnalyticsContext: { self.origin() })()
        XCTAssertEqual(StyleShareProbe.factories, 1)
        XCTAssertTrue(StyleShareProbe.origin?.scope?.isValid != true)
        EntryProbe.presented = nil; XCTAssertFalse(hub.policy.hasExclusions)
    }
}
